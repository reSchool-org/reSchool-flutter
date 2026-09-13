#!/usr/bin/env python3
"""по умолчанию только читаем, создание профилей и отправка секретов включаются отдельными флагами"""

import argparse
import base64
import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from apple_release import BUNDLE, profile_values

ORIGIN = "https://api.appstoreconnect.apple.com"
BUNDLES = (BUNDLE, BUNDLE + ".ReSchoolWidgets")
TEAM = "AQ52Q995ZR"
REPO = "reSchool-org/reSchool-Flutter-test"
ENVIRONMENT = "apple-ios-testflight"
TARGETS = {
    "ios-testflight": {"bundles": BUNDLES, "profile_type": "IOS_APP_STORE", "platform": "IOS",
                       "certificate_names": ("Apple Distribution:",)},
    "macos-testflight": {"bundles": (BUNDLE, BUNDLE + ".ReSchoolMacWidgets"),
                          "profile_type": "MAC_APP_STORE", "platform": "MAC_OS",
                         "certificate_names": ("Apple Distribution:", "3rd Party Mac Developer Application:")},
    "macos-direct": {"bundles": (BUNDLE, BUNDLE + ".ReSchoolMacWidgets"),
                     "profile_type": "MAC_APP_DIRECT", "platform": "MAC_OS",
                     "certificate_names": ("Developer ID Application:",)},
}


class SafeError(Exception):
    """в терминал можно выводить только заранее заданные локальные коды ошибок"""


def command(*args, data=None):
    try:
        result = subprocess.run(args, input=data, capture_output=True,
                                check=False, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        raise SafeError("SUBPROCESS_UNAVAILABLE_OR_TIMEOUT") from None
    if result.returncode:
        raise SafeError("SUBPROCESS_FAILED") from None
    return result.stdout


def der_to_raw(signature):
    # в jws с es256 лежат два числа фиксированной ширины, а не последовательность asn.1 от openssl
    if len(signature) < 8 or signature[:1] != b"\x30" or signature[1] != len(signature) - 2:
        raise SafeError("INVALID_ES256_SIGNATURE")
    offset, result = 2, b""
    order = int("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551", 16)
    for _ in range(2):
        if offset + 2 > len(signature) or signature[offset] != 2:
            raise SafeError("INVALID_ES256_SIGNATURE")
        size = signature[offset + 1]
        value = signature[offset + 2:offset + 2 + size]
        if (not 1 <= size <= 33 or len(value) != size or value[0] & 0x80
                or (size > 1 and value[0] == 0 and not value[1] & 0x80)):
            raise SafeError("INVALID_ES256_SIGNATURE")
        number = int.from_bytes(value, "big")
        if not 0 < number < order:
            raise SafeError("INVALID_ES256_SIGNATURE")
        result += number.to_bytes(32, "big")
        offset += 2 + size
    if offset != len(signature):
        raise SafeError("INVALID_ES256_SIGNATURE")
    return result


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def make_jwt(key_path, key_id, issuer):
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer, "iat": now - 10, "exp": now + 240,
               "aud": "appstoreconnect-v1"}
    signing_input = b".".join(b64url(json.dumps(part, separators=(",", ":")).encode())
                              for part in (header, payload))
    signature = command("openssl", "dgst", "-sha256", "-sign", str(key_path),
                        data=signing_input)
    return (signing_input + b"." + b64url(der_to_raw(signature))).decode("ascii")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise SafeError("HTTP_REDIRECT_BLOCKED")


