import base64
import contextlib
import datetime
import io
import json
from pathlib import Path
import plistlib
import sys
import unittest
from unittest.mock import Mock, patch
import urllib.error

sys.path.insert(0, str(Path(__file__).parents[1]))
import setup_apple_profiles as setup


class SetupProfilesTests(unittest.TestCase):
    def test_der_conversion_padding_and_sign_byte(self):
        signature = b"\x30\x26\x02\x01\x01\x02\x21\x00" + b"\x80" * 32
        self.assertEqual(setup.der_to_raw(signature), b"\x00" * 31 + b"\x01" + b"\x80" * 32)

    def test_der_rejects_malformed_signatures(self):
        for signature in (b"", b"\x30\x06\x02\x01\x00\x02\x01\x01",
                          b"\x30\x06\x02\x01\x80\x02\x01\x01",
                          b"\x30\x07\x02\x02\x00\x01\x02\x01\x01",
                          b"\x30\x06\x02\x01\x01\x02\x01\x01trailing",
                          b"\x30\x06\x02\x02\x01\x02\x02\x01"):
            with self.subTest(signature=signature), self.assertRaises(setup.SafeError):
                setup.der_to_raw(signature)

    def test_jwt_short_lived_and_signing_input_only_on_stdin(self):
        with patch.object(setup.time, "time", return_value=1000), \
                patch.object(setup, "command", return_value=b"\x30\x06\x02\x01\x01\x02\x01\x02") as command:
            token = setup.make_jwt(Path("/private.p8"), "KEY", "ISSUER")
        header, payload, signature = token.split(".")
        self.assertEqual(json.loads(base64.urlsafe_b64decode(header + "=="))["alg"], "ES256")
        claims = json.loads(base64.urlsafe_b64decode(payload + "=="))
        self.assertEqual(claims, {"iss": "ISSUER", "iat": 990, "exp": 1240, "aud": "appstoreconnect-v1"})
        self.assertEqual(len(base64.urlsafe_b64decode(signature + "==")), 64)
        self.assertEqual(command.call_args.kwargs["data"], (header + "." + payload).encode())
        self.assertNotIn(token, command.call_args.args)

    def test_matching_requires_bundle_certificate_type_state_and_expiry(self):
        included = {("bundleIds", "bundle"): {"attributes": {"identifier": setup.BUNDLE, "platform": "IOS"}}}
        profile = {"attributes": {"profileType": "IOS_APP_STORE", "profileState": "ACTIVE",
                                   "expirationDate": "2099-01-01T00:00:00Z"},
                   "relationships": {"bundleId": {"data": {"id": "bundle"}},
                                     "certificates": {"data": [{"id": "correct"}]}}}
        self.assertEqual(setup.matching_bundle(profile, included, {"correct"}), setup.BUNDLE)
        self.assertIsNone(setup.matching_bundle(profile, included, {"wrong"}))
        self.assertIsNone(setup.matching_bundle(profile, {}, {"correct"}))
        for key, value in (("profileType", "IOS_APP_DEVELOPMENT"), ("profileState", "INVALID"),
                           ("expirationDate", "2000-01-01T00:00:00Z"), ("expirationDate", "invalid")):
            with patch.dict(profile["attributes"], {key: value}):
                self.assertIsNone(setup.matching_bundle(profile, included, {"correct"}))

    def test_external_pagination_never_gets_token(self):
        client = setup.AppleClient(None, None, None)
        response = Mock(status=200)
        response.read.return_value = json.dumps({"data": [], "links": {"next": "https://other.example/v1/profiles"}}).encode()
        client.opener = Mock()
        client.opener.open.return_value.__enter__ = Mock(return_value=response)
        client.opener.open.return_value.__exit__ = Mock(return_value=False)
        with patch.object(setup, "make_jwt", return_value="secret") as jwt:
            with self.assertRaisesRegex(setup.SafeError, "UNSAFE_APPLE_URL"):
                client.listing("/v1/profiles")
            self.assertEqual(jwt.call_count, 1)
            self.assertEqual(client.opener.open.call_count, 1)

    def test_same_host_pagination(self):
        client = setup.AppleClient(None, None, None)
        with patch.object(client, "get", side_effect=[
            {"data": [{"id": "1"}], "links": {"next": "?cursor=next"}},
            {"data": [{"id": "2"}], "included": [{"type": "bundleIds", "id": "b"}]},
        ]) as get:
            resources, included = client.listing("/v1/profiles")
        self.assertEqual(len(resources), 2)
        self.assertIn(("bundleIds", "b"), included)
        self.assertEqual(get.call_args.args[0], setup.ORIGIN + "/v1/profiles?cursor=next")

    def test_capabilities_query_has_no_unsupported_limit(self):
        client = setup.AppleClient(None, None, None)
        with patch.object(client, "get", return_value={"data": []}) as get:
            client.listing("/v1/bundleIds/example/bundleIdCapabilities")
        get.assert_called_once_with(setup.ORIGIN + "/v1/bundleIds/example/bundleIdCapabilities")

    def test_profile_content_checks_entitlements_and_embedded_certificate(self):
        values = {
            "ApplicationIdentifierPrefix": [setup.TEAM], "TeamIdentifier": [setup.TEAM],
            "ExpirationDate": datetime.datetime(2099, 1, 1), "Platform": ["iOS"],
            "UUID": "00000000-0000-0000-0000-000000000000",
            "DeveloperCertificates": [b"certificate"],
            "Entitlements": {"application-identifier": setup.TEAM + "." + setup.BUNDLE,
                             "com.apple.security.application-groups": ["group." + setup.BUNDLE],
                             "aps-environment": "production"},
        }
        profile = {"attributes": {"profileContent": base64.b64encode(b"cms fixture").decode()}}
        with patch.object(setup, "command", return_value=plistlib.dumps(values)) as command, \
                patch.object(setup, "fingerprint", return_value=b"digest"):
            self.assertEqual(setup.validated_content(profile, setup.BUNDLE, b"digest"),
                             base64.b64encode(b"cms fixture"))
            self.assertEqual(command.call_args.kwargs["data"], b"cms fixture")
            with self.assertRaisesRegex(setup.SafeError, "PROFILE_SIGNING_CERTIFICATE_MISMATCH"):
                setup.validated_content(profile, setup.BUNDLE, b"other")
            del values["Entitlements"]["com.apple.security.application-groups"]
            command.return_value = plistlib.dumps(values)
            with self.assertRaisesRegex(setup.SafeError, "PROFILE_ENTITLEMENTS_OR_METADATA_INVALID"):
                setup.validated_content(profile, setup.BUNDLE, b"digest")

    def test_redirects_blocked(self):
        with self.assertRaisesRegex(setup.SafeError, "HTTP_REDIRECT_BLOCKED"):
            setup.NoRedirect().redirect_request(None, None, 302, "secret", {}, setup.ORIGIN + "/v1/profiles")

    def test_http_error_body_never_read_or_exposed(self):
        client = setup.AppleClient(None, None, None)
        body = Mock()
        client.opener = Mock()
        client.opener.open.side_effect = urllib.error.HTTPError(
            "https://secret.example", 403, "sensitive body", {"secret": "value"}, body)
        with patch.object(setup, "make_jwt", return_value="secret"):
            with self.assertRaisesRegex(setup.SafeError, "^HTTP_403$"):
                client.get(setup.ORIGIN + "/v1/profiles")
        body.read.assert_not_called()

    def test_subprocess_errors_hide_output_and_arguments(self):
        with patch.object(setup.subprocess, "run", return_value=Mock(returncode=1, stderr=b"SECRET")):
            with self.assertRaisesRegex(setup.SafeError, "^SUBPROCESS_FAILED$"):
                setup.command("openssl", "SECRET", data=b"SECRET")

    def test_no_upload_without_both_profiles(self):
        with patch.object(setup, "command") as command:
            with self.assertRaisesRegex(setup.SafeError, "BOTH_VALID_PROFILES_REQUIRED"):
                setup.upload({setup.BUNDLE: b"secret"})
            command.assert_not_called()

    def test_upload_checks_branch_and_passes_secrets_only_on_stdin(self):
        environment = {"deployment_branch_policy": {
            "protected_branches": False, "custom_branch_policies": True}}
        policies = {"total_count": 1, "branch_policies": [{"name": "main", "type": "branch"}]}
        selected = dict.fromkeys(setup.BUNDLES, b"SECRET")
        with patch.object(setup, "command", side_effect=[
            json.dumps(environment).encode(), json.dumps(policies).encode(), b"", b"",
        ]) as command:
            setup.upload(selected)
        calls = command.call_args_list[2:]
        self.assertEqual(len(calls), 2)
        for call in calls:
            self.assertEqual(call.args[:3], ("gh", "secret", "set"))
            self.assertNotIn("SECRET", call.args)
            self.assertEqual(call.kwargs["data"], b"SECRET")
        policies["branch_policies"][0]["name"] = "*"
        with patch.object(setup, "command", side_effect=[
            json.dumps(environment).encode(), json.dumps(policies).encode(),
        ]) as command:
            with self.assertRaisesRegex(setup.SafeError, "ENVIRONMENT_MUST_ALLOW_EXACTLY_MAIN"):
                setup.upload(selected)
            self.assertEqual(command.call_count, 2)

    def test_default_main_is_read_only_and_redacts_unexpected_errors(self):
        argv = ["--key-path", "/private.p8", "--key-id", "ABCDEFGHIJ", "--issuer",
                "00000000-0000-0000-0000-000000000000", "--certificate", "/public.cer"]
        with patch.object(Path, "is_symlink", return_value=False), \
                patch.object(Path, "is_file", return_value=True), \
                patch.object(Path, "stat", return_value=Mock(st_mode=0o600)), \
                patch.object(setup, "command", return_value=b"subject=CN=Apple Distribution: Test,OU=AQ52Q995ZR"), \
                patch.object(setup, "fingerprint", return_value=b"digest"), \
                patch.object(setup, "inspect", return_value=({"ready_to_upload": True}, dict.fromkeys(setup.BUNDLES, b"secret"))) as inspect, \
                patch.object(setup, "upload") as upload:
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(setup.main(argv), 0)
            upload.assert_not_called()
            self.assertFalse(inspect.call_args.kwargs["create_missing"])
            self.assertNotIn("secret", output.getvalue())
            inspect.side_effect = ValueError("SECRET")
            with contextlib.redirect_stderr(output):
                self.assertEqual(setup.main(argv), 1)
            self.assertNotIn("SECRET", output.getvalue())


