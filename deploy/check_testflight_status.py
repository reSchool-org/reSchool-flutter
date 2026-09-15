#!/usr/bin/env python3
"""Attach app.txt to the latest GitHub release once its iOS version is testing externally."""

import argparse
import datetime
import json
import os
from pathlib import Path
import re
import sys
import tempfile

from apple_release import BUNDLE, decode, secret
from publish_apple_release import command
from setup_apple_profiles import AppleClient, SafeError

DEFAULT_PUBLIC_URL = "https://testflight.apple.com/join/JqADzPK9"


def related(resource, name, included):
    reference = resource.get("relationships", {}).get(name, {}).get("data")
    if not isinstance(reference, dict):
        return {}
    return included.get((reference.get("type"), reference.get("id")), {})


def externally_testing(build, included, version, now):
    prerelease = related(build, "preReleaseVersion", included).get("attributes", {})
    details = related(build, "buildBetaDetail", included).get("attributes", {})
    attrs = build.get("attributes", {})
    if (prerelease.get("platform") != "IOS" or prerelease.get("version") != version
            or attrs.get("processingState") != "VALID" or attrs.get("expired") is not False
            or attrs.get("buildAudienceType") == "INTERNAL_ONLY"
            or details.get("externalBuildState") != "IN_BETA_TESTING"):
        return False
    try:
        expiry = datetime.datetime.fromisoformat(attrs["expirationDate"].replace("Z", "+00:00"))
        return expiry > now
    except (KeyError, TypeError, ValueError):
        return False


def find_external_build(client, version, public_url):
    def listing(stage, path, **query):
        try:
            return client.listing(path, **query)
        except SafeError as error:
            raise SafeError(f"{stage}: {error}") from None

    apps, _ = listing("APPS", "/v1/apps", **{"filter[bundleId]": BUNDLE})
    if len(apps) != 1 or apps[0].get("attributes", {}).get("bundleId") != BUNDLE:
        raise ValueError("Expected exactly one App Store Connect app matching the iOS bundle ID")
    app_id = apps[0]["id"]
    builds, included = listing("BUILDS", "/v1/builds", **{
        "filter[app]": app_id,
        "filter[preReleaseVersion.version]": version,
        "filter[preReleaseVersion.platform]": "IOS",
        "filter[expired]": "false",
        "filter[processingState]": "VALID",
        "include": "preReleaseVersion,buildBetaDetail",
        "limit": 200,
    })
    now = datetime.datetime.now(datetime.timezone.utc)
    candidates = {build["id"]: build for build in builds
                  if externally_testing(build, included, version, now)}
    if not candidates:
        return None
    # ссылку проверяем локально, состав группы читаем полностью с пагинацией
    groups, _ = listing("BETA_GROUPS", "/v1/betaGroups", **{
        "filter[app]": app_id, "limit": 200,
    })
    for group in groups:
        attrs = group.get("attributes", {})
        if (attrs.get("isInternalGroup") is not False
                or attrs.get("publicLinkEnabled") is not True
                or attrs.get("publicLink") != public_url):
            continue
        members, _ = listing("BETA_GROUP_BUILDS", f"/v1/betaGroups/{group['id']}/builds",
                             limit=200)
        for member in members:
            if member.get("id") in candidates:
                return candidates[member["id"]]
    return None


def publish_if_ready(repo, public_url, client_factory):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo):
        raise ValueError("Invalid GitHub repository")
    if not re.fullmatch(r"https://testflight\.apple\.com/join/[A-Za-z0-9]+", public_url):
        raise ValueError("TESTFLIGHT_PUBLIC_URL must be a TestFlight public invitation URL")
    # This is the same release selected by UpdateService in the Flutter app.
    raw = command("gh", "api", f"repos/{repo}/releases/latest", missing_ok=True)
    if raw is None:
        print("No published release yet; nothing to check.")
        return False
    release = json.loads(raw)
    tag = release.get("tag_name", "")
    if release.get("draft") or release.get("prerelease"):
        raise ValueError("Expected a published stable GitHub release")
    if not re.fullmatch(r"v\d{1,3}\.\d{1,3}\.\d{1,3}", tag):
        raise ValueError("Latest release tag must be vMAJOR.MINOR.PATCH")
    if any(asset.get("name") == "app.txt" for asset in release.get("assets", [])):
        print(f"{tag}: app.txt already exists; nothing to publish.")
        return False
    build = find_external_build(client_factory(), tag[1:], public_url)
    if build is None:
        print(f"{tag}: no active iOS build is testing in the external group with the configured public link; retry on the next run.")
        return False
    # Bind publication to the release that was checked, even if /latest changes.
    current = json.loads(command("gh", "api", f"repos/{repo}/releases/tags/{tag}"))
    if (current.get("id") != release.get("id") or current.get("draft")
            or current.get("prerelease")):
        raise ValueError("GitHub release changed during the Apple check")
    if any(asset.get("name") == "app.txt" for asset in current.get("assets", [])):
        print(f"{tag}: another run already published app.txt.")
        return False
    with tempfile.TemporaryDirectory(prefix="testflight-link-") as temporary:
        path = Path(temporary) / "app.txt"
        path.write_text(public_url + "\n", encoding="utf-8")
        # No --clobber: existing release assets must never be replaced.
        command("gh", "release", "upload", tag, str(path), "--repo", repo)
    print(f"{tag}: external testing is active; published app.txt.")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="testflight-status-") as temporary:
        def client_factory():
            key = decode("ASC_PRIVATE_KEY_BASE64", Path(temporary) / "AuthKey.p8")
            return AppleClient(key, secret("ASC_KEY_ID"), secret("ASC_ISSUER_ID"))

        publish_if_ready(args.repo, os.environ.get("TESTFLIGHT_PUBLIC_URL") or DEFAULT_PUBLIC_URL,
                         client_factory)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, RuntimeError, SafeError) as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