class AppleClient:
    def __init__(self, key_path, key_id, issuer, *, allow_create=False):
        self.credentials = (key_path, key_id, issuer)
        self.allow_create = allow_create
        self.opener = urllib.request.build_opener(NoRedirect())

    def get(self, url):
        return self._request(url)

    def create_profile(self, bundle, bundle_id, certificate_id, *, target="ios-testflight"):
        config = TARGETS[target]
        if bundle not in config["bundles"]:
            raise SafeError("UNEXPECTED_PROFILE_BUNDLE")
        payload = {"data": {
            "type": "profiles",
            "attributes": {"name": ("reSchool TestFlight " if target == "ios-testflight"
                                    else "reSchool " + target + " ") + bundle,
                           "profileType": config["profile_type"]},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {"data": [{"type": "certificates", "id": certificate_id}]},
            },
        }}
        return self._request(ORIGIN + "/v1/profiles", payload=payload)

    def _request(self, url, *, payload=None):
        if payload is not None and (not self.allow_create or url != ORIGIN + "/v1/profiles"):
            raise SafeError("APPLE_MUTATION_BLOCKED")
        parsed = urllib.parse.urlsplit(url)
        if (parsed.scheme != "https" or parsed.netloc != "api.appstoreconnect.apple.com"
                or not parsed.path.startswith("/v1/") or parsed.fragment
                or "\\" in url or any(ord(char) <= 32 for char in url)):
            raise SafeError("UNSAFE_APPLE_URL")
        request = urllib.request.Request(url, method="GET" if payload is None else "POST",
                                        data=None if payload is None else json.dumps(payload).encode(), headers={
            "Authorization": "Bearer " + make_jwt(*self.credentials),
            "Accept": "application/json",
            "Content-Type": "application/json",
        })
        try:
            with self.opener.open(request, timeout=30) as response:
                if response.status != (200 if payload is None else 201):
                    raise SafeError("UNEXPECTED_HTTP_STATUS")
                return json.load(response)
        except urllib.error.HTTPError as error:
            code = error.code
            error.close()  # тело и заголовки ошибки от apple не читаем и не печатаем
            raise SafeError(f"HTTP_{code}") from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise SafeError("NETWORK_FAILURE") from None

    def listing(self, path, **query):
        url = ORIGIN + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        resources, included, seen = [], {}, set()
        while url:
            if url in seen or len(seen) >= 100:
                raise SafeError("INVALID_PAGINATION")
            seen.add(url)
            page = self.get(url)
            if not isinstance(page.get("data"), list):
                raise SafeError("INVALID_APPLE_RESPONSE")
            resources.extend(page["data"])
            for item in page.get("included", []):
                included[(item["type"], item["id"])] = item
            next_url = page.get("links", {}).get("next")
            url = urllib.parse.urljoin(url, next_url) if next_url else None
        return resources, included


def fingerprint(certificate):
    der = command("openssl", "x509", "-inform", "DER", "-outform", "DER", data=certificate)
    return hashlib.sha256(der).digest()


def unexpired(value):
    try:
        expiry = datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))
        return expiry > datetime.datetime.now(datetime.timezone.utc)
    except (ValueError, TypeError, AttributeError):
        return False


def matching_bundle(profile, included, certificate_ids, *, require_valid=True, target="ios-testflight"):
    config = TARGETS[target]
    attrs = profile.get("attributes", {})
    if (attrs.get("profileType") != config["profile_type"] or (require_valid and (
            attrs.get("profileState") != "ACTIVE" or not unexpired(attrs.get("expirationDate"))))):
        return None
    relations = profile.get("relationships", {})
    bundle_ref = relations.get("bundleId", {}).get("data") or {}
    bundle_attrs = included.get(("bundleIds", bundle_ref.get("id")), {}).get("attributes", {})
    bundle = bundle_attrs.get("identifier")
    if bundle_attrs.get("platform") not in (config["platform"], "UNIVERSAL"):
        return None
    certificates = relations.get("certificates", {}).get("data") or []
    if bundle in config["bundles"] and any(item.get("id") in certificate_ids for item in certificates):
        return bundle
    return None