class CreateProfilesTests(unittest.TestCase):
    target = "ios-testflight"

    def setUp(self):
        self.config = setup.TARGETS[self.target]
        self.target_bundles = self.config["bundles"]
        self.cert = {"id": "cert-id", "type": "certificates", "attributes": {
            "certificateType": "DISTRIBUTION",
            "certificateContent": base64.b64encode(b"certificate").decode()}}
        self.bundles = [{"id": f"bundle-{index}", "type": "bundleIds", "attributes": {
            "identifier": bundle, "platform": "IOS" if self.target == "ios-testflight" else "MAC_OS"}}
            for index, bundle in enumerate(self.target_bundles)]
        self.included = {(item["type"], item["id"]): item for item in [self.cert, *self.bundles]}
        self.profiles = []
        self.capabilities = [{"attributes": {"capabilityType": name}}
                             for name in ("APP_GROUPS",)]
        self.client = Mock()

        def listing(path, **query):
            if path == "/v1/certificates":
                return [self.cert], {}
            if path == "/v1/bundleIds":
                return self.bundles, {}
            if path.endswith("/bundleIdCapabilities"):
                return self.capabilities, {}
            if path == "/v1/profiles":
                return self.profiles, self.included
            self.fail("Unexpected API path")

        self.client.listing.side_effect = listing
        self.client.create_profile.side_effect = lambda bundle, *_, **kwargs: {
            "data": self.profile(self.target_bundles.index(bundle))}

    def profile(self, index):
        return {"type": "profiles", "attributes": {"profileType": self.config["profile_type"],
                "profileState": "ACTIVE", "expirationDate": "2099-01-01T00:00:00Z"},
                "relationships": {"bundleId": {"data": {"id": f"bundle-{index}"}},
                                  "certificates": {"data": [{"id": "cert-id"}]}}}

    def inspect(self, create_missing=True):
        with patch.object(setup, "fingerprint", return_value=b"digest"), contextlib.redirect_stdout(io.StringIO()):
            return setup.inspect(self.client, b"digest", create_missing=create_missing, target=self.target)

    def test_default_inspection_never_creates(self):
        self.inspect(create_missing=False)
        self.client.create_profile.assert_not_called()

    def test_create_only_missing_and_bind_discovered_ids(self):
        self.profiles = [self.profile(0)]
        with patch.object(setup, "validated_content", return_value=b"SECRET") as validate:
            report, selected = self.inspect()
        self.client.create_profile.assert_called_once_with(self.target_bundles[1], "bundle-1", "cert-id", target=self.target)
        self.assertEqual(validate.call_count, 2)
        self.assertEqual(set(selected), set(self.target_bundles))
        self.assertTrue(report["ready_to_upload"])
        self.assertFalse(report["bundles"][setup.BUNDLE]["created"])
        self.assertTrue(report["bundles"][self.target_bundles[1]]["created"])
        profiles_call = next(call for call in self.client.listing.call_args_list if call.args[0] == "/v1/profiles")
        self.assertNotIn("filter[profileState]", profiles_call.kwargs)

    def test_existing_invalid_expired_or_bad_content_blocks_all_creation(self):
        for change in ({"profileState": "INVALID"}, {"expirationDate": "2000-01-01T00:00:00Z"}, {}):
            self.profiles = [self.profile(1)]
            self.profiles[0]["attributes"].update(change)
            with self.subTest(change=change), patch.object(setup, "validated_content", side_effect=setup.SafeError("INVALID")):
                with self.assertRaisesRegex(setup.SafeError, "EXISTING_MATCHING_INVALID_PROFILE_REQUIRES_REVIEW"):
                    self.inspect()
            self.client.create_profile.assert_not_called()

    def test_missing_capabilities_block_all_creation(self):
        for name in ("PUSH_NOTIFICATIONS",):
            self.capabilities = [{"attributes": {"capabilityType": name}}]
            with self.subTest(name=name), self.assertRaisesRegex(setup.SafeError, "REQUIRED_CAPABILITIES_MISSING"):
                self.inspect()
            self.client.create_profile.assert_not_called()

    def test_post_forbidden_stops_without_retry_or_second_profile(self):
        self.client.create_profile.side_effect = setup.SafeError("HTTP_403")
        with self.assertRaisesRegex(setup.SafeError, "HTTP_403"):
            self.inspect()
        self.assertEqual(self.client.create_profile.call_count, 1)

    def test_read_forbidden_stops_before_any_creation(self):
        self.client.listing.side_effect = setup.SafeError("HTTP_403")
        with self.assertRaisesRegex(setup.SafeError, "HTTP_403"):
            self.inspect()
        self.assertEqual(self.client.listing.call_count, 1)
        self.client.create_profile.assert_not_called()

    def test_post_is_explicit_and_restricted_to_profiles(self):
        client = setup.AppleClient(None, None, None)
        with patch.object(setup, "make_jwt") as jwt:
            with self.assertRaisesRegex(setup.SafeError, "APPLE_MUTATION_BLOCKED"):
                client.create_profile(setup.BUNDLE, "bundle-0", "cert-id")
            client.allow_create = True
            for url in (setup.ORIGIN + "/v1/certificates", setup.ORIGIN + "/v1/profiles/existing",
                        setup.ORIGIN + "/v1/profiles?other=true", "https://other.example/v1/profiles"):
                with self.assertRaisesRegex(setup.SafeError, "APPLE_MUTATION_BLOCKED"):
                    client._request(url, payload={})
            jwt.assert_not_called()

    def test_create_payload_exact_bundle_certificate_and_store_type(self):
        client = setup.AppleClient(None, None, None, allow_create=True)
        response = Mock(status=201)
        response.read.return_value = b'{"data": {}}'
        client.opener = Mock()
        client.opener.open.return_value.__enter__ = Mock(return_value=response)
        client.opener.open.return_value.__exit__ = Mock(return_value=False)
        with patch.object(setup, "make_jwt", return_value="SECRET"):
            client.create_profile(setup.BUNDLE, "bundle-0", "cert-id")
        request = client.opener.open.call_args.args[0]
        self.assertEqual(request.full_url, setup.ORIGIN + "/v1/profiles")
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(json.loads(request.data), {"data": {
            "type": "profiles", "attributes": {"name": "reSchool TestFlight " + setup.BUNDLE,
                                                   "profileType": "IOS_APP_STORE"},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": "bundle-0"}},
                              "certificates": {"data": [{"type": "certificates", "id": "cert-id"}]}},
        }})

    def test_created_invalid_profile_never_uploads_or_creates_widget(self):
        argv = ["--key-path", "/private.p8", "--key-id", "ABCDEFGHIJ", "--issuer",
                "00000000-0000-0000-0000-000000000000", "--certificate", "/public.cer",
                "--create-missing", "--upload"]
        output = io.StringIO()
        with patch.object(Path, "is_symlink", return_value=False), \
                patch.object(Path, "is_file", return_value=True), \
                patch.object(Path, "stat", return_value=Mock(st_mode=0o600)), \
                patch.object(setup, "command", return_value=b"subject=CN=Apple Distribution: Test,OU=AQ52Q995ZR"), \
                patch.object(setup, "fingerprint", return_value=b"digest"), \
                patch.object(setup, "AppleClient", return_value=self.client), \
                patch.object(setup, "validated_content", side_effect=ValueError("SECRET")), \
                patch.object(setup, "upload") as upload, \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            self.assertEqual(setup.main(argv), 1)
        upload.assert_not_called()
        self.assertEqual(self.client.create_profile.call_count, 1)
        self.assertIn("CREATED_PROFILE_VALIDATION_FAILED_RESOURCE_RETAINED", output.getvalue())
        self.assertNotIn("SECRET", output.getvalue())