def validated_content(profile, bundle, expected_fingerprint, *, target="ios-testflight"):
    if bundle not in TARGETS[target]["bundles"]:
        raise SafeError("UNEXPECTED_PROFILE_BUNDLE")
    content = base64.b64decode(profile["attributes"]["profileContent"], validate=True)
    # подпись cms проверяем, но выдавать это за проверку цепочки доверия apple нельзя
    decoded = command("openssl", "cms", "-verify", "-inform", "DER", "-noverify", data=content)
    values = plistlib.loads(decoded)
    try:
        platform = target.split("-")[0]
        if ((platform == "macos" and values.get("Platform") != ["OSX"])
                or (platform == "ios" and "OSX" in values.get("Platform", []))):
            raise ValueError("Profile platform mismatch")
        profile_values(values, bundle, platform, TEAM, target == "macos-direct")
    except ValueError:
        raise SafeError("PROFILE_ENTITLEMENTS_OR_METADATA_INVALID") from None
    if not any(fingerprint(cert) == expected_fingerprint
               for cert in values.get("DeveloperCertificates", [])):
        raise SafeError("PROFILE_SIGNING_CERTIFICATE_MISMATCH")
    return base64.b64encode(content)


def inspect(client, expected_fingerprint, *, create_missing=False, target="ios-testflight"):
    config = TARGETS[target]
    target_bundles = config["bundles"]
    report = {"mode": "create-missing" if create_missing else "read-only",
              "target": target, "environment": "apple-" + target,
              "access": {}, "certificate_exists": None,
              "bundles": {bundle: {"exists": None, "capabilities": None,
                                    "matching_profiles": None} for bundle in target_bundles}}

    def listing(scope, path, **query):
        try:
            result = client.listing(path, **query)
        except SafeError as error:
            report["access"][scope] = str(error)
            if str(error) == "HTTP_401" or create_missing:
                raise
            return None
        report["access"][scope] = "allowed"
        return result

    certificates = listing("certificates.read", "/v1/certificates")
    certificate_ids = set()
    if certificates is not None:
        for cert in certificates[0]:
            content = cert.get("attributes", {}).get("certificateContent")
            if content and fingerprint(base64.b64decode(content, validate=True)) == expected_fingerprint:
                certificate_ids.add(cert["id"])
        report["certificate_exists"] = bool(certificate_ids)

    # платформы бандла в api и Platform в plist это разные вещи, UNIVERSAL не отсеиваем
    bundles = listing("bundleIds.read", "/v1/bundleIds", **{
        "filter[identifier]": ",".join(target_bundles)})
    bundle_ids = {}
    if bundles is not None:
        for metadata in report["bundles"].values():
            metadata["exists"] = False
        for bundle in bundles[0]:
            identifier = bundle.get("attributes", {}).get("identifier")
            if (identifier not in target_bundles
                    or bundle.get("attributes", {}).get("platform") not in (config["platform"], "UNIVERSAL")):
                continue
            if identifier in bundle_ids:
                raise SafeError("AMBIGUOUS_BUNDLE_ID")
            bundle_ids[identifier] = bundle["id"]
            report["bundles"][identifier]["exists"] = True
            resource_id = urllib.parse.quote(bundle["id"], safe="")
            capabilities = listing(identifier + ".capabilities.read",
                                   f"/v1/bundleIds/{resource_id}/bundleIdCapabilities")
            if capabilities is not None:
                # наружу отдаём только два известных типа возможностей, а не произвольный текст из api
                types = {item.get("attributes", {}).get("capabilityType") for item in capabilities[0]}
                report["bundles"][identifier]["capabilities"] = {
                    name: name in types for name in ("APP_GROUPS",)}

    profile_query = {
        "include": "bundleId,certificates", "filter[profileType]": config["profile_type"],
        "limit[certificates]": 50,
    }
    # негодные и просроченные профили должны оставаться на виду, иначе будем плодить новые
    if not create_missing:
        profile_query["filter[profileState]"] = "ACTIVE"
    profiles = listing("profiles.read", "/v1/profiles", **profile_query)
    selected = {}
    if profiles is not None:
        resources, included = profiles
        for (kind, resource_id), item in included.items():
            if kind == "certificates":
                content = item.get("attributes", {}).get("certificateContent")
                if content and fingerprint(base64.b64decode(content, validate=True)) == expected_fingerprint:
                    certificate_ids.add(resource_id)
        if certificate_ids:
            report["certificate_exists"] = True
        for metadata in report["bundles"].values():
            metadata["matching_profiles"] = 0
            metadata["valid_profiles"] = 0
            metadata["profile_validation_failures"] = 0
        for profile in resources:
            bundle = matching_bundle(profile, included, certificate_ids,
                                     require_valid=not create_missing, target=target)
            if bundle is None:
                continue
            metadata = report["bundles"][bundle]
            metadata["exists"] = True
            metadata["matching_profiles"] += 1
            try:
                if matching_bundle(profile, included, certificate_ids, target=target) is None:
                    raise SafeError("EXISTING_PROFILE_INVALID_OR_EXPIRED")
                content = validated_content(profile, bundle, expected_fingerprint, target=target)
            except (SafeError, ValueError, KeyError, plistlib.InvalidFileException):
                metadata["profile_validation_failures"] += 1
                continue
            metadata["valid_profiles"] += 1
            selected[bundle] = content
    if create_missing:
        if len(certificate_ids) != 1 or set(bundle_ids) != set(target_bundles):
            raise SafeError("EXACT_CERTIFICATE_AND_BOTH_BUNDLE_IDS_REQUIRED")
        # обе предварительные проверки доводим до конца, и только потом создаём хоть что нибудь
        for bundle, metadata in report["bundles"].items():
            if metadata["profile_validation_failures"]:
                raise SafeError("EXISTING_MATCHING_INVALID_PROFILE_REQUIRES_REVIEW")
            capabilities = metadata["capabilities"] or {}
            if not capabilities.get("APP_GROUPS"):
                raise SafeError("REQUIRED_CAPABILITIES_MISSING")
        certificate_id = next(iter(certificate_ids))
        for bundle in target_bundles:
            metadata = report["bundles"][bundle]
            metadata["created"] = False
            if bundle in selected:
                continue
            # post не повторяем: даже оборванный ответ мог успеть создать профиль
            print(json.dumps({"bundle": bundle, "creation": "requesting"}), flush=True)
            response = client.create_profile(bundle, bundle_ids[bundle], certificate_id, target=target)
            print(json.dumps({"bundle": bundle, "created": True, "validated": False}), flush=True)
            try:
                profile = response["data"]
                attrs = profile["attributes"]
                if (profile.get("type") != "profiles" or attrs.get("profileType") != config["profile_type"]
                        or attrs.get("profileState") != "ACTIVE" or not unexpired(attrs.get("expirationDate"))):
                    raise SafeError("CREATED_PROFILE_METADATA_INVALID")
                content = validated_content(profile, bundle, expected_fingerprint, target=target)
            except Exception:
                raise SafeError("CREATED_PROFILE_VALIDATION_FAILED_RESOURCE_RETAINED") from None
            selected[bundle] = content
            metadata.update(created=True, matching_profiles=1, valid_profiles=1)
            print(json.dumps({"bundle": bundle, "created": True, "validated": True}), flush=True)
    report["ready_to_upload"] = all(bundle in selected for bundle in target_bundles)
    return report, selected


def repositories(repo, also_repo=None):
    destinations = [repo] + ([also_repo] if also_repo is not None else [])
    if any(not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_][A-Za-z0-9_.-]*", value)
           for value in destinations):
        raise SafeError("INVALID_REPOSITORY_OWNER_NAME")
    if len({value.lower() for value in destinations}) != len(destinations):
        raise SafeError("DUPLICATE_REPOSITORY_DESTINATION")
    return destinations


def upload(selected, *, target="ios-testflight", repo=REPO, also_repo=None):
    destinations = repositories(repo, also_repo)
    target_bundles = TARGETS[target]["bundles"]
    destination = "apple-" + target
    if set(selected) != set(target_bundles):
        raise SafeError("BOTH_VALID_PROFILES_REQUIRED")
    values = dict(zip(("APPLE_APP_PROFILE_BASE64", "APPLE_WIDGET_PROFILE_BASE64"),
                      (selected[bundle] for bundle in target_bundles)))
    if any(len(content) > 48 * 1024 for content in values.values()):
        raise SafeError("GITHUB_SECRET_TOO_LARGE")
    # все проверки назначения проходим до первой записи секрета
    for repository in destinations:
        endpoint = f"repos/{repository}/environments/{destination}"
        environment = json.loads(command("gh", "api", endpoint))
        policies = json.loads(command("gh", "api", endpoint + "/deployment-branch-policies"))
        branches = policies.get("branch_policies", [])
        if (environment.get("deployment_branch_policy") != {
                "protected_branches": False, "custom_branch_policies": True}
                or policies.get("total_count") != 1 or len(branches) != 1
                or branches[0].get("name") != "main" or branches[0].get("type") != "branch"):
            raise SafeError("ENVIRONMENT_MUST_ALLOW_EXACTLY_MAIN")
    for repository in destinations:
        for name, content in values.items():
            command("gh", "secret", "set", name, "--repo", repository, "--env", destination,
                    data=content)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=TARGETS, default="ios-testflight")
    parser.add_argument("--repo", default=REPO)
    parser.add_argument("--also-repo", help="Also upload the same secrets to this owner/name repository")
    parser.add_argument("--key-path", type=Path, required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer", required=True)
    parser.add_argument("--certificate", type=Path, required=True)
    parser.add_argument("--create-missing", action="store_true",
                        help="Create only missing target profiles for the existing app and widget")
    parser.add_argument("--upload", action="store_true",
                        help="Explicitly upload both validated profiles to the fixed GitHub Environment")
    args = parser.parse_args(argv)
    try:
        repositories(args.repo, args.also_repo)
        if (not re.fullmatch(r"[A-Z0-9]{10}", args.key_id)
                or not re.fullmatch(r"[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}", args.issuer)):
            raise SafeError("INVALID_KEY_OR_ISSUER_ID")
        if (args.key_path.is_symlink() or not args.key_path.is_file()
                or args.key_path.stat().st_mode & 0o077):
            raise SafeError("PRIVATE_KEY_REQUIRES_REGULAR_OWNER_ONLY_FILE")
        cert = command("openssl", "x509", "-inform", "DER", "-in", str(args.certificate), "-outform", "DER")
        subject = command("openssl", "x509", "-inform", "DER", "-noout", "-subject",
                          "-nameopt", "RFC2253", data=cert).decode().strip().removeprefix("subject=").strip()
        if (not any(re.search(r"(?:^|(?<!\\),)CN=" + re.escape(name), subject)
                    for name in TARGETS[args.target]["certificate_names"])
                or not re.search(r"(?:^|(?<!\\),)OU=" + TEAM + r"(?:,|$)", subject)):
            raise SafeError("LOCAL_CERTIFICATE_TEAM_OR_TYPE_MISMATCH")
        command("openssl", "x509", "-inform", "DER", "-noout", "-checkend", "0", data=cert)
        client = AppleClient(args.key_path, args.key_id, args.issuer, allow_create=args.create_missing)
        report, selected = inspect(client, fingerprint(cert), create_missing=args.create_missing, target=args.target)
        print(json.dumps(report, indent=2, sort_keys=True))
        if args.upload:
            upload(selected, target=args.target, repo=args.repo, also_repo=args.also_repo)
            print("Both profile secrets uploaded. No release started.")
        return 0
    except SafeError as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
    except Exception:
        # исключения могут тащить заголовки запроса, ключи и тела, наружу их не пускаем
        print('{"error": "LOCAL_OR_RESPONSE_FAILURE"}', file=sys.stderr)
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print('{"error": "CANCELLED"}', file=sys.stderr)
        sys.exit(130)