class RepositoryUploadTests(unittest.TestCase):
    primary = "reSchool-org/reSchool-flutter"

    def setUp(self):
        self.environment = json.dumps({"deployment_branch_policy": {
            "protected_branches": False, "custom_branch_policies": True}}).encode()
        self.policies = json.dumps({"total_count": 1, "branch_policies": [
            {"name": "main", "type": "branch"}]}).encode()

    def test_single_and_dual_repo_uploads_for_every_target(self):
        for target, config in setup.TARGETS.items():
            selected = dict(zip(config["bundles"], (b"APP_SECRET", b"WIDGET_SECRET")))
            for also_repo in (None, setup.REPO):
                repos = [self.primary] + ([also_repo] if also_repo is not None else [])
                with self.subTest(target=target, repos=repos), patch.object(setup, "command", side_effect=
                        [self.environment, self.policies] * len(repos) + [b""] * (2 * len(repos))) as command:
                    setup.upload(selected, target=target, repo=self.primary, also_repo=also_repo)
                    checks = command.call_args_list[:2 * len(repos)]
                    self.assertTrue(all(call.args[:2] == ("gh", "api") for call in checks))
                    self.assertEqual([call.args[-1] for call in checks[::2]], [
                        f"repos/{repo}/environments/apple-{target}" for repo in repos])
                    writes = command.call_args_list[2 * len(repos):]
                    self.assertEqual([call.args[5] for call in writes], [repo for repo in repos for _ in range(2)])
                    self.assertEqual([call.kwargs["data"] for call in writes], [b"APP_SECRET", b"WIDGET_SECRET"] * len(repos))
                    self.assertTrue(all(call.args[-1] == "apple-" + target for call in writes))

    def test_second_environment_failure_prevents_all_profile_writes(self):
        invalid = json.dumps({"total_count": 1, "branch_policies": [{"name": "*", "type": "branch"}]}).encode()
        for target, config in setup.TARGETS.items():
            for second_checks in ([self.environment, invalid], [b"{}", self.policies],
                                  [setup.SafeError("SUBPROCESS_FAILED")]):
                with self.subTest(target=target, second_checks=second_checks), \
                        patch.object(setup, "command", side_effect=[
                            self.environment, self.policies, *second_checks]) as command:
                    with self.assertRaises(setup.SafeError):
                        setup.upload(dict.fromkeys(config["bundles"], b"SECRET"), target=target,
                                     repo=setup.REPO, also_repo=self.primary)
                    self.assertTrue(all(call.args[:2] == ("gh", "api") for call in command.call_args_list))

    def test_invalid_and_duplicate_repositories_never_contact_github(self):
        invalid = ["", "owner", "owner/repo/extra", "../repo", "owner/..", "owner/repo?query=1",
                   "https://github.com/owner/repo", "owner/repo\n", "--repo/other", "owner/repo space"]
        for options in ([{flag: value} for flag in ("repo", "also_repo") for value in invalid]
                        + [{"also_repo": setup.REPO}, {"also_repo": setup.REPO.upper()}]):
            with self.subTest(options=options), patch.object(setup, "command") as command:
                with self.assertRaises(setup.SafeError):
                    setup.upload(dict.fromkeys(setup.BUNDLES, b"SECRET"), **options)
                command.assert_not_called()


    def fixture(self, target):
        fixture = CreateProfilesTests()
        fixture.target = target
        fixture.setUp()
        return fixture

    def test_target_mapping(self):
        for target, profile_type, platform, widget in (
            ("ios-testflight", "IOS_APP_STORE", "IOS", "ReSchoolWidgets"),
            ("macos-testflight", "MAC_APP_STORE", "MAC_OS", "ReSchoolMacWidgets"),
            ("macos-direct", "MAC_APP_DIRECT", "MAC_OS", "ReSchoolMacWidgets"),
        ):
            with self.subTest(target=target):
                config = setup.TARGETS[target]
                self.assertEqual(config["bundles"], ("com.magisky.reschoolbeta", "com.magisky.reschoolbeta." + widget))
                self.assertEqual(config["profile_type"], profile_type)
                self.assertEqual(config["platform"], platform)

    def test_matching_never_mixes_targets_or_native_platforms(self):
        for target in setup.TARGETS:
            fixture = self.fixture(target)
            for index, bundle in enumerate(fixture.target_bundles):
                profile = fixture.profile(index)
                with self.subTest(target=target, bundle=bundle):
                    for platform in ("UNIVERSAL", "MAC_OS" if target.startswith("macos") else "IOS"):
                        with self.subTest(platform=platform), patch.dict(
                                fixture.bundles[index]["attributes"], {"platform": platform}):
                            self.assertEqual(setup.matching_bundle(profile, fixture.included, {"cert-id"}, target=target), bundle)
                            for other in setup.TARGETS:
                                if other != target:
                                    self.assertIsNone(setup.matching_bundle(profile, fixture.included, {"cert-id"}, target=other))
                    for platform in ("OSX", None, "MAC_CATALYST", "IOS" if target.startswith("macos") else "MAC_OS"):
                        with patch.dict(fixture.bundles[index]["attributes"], {"platform": platform}):
                            self.assertIsNone(setup.matching_bundle(profile, fixture.included, {"cert-id"}, target=target))
                    with patch.dict(fixture.bundles[index]["attributes"], {"identifier": "wrong.widget"}):
                        self.assertIsNone(setup.matching_bundle(profile, fixture.included, {"cert-id"}, target=target))

    def test_bundle_lookup_checks_supported_platforms_locally_without_platform_filter(self):
        for target in setup.TARGETS:
            native = "IOS" if target == "ios-testflight" else "MAC_OS"
            for platform in ("IOS", "MAC_OS", "UNIVERSAL", "OSX", "MAC_CATALYST", None):
                fixture = self.fixture(target)
                for bundle in fixture.bundles:
                    bundle["attributes"]["platform"] = platform
                with self.subTest(target=target, platform=platform):
                    report, selected = fixture.inspect(create_missing=False)
                    expected = platform in (native, "UNIVERSAL")
                    self.assertTrue(all(metadata["exists"] == expected
                                        for metadata in report["bundles"].values()))
                    bundle_call = next(call for call in fixture.client.listing.call_args_list
                                       if call.args[0] == "/v1/bundleIds")
                    self.assertEqual(bundle_call.kwargs, {
                        "filter[identifier]": ",".join(fixture.target_bundles)})
                    capability_calls = [call for call in fixture.client.listing.call_args_list
                                        if call.args[0].endswith("/bundleIdCapabilities")]
                    self.assertEqual(len(capability_calls), 2 if expected else 0)
                    self.assertEqual(selected, {})
                    fixture.client.create_profile.assert_not_called()

    def test_universal_main_found_but_nonexact_widget_identifier_remains_missing(self):
        fixture = self.fixture("macos-direct")
        fixture.bundles[0]["attributes"]["platform"] = "UNIVERSAL"
        fixture.bundles[1]["attributes"]["identifier"] += ".other"
        report, selected = fixture.inspect(create_missing=False)
        self.assertTrue(report["bundles"][setup.BUNDLE]["exists"])
        self.assertFalse(report["bundles"][fixture.target_bundles[1]]["exists"])
        self.assertTrue(all(metadata["matching_profiles"] == 0
                            for metadata in report["bundles"].values()))
        self.assertFalse(report["ready_to_upload"])
        self.assertEqual(selected, {})
        fixture.client.create_profile.assert_not_called()

    def test_universal_bundle_cannot_bypass_signed_mac_profile_platform_validation(self):
        for target in ("macos-testflight", "macos-direct"):
            for platform in (["iOS"], ["OSX", "iOS"], ["MacCatalyst"], ["UNIVERSAL"], ["MAC_OS"]):
                fixture = self.fixture(target)
                fixture.bundles[0]["attributes"]["platform"] = "UNIVERSAL"
                fixture.profiles = [fixture.profile(0)]
                fixture.profiles[0]["attributes"]["profileContent"] = base64.b64encode(b"cms fixture").decode()
                with self.subTest(target=target, platform=platform), patch.object(
                        setup, "command", return_value=plistlib.dumps({"Platform": platform})) as command:
                    report, selected = fixture.inspect(create_missing=False)
                    metadata = report["bundles"][setup.BUNDLE]
                    self.assertEqual(metadata["matching_profiles"], 1)
                    self.assertEqual(metadata["profile_validation_failures"], 1)
                    self.assertEqual(metadata["valid_profiles"], 0)
                    self.assertFalse(report["ready_to_upload"])
                    self.assertEqual(selected, {})
                    command.assert_called_once_with(
                        "openssl", "cms", "-verify", "-inform", "DER", "-noverify", data=b"cms fixture")
                    fixture.client.create_profile.assert_not_called()

    def test_mac_profile_content_native_group_and_exact_certificate_without_push(self):
        for target in ("macos-testflight", "macos-direct"):
            for bundle in setup.TARGETS[target]["bundles"]:
                values = {
                    "ApplicationIdentifierPrefix": [setup.TEAM], "TeamIdentifier": [setup.TEAM],
                    "ExpirationDate": datetime.datetime(2099, 1, 1), "Platform": ["OSX"],
                    "UUID": "00000000-0000-0000-0000-000000000000",
                    "DeveloperCertificates": [b"certificate"],
                    "ProvisionsAllDevices": target == "macos-direct",
                    "Entitlements": {
                        "com.apple.application-identifier": setup.TEAM + "." + bundle,
                        "com.apple.security.application-groups": ["group." + setup.BUNDLE],
                    },
                }
                profile = {"attributes": {"profileContent": base64.b64encode(b"cms fixture").decode()}}
                with self.subTest(target=target, bundle=bundle), \
                        patch.object(setup, "command", return_value=plistlib.dumps(values)) as command, \
                        patch.object(setup, "fingerprint", return_value=b"digest"):
                    self.assertEqual(setup.validated_content(profile, bundle, b"digest", target=target),
                                     base64.b64encode(b"cms fixture"))
                    command.assert_called_once_with(
                        "openssl", "cms", "-verify", "-inform", "DER", "-noverify", data=b"cms fixture")
                    with self.assertRaisesRegex(setup.SafeError, "PROFILE_SIGNING_CERTIFICATE_MISMATCH"):
                        setup.validated_content(profile, bundle, b"different", target=target)
                    changes = [
                        {"Platform": ["iOS"]}, {"Platform": ["OSX", "iOS"]},
                        {"Platform": ["MAC_OS"]}, {"Platform": ["UNIVERSAL"]},
                        {"Platform": ["MacCatalyst"]}, {"Platform": ["OSX", "MacCatalyst"]},
                        {"TeamIdentifier": ["XXXXXXXXXX"]},
                        {"ExpirationDate": datetime.datetime(2000, 1, 1)},
                        {"ProvisionedDevices": ["device"]},
                        {"Entitlements": dict(values["Entitlements"], **{
                            "com.apple.security.application-groups": ["group.wrong"]})},
                        {"Entitlements": dict(values["Entitlements"], **{
                            "com.apple.security.get-task-allow": True})},
                        {"Entitlements": dict(values["Entitlements"], **{
                            "com.apple.application-identifier": setup.TEAM + "." + setup.BUNDLES[1]})},
                    ]
                    if target == "macos-testflight":
                        changes.append({"ProvisionsAllDevices": True})
                    for change in changes:
                        command.return_value = plistlib.dumps(dict(values, **change))
                        with self.subTest(change=change), self.assertRaisesRegex(
                                setup.SafeError, "PROFILE_ENTITLEMENTS_OR_METADATA_INVALID"):
                            setup.validated_content(profile, bundle, b"digest", target=target)

    def test_mac_inspect_reuses_distribution_certificate_and_does_not_require_push(self):
        for target in ("macos-testflight", "macos-direct"):
            fixture = self.fixture(target)
            fixture.capabilities = [{"attributes": {"capabilityType": "APP_GROUPS"}}]
            with self.subTest(target=target), patch.object(setup, "validated_content", return_value=b"SECRET") as validate:
                report, selected = fixture.inspect(create_missing=False)
                fixture.client.create_profile.assert_not_called()
                self.assertFalse(report["ready_to_upload"])
                report, selected = fixture.inspect()
                self.assertTrue(report["ready_to_upload"])
                self.assertEqual(report["environment"], "apple-" + target)
                self.assertEqual(set(selected), set(fixture.target_bundles))
                self.assertEqual(fixture.client.create_profile.call_count, 2)
                for call in fixture.client.create_profile.call_args_list:
                    self.assertEqual(call.kwargs, {"target": target})
                    self.assertEqual(call.args[2], "cert-id")
                for call in validate.call_args_list:
                    self.assertEqual(call.kwargs, {"target": target})
                for call in fixture.client.listing.call_args_list:
                    if call.args[0] == "/v1/bundleIds":
                        self.assertEqual(call.kwargs, {"filter[identifier]": ",".join(fixture.target_bundles)})
                    if call.args[0] == "/v1/profiles":
                        self.assertEqual(call.kwargs["filter[profileType]"], fixture.config["profile_type"])

    def test_mac_preflight_blocks_creation_with_wrong_platform_group_or_fingerprint(self):
        for target in ("macos-testflight", "macos-direct"):
            for failure in ("platform", "group", "fingerprint"):
                fixture = self.fixture(target)
                if failure == "platform":
                    fixture.bundles[0]["attributes"]["platform"] = "IOS"
                if failure == "group":
                    fixture.capabilities = [{"attributes": {"capabilityType": "PUSH_NOTIFICATIONS"}}]
                if failure == "fingerprint":
                    fixture.cert["attributes"]["certificateContent"] = base64.b64encode(b"other").decode()
                with self.subTest(target=target, failure=failure), \
                        patch.object(setup, "fingerprint", side_effect=lambda cert: b"digest" if cert == b"certificate" else b"other"):
                    with self.assertRaises(setup.SafeError):
                        setup.inspect(fixture.client, b"digest", create_missing=True, target=target)
                    fixture.client.create_profile.assert_not_called()

    def test_mac_existing_invalid_profile_blocks_creation(self):
        for target in ("macos-testflight", "macos-direct"):
            fixture = self.fixture(target)
            fixture.profiles = [fixture.profile(1)]
            with self.subTest(target=target), patch.object(setup, "validated_content", side_effect=setup.SafeError("BAD_GROUP")):
                with self.assertRaisesRegex(setup.SafeError, "EXISTING_MATCHING_INVALID_PROFILE_REQUIRES_REVIEW"):
                    fixture.inspect()
                fixture.client.create_profile.assert_not_called()

    def test_mac_payload_and_no_implicit_mutation_or_cross_platform_widget(self):
        for target in ("macos-testflight", "macos-direct"):
            client = setup.AppleClient(None, None, None)
            with self.subTest(target=target), patch.object(setup, "make_jwt") as jwt:
                with self.assertRaisesRegex(setup.SafeError, "APPLE_MUTATION_BLOCKED"):
                    client.create_profile(setup.BUNDLE, "bundle-id", "cert-id", target=target)
                jwt.assert_not_called()
            with patch.object(client, "_request") as request:
                for bundle in setup.TARGETS[target]["bundles"]:
                    client.create_profile(bundle, "bundle-id", "cert-id", target=target)
                    self.assertEqual(request.call_args.args, (setup.ORIGIN + "/v1/profiles",))
                    payload = request.call_args.kwargs["payload"]["data"]
                    self.assertEqual(payload["attributes"]["profileType"], setup.TARGETS[target]["profile_type"])
                    self.assertEqual(payload["relationships"], {
                        "bundleId": {"data": {"type": "bundleIds", "id": "bundle-id"}},
                        "certificates": {"data": [{"type": "certificates", "id": "cert-id"}]},
                    })
                request.reset_mock()
                with self.assertRaisesRegex(setup.SafeError, "UNEXPECTED_PROFILE_BUNDLE"):
                    client.create_profile(setup.BUNDLES[1], "bundle-id", "cert-id", target=target)
                request.assert_not_called()

    def test_upload_target_environment_and_no_ios_mac_mix(self):
        environment = {"deployment_branch_policy": {"protected_branches": False, "custom_branch_policies": True}}
        policies = {"total_count": 1, "branch_policies": [{"name": "main", "type": "branch"}]}
        for target in setup.TARGETS:
            selected = dict.fromkeys(setup.TARGETS[target]["bundles"], b"SECRET")
            with self.subTest(target=target), patch.object(setup, "command", side_effect=[
                json.dumps(environment).encode(), json.dumps(policies).encode(), b"", b"",
            ]) as command:
                setup.upload(selected, target=target)
                self.assertEqual(command.call_args_list[0].args[-1],
                                 f"repos/{setup.REPO}/environments/apple-{target}")
                for call in command.call_args_list[2:]:
                    self.assertEqual(call.args[-1], "apple-" + target)
                    self.assertEqual(call.kwargs["data"], b"SECRET")
                    self.assertNotIn("SECRET", repr(call.args))
            other = "ios-testflight" if target.startswith("macos") else "macos-testflight"
            with patch.object(setup, "command") as command:
                with self.assertRaisesRegex(setup.SafeError, "BOTH_VALID_PROFILES_REQUIRED"):
                    setup.upload(selected, target=other)
                command.assert_not_called()

    def test_main_certificate_types_target_forwarding_and_legacy_default(self):
        argv = ["--key-path", "/private.p8", "--key-id", "ABCDEFGHIJ", "--issuer",
                "00000000-0000-0000-0000-000000000000", "--certificate", "/public.cer"]
        cases = [
            (None, "Apple Distribution:", True),
            (None, "Developer ID Application:", False),
            (None, "3rd Party Mac Developer Application:", False),
            ("macos-testflight", "Apple Distribution:", True),
            ("macos-testflight", "3rd Party Mac Developer Application:", True),
            ("macos-testflight", "Developer ID Application:", False),
            ("macos-testflight", "Mac Installer Distribution:", False),
            ("macos-direct", "Developer ID Application:", True),
            ("macos-direct", "Apple Distribution:", False),
            ("macos-direct", "Developer ID Installer:", False),
        ]
        for target, name, valid in cases:
            for upload_requested in (False, True):
                actual_target = target or "ios-testflight"
                selected = dict.fromkeys(setup.TARGETS[actual_target]["bundles"], b"SECRET")
                output = io.StringIO()
                with self.subTest(target=target, name=name, upload=upload_requested), \
                        patch.object(Path, "is_symlink", return_value=False), \
                        patch.object(Path, "is_file", return_value=True), \
                        patch.object(Path, "stat", return_value=Mock(st_mode=0o600)), \
                        patch.object(setup, "command", return_value=f"subject=CN={name} Test,OU={setup.TEAM}".encode()), \
                        patch.object(setup, "fingerprint", return_value=b"digest"), \
                        patch.object(setup, "AppleClient") as client, \
                        patch.object(setup, "inspect", return_value=({"ready_to_upload": True}, selected)) as inspect, \
                        patch.object(setup, "upload") as upload, \
                        contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                    arguments = argv + (["--target", target] if target else []) + (["--upload"] if upload_requested else [])
                    self.assertEqual(setup.main(arguments), 0 if valid else 1)
                    if valid:
                        client.assert_called_once_with(Path("/private.p8"), "ABCDEFGHIJ",
                                                       "00000000-0000-0000-0000-000000000000", allow_create=False)
                        inspect.assert_called_once_with(client.return_value, b"digest", create_missing=False, target=actual_target)
                        if upload_requested:
                            upload.assert_called_once_with(selected, target=actual_target, repo=setup.REPO,
                                                           also_repo=None)
                        else:
                            upload.assert_not_called()
                    else:
                        client.assert_not_called()
                        inspect.assert_not_called()
                        upload.assert_not_called()
                    self.assertNotIn("SECRET", output.getvalue())

    def test_mac_private_key_permissions_and_team_checked_before_apple_access(self):
        argv = ["--key-path", "/private.p8", "--key-id", "ABCDEFGHIJ", "--issuer",
                "00000000-0000-0000-0000-000000000000", "--certificate", "/public.cer",
                "--create-missing", "--upload"]
        for target in ("macos-testflight", "macos-direct"):
            for symlink, regular, mode, team in ((True, True, 0o600, setup.TEAM),
                                               (False, False, 0o600, setup.TEAM),
                                               (False, True, 0o644, setup.TEAM),
                                               (False, True, 0o600, "XXXXXXXXXX")):
                name = setup.TARGETS[target]["certificate_names"][0]
                with self.subTest(target=target, mode=mode, team=team), \
                        patch.object(Path, "is_symlink", return_value=symlink), \
                        patch.object(Path, "is_file", return_value=regular), \
                        patch.object(Path, "stat", return_value=Mock(st_mode=mode)), \
                        patch.object(setup, "command", return_value=f"subject=CN={name} Test,OU={team}".encode()), \
                        patch.object(setup, "AppleClient") as client, \
                        patch.object(setup, "upload") as upload, contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(setup.main(argv + ["--target", target]), 1)
                    client.assert_not_called()
                    upload.assert_not_called()


if __name__ == "__main__":
    unittest.main()
