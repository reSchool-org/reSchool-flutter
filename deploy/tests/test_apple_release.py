import datetime
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import sys
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location("apple_release", Path(__file__).parents[1] / "apple_release.py")
apple = importlib.util.module_from_spec(spec)
spec.loader.exec_module(apple)


CERTIFICATE = b"fixture-distribution-certificate-DER"
IDENTITY = hashlib.sha1(CERTIFICATE).hexdigest().upper()
SUBMISSION = "12345678-1234-1234-1234-123456789012"


def make_app(app, platform="macos"):
    widget = app / ("PlugIns/ReSchoolWidgets.appex" if platform == "ios"
                    else "Contents/PlugIns/ReSchoolMacWidgets.appex")
    for bundle in (app, widget):
        contents = bundle if platform == "ios" else bundle / "Contents"
        contents.mkdir(parents=True)
        data = {"CFBundleIdentifier": apple.BUNDLE if bundle == app else apple.BUNDLE + (
                    ".ReSchoolWidgets" if platform == "ios" else ".ReSchoolMacWidgets"),
                "CFBundleShortVersionString": "2.0.1", "CFBundleVersion": "1.1.1",
                "CFBundleExecutable": "reschool"}
        if platform == "macos":
            data.update(CFBundleSupportedPlatforms=["MacOSX"], DTPlatformName="macosx",
                        DTSDKName="macosx15.2", LSApplicationCategoryType="public.app-category.education")
            (contents / "MacOS").mkdir()
            (contents / "MacOS/reschool").write_bytes(b"fixture-MachO")
            (contents / "Resources").mkdir()
        (contents / "Info.plist").write_bytes(plistlib.dumps(data))
        (contents / ("PrivacyInfo.xcprivacy" if platform == "ios"
                     else "Resources/PrivacyInfo.xcprivacy")).write_bytes(plistlib.dumps({}))
    return app, widget


def mac_tool_output(*args, **kwargs):
    if args[0] == "lipo":
        return b"x86_64 arm64\n"
    if args[:2] == ("xcrun", "vtool"):
        if args[3] == "x86_64":
            return b"Load command 8\n      cmd LC_VERSION_MIN_MACOSX\n  cmdsize 16\n  version 10.14\n      sdk 15.2\n"
        return b"Load command 9\n      cmd LC_BUILD_VERSION\n  cmdsize 32\n platform MACOS\n    minos 11.0\n      sdk 15.2\n"
    if args[:2] == ("codesign", "-d"):
        return plistlib.dumps({"com.apple.security.app-sandbox": True,
                              "com.apple.security.application-groups": [apple.GROUP],
                              "aps-environment": "production"})
    return b""


class ReleaseValidationTests(unittest.TestCase):
    def test_version_and_counter(self):
        self.assertEqual(apple.version_values("2.0.1", "101"), ("2.0.1", "1.1.1"))
        self.assertEqual(apple.version_values("2.0.1", "10001"), ("2.0.1", "2.0.1"))
        for version, build in [("1;exit", "1"), ("1.0", "1"), ("1.0.0", "0"),
                               ("1.0.0", "100000000"), ("1.0.0", "-1")]:
            with self.assertRaises(ValueError):
                apple.version_values(version, build)

    def profile(self):
        return {"UUID": "12345678-1234-1234-1234-123456789012",
                "DeveloperCertificates": [CERTIFICATE],
                "TeamIdentifier": ["ABCDEFGHIJ"], "ApplicationIdentifierPrefix": ["ABCDEFGHIJ"],
                "Platform": ["iOS"], "ExpirationDate": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + datetime.timedelta(days=1),
                "Entitlements": {"application-identifier": "ABCDEFGHIJ." + apple.BUNDLE,
                                 "com.apple.security.application-groups": [apple.GROUP],
                                 "aps-environment": "production"}}

    def validate(self, profile):
        return apple.profile_values(profile, apple.BUNDLE, "ios", "ABCDEFGHIJ", False, IDENTITY)

    def test_distribution_profile(self):
        profile = self.profile()
        self.assertEqual(self.validate(profile), profile["UUID"])

    def test_profile_certificate_match_for_app_and_widget_on_both_platforms(self):
        for platform in ("ios", "macos"):
            for widget in (False, True):
                bundle = apple.BUNDLE + ((".ReSchoolWidgets" if platform == "ios"
                                        else ".ReSchoolMacWidgets") if widget else "")
                for certs in ([b"other", CERTIFICATE], [], [b"other"], ["not DER bytes"]):
                    with self.subTest(platform=platform, widget=widget, certs=certs):
                        profile = self.profile()
                        profile["Platform"] = ["iOS" if platform == "ios" else "OSX"]
                        profile["Entitlements"]["application-identifier"] = "ABCDEFGHIJ." + bundle
                        profile["DeveloperCertificates"] = certs
                        if CERTIFICATE in certs:
                            self.assertEqual(apple.profile_values(profile, bundle, platform,
                                "ABCDEFGHIJ", False, IDENTITY.lower()), profile["UUID"])
                        else:
                            with self.assertRaisesRegex(ValueError, "selected signing certificate"):
                                apple.profile_values(profile, bundle, platform, "ABCDEFGHIJ", False, IDENTITY)

    def test_profile_setup_can_validate_metadata_without_imported_identity(self):
        profile = self.profile()
        self.assertEqual(apple.profile_values(profile, apple.BUNDLE, "ios", "ABCDEFGHIJ", False),
                         profile["UUID"])

    def test_rejects_wrong_team_platform_expiry_and_ad_hoc(self):
        for key, value in [("TeamIdentifier", ["XXXXXXXXXX"]), ("Platform", ["OSX"]),
                           ("ExpirationDate", datetime.datetime(2000, 1, 1)),
                           ("ProvisionedDevices", ["device"]), ("ProvisionsAllDevices", True),
                           ("UUID", "../../outside")]:
            profile = self.profile()
            profile[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate(profile)

    def test_rejects_wrong_entitlements(self):
        for key, value in [("get-task-allow", True),
                           ("com.apple.security.application-groups", []),
                           ("application-identifier", "ABCDEFGHIJ.*")]:
            profile = self.profile()
            profile["Entitlements"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate(profile)


    def test_macos_all_devices_profile_is_direct_only(self):
        profile = self.profile()
        profile["Platform"] = ["OSX"]
        profile["ProvisionsAllDevices"] = True
        entitlements = profile["Entitlements"]
        entitlements["com.apple.application-identifier"] = entitlements.pop("application-identifier")
        entitlements.pop("aps-environment")
        self.assertEqual(
            apple.profile_values(profile, apple.BUNDLE, "macos", "ABCDEFGHIJ", True),
            profile["UUID"],
        )
        with self.assertRaisesRegex(ValueError, "not ad-hoc/enterprise"):
            apple.profile_values(profile, apple.BUNDLE, "macos", "ABCDEFGHIJ", False)

    def test_macos_direct_and_store_reject_devices_and_debug_entitlements(self):
        for direct in (False, True):
            for invalid in ("ProvisionedDevices", "com.apple.security.get-task-allow"):
                with self.subTest(direct=direct, invalid=invalid):
                    profile = self.profile()
                    profile["Platform"] = ["OSX"]
                    if invalid == "ProvisionedDevices":
                        profile[invalid] = ["device"]
                    else:
                        profile["Entitlements"][invalid] = True
                    with self.assertRaises(ValueError):
                        apple.profile_values(profile, apple.BUNDLE, "macos", "ABCDEFGHIJ", direct)


class IOSReleaseEntitlementTests(unittest.TestCase):
    def test_release_without_push_is_valid_but_development_apns_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            app, _ = make_app(Path(temporary) / "Runner.app", platform="ios")
            for push in (None, "production", "development"):
                entitlements = {"com.apple.security.application-groups": [apple.GROUP]}
                if push is not None:
                    entitlements["aps-environment"] = push

                def output(*args, **kwargs):
                    return plistlib.dumps(entitlements) if args[:2] == ("codesign", "-d") else b""

                with self.subTest(push=push), mock.patch.object(apple, "run", side_effect=output):
                    if push == "development":
                        with self.assertRaisesRegex(ValueError, "APNs must use production"):
                            apple.verify_app(app, "ios", "2.0.1", "1.1.1", signed=True)
                    else:
                        apple.verify_app(app, "ios", "2.0.1", "1.1.1", signed=True)


class NativeMacTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.app, self.widget = make_app(self.root / "reschool.app")
        self.run = mock.patch.object(apple, "run", side_effect=mac_tool_output).start()
        self.addCleanup(mock.patch.stopall)

    def verify(self, signed=False):
        apple.verify_app(self.app, "macos", "2.0.1", "1.1.1", signed)

    def test_native_universal_app_and_widget_with_legacy_intel_load_command(self):
        for signed in (False, True):
            self.run.reset_mock()
            self.verify(signed)
            calls = [call.args for call in self.run.call_args_list]
            self.assertEqual(sum(args[0] == "lipo" for args in calls), 2)
            self.assertEqual(sum(args[:2] == ("xcrun", "vtool") for args in calls), 4)
            self.assertEqual(sum(args[0] == "codesign" for args in calls), 4 if signed else 0)

    def test_rejects_non_native_metadata_in_app_or_widget_even_unsigned(self):
        for bundle in (self.app, self.widget):
            info = bundle / "Contents/Info.plist"
            original = info.read_bytes()
            for key, value in [("CFBundleSupportedPlatforms", ["iPhoneOS"]),
                               ("CFBundleSupportedPlatforms", ["MacOSX", "iPhoneOS"]),
                               ("CFBundleSupportedPlatforms", None),
                               ("DTPlatformName", "iphoneos"), ("DTPlatformName", None),
                               ("DTSDKName", "iphoneos18.2"),
                               ("DTPlatformVariant", "maccatalyst"), ("UIDeviceFamily", [2]),
                               ("LSRequiresIPhoneOS", False), ("MinimumOSVersion", "15.0")]:
                with self.subTest(bundle=bundle.name, key=key, value=value):
                    data = plistlib.loads(original)
                    if value is None:
                        data.pop(key)
                    else:
                        data[key] = value
                    info.write_bytes(plistlib.dumps(data))
                    with self.assertRaisesRegex(ValueError, "native MacOSX"):
                        self.verify()
            info.write_bytes(original)

    def test_rejects_wrong_architectures_or_macho_platform_in_either_bundle(self):
        for bundle in (self.app, self.widget):
            binary = str(bundle / "Contents/MacOS/reschool")
            cases = [("lipo", b"arm64\n"), ("lipo", b"x86_64\n"),
                     ("vtool", b"cmd LC_BUILD_VERSION\n platform MACCATALYST\n"),
                     ("vtool", b"cmd LC_BUILD_VERSION\n platform IOS\n"),
                     ("vtool", b"cmd LC_BUILD_VERSION\n platform 6\n"),
                     ("vtool", b"cmd LC_VERSION_MIN_IPHONEOS\n version 12.0\n"),
                     ("vtool", b"cmd LC_BUILD_VERSION\n"), ("vtool", b"")]
            for arch in ("arm64", "x86_64"):
                for tool, output in cases:
                    with self.subTest(bundle=bundle.name, arch=arch, tool=tool, output=output):
                        def result(*args, **kwargs):
                            if args[-1] == binary and (args[0] == tool or
                                    (args[:2] == ("xcrun", tool) and args[3] == arch)):
                                return output
                            return mac_tool_output(*args, **kwargs)
                        self.run.side_effect = result
                        with self.assertRaises(ValueError):
                            self.verify()

    def test_numeric_macos_platform_is_accepted(self):
        def result(*args, **kwargs):
            if args[:2] == ("xcrun", "vtool"):
                return b"cmd LC_BUILD_VERSION\n platform 1\n"
            return mac_tool_output(*args, **kwargs)
        self.run.side_effect = result
        self.verify()

    def test_signed_widget_entitlements_and_signature_are_checked(self):
        for ent in ({}, {"com.apple.security.application-groups": [apple.GROUP]},
                    {"com.apple.security.application-groups": [apple.GROUP],
                     "com.apple.security.app-sandbox": True, "com.apple.security.get-task-allow": True}):
            def result(*args, **kwargs):
                if args[:2] == ("codesign", "-d") and args[-1] == str(self.widget):
                    return plistlib.dumps(ent)
                return mac_tool_output(*args, **kwargs)
            self.run.side_effect = result
            with self.assertRaises(ValueError):
                self.verify(signed=True)
        def bad_signature(*args, **kwargs):
            if args[:2] == ("codesign", "--verify") and args[-1] == str(self.widget):
                raise RuntimeError("codesign failed (exit 1)")
            return mac_tool_output(*args, **kwargs)
        self.run.side_effect = bad_signature
        with self.assertRaises(RuntimeError):
            self.verify(signed=True)

    def test_rejects_missing_executable_privacy_version_category_and_widget(self):
        for key, value in [("CFBundleExecutable", "../outside"), ("CFBundleExecutable", "missing"),
                           ("CFBundleVersion", "9"), ("CFBundleIdentifier", "other"),
                           ("LSApplicationCategoryType", "public.app-category.games")]:
            info = self.app / "Contents/Info.plist"
            original = info.read_bytes()
            data = plistlib.loads(original)
            data[key] = value
            info.write_bytes(plistlib.dumps(data))
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.verify()
            info.write_bytes(original)
        (self.widget / "Contents/Resources/PrivacyInfo.xcprivacy").unlink()
        with self.assertRaisesRegex(ValueError, "privacy manifest"):
            self.verify()
        shutil.rmtree(self.widget)
        with self.assertRaisesRegex(ValueError, "exactly one widget"):
            self.verify()


class PackageTests(unittest.TestCase):
    def test_expanded_payload_requires_one_app_and_ignores_scripts_metadata(self):
        for count in (0, 1, 2):
            with self.subTest(count=count), tempfile.TemporaryDirectory() as temporary, \
                 mock.patch.object(apple, "run") as run, mock.patch.object(apple, "verify_app") as verify:
                state = Path(temporary)
                artifact = state / "release.pkg"
                expanded = None
                def expand(*args, **kwargs):
                    nonlocal expanded
                    if args[:2] == ("pkgutil", "--expand-full"):
                        expanded = Path(args[-1])
                        self.assertEqual(expanded.parent.stat().st_mode & 0o777, 0o700)
                        self.assertFalse(expanded.exists())
                        # pkgutil умеет разворачивать метаданные Scripts рядом с Payload
                        make_app(expanded / "component.pkg/Scripts/reschool.app")
                        (expanded / "component.pkg/Scripts/Payload/fake.app/Contents").mkdir(parents=True)
                        (expanded / "component.pkg/Scripts/Payload/fake.app/Contents/Info.plist").touch()
                        for index in range(count):
                            make_app(expanded / f"component{index}.pkg/Payload/Applications/app{index}.app")
                    return b""
                run.side_effect = expand
                if count == 1:
                    apple.verify_pkg(artifact, "2.0.1", "1.1.1", state)
                    verify.assert_called_once_with(
                        expanded / "component0.pkg/Payload/Applications/app0.app",
                        "macos", "2.0.1", "1.1.1", signed=True)
                else:
                    with self.assertRaisesRegex(ValueError, "exactly one app"):
                        apple.verify_pkg(artifact, "2.0.1", "1.1.1", state)
                    verify.assert_not_called()
                self.assertFalse(expanded.parent.exists())
                self.assertEqual(run.call_args_list[0],
                                 mock.call("pkgutil", "--check-signature", str(artifact)))

    def test_exported_widget_validation_failure_propagates_and_cleans_up(self):
        with tempfile.TemporaryDirectory() as temporary, mock.patch.object(apple, "run") as run:
            def result(*args, **kwargs):
                if args[:2] == ("pkgutil", "--expand-full"):
                    app, widget = make_app(Path(args[-1]) / "component.pkg/Payload/reschool.app")
                    info = widget / "Contents/Info.plist"
                    data = plistlib.loads(info.read_bytes())
                    data["CFBundleVersion"] = "9"
                    info.write_bytes(plistlib.dumps(data))
                return mac_tool_output(*args, **kwargs)
            run.side_effect = result
            with self.assertRaisesRegex(ValueError, "versions must match"):
                apple.verify_pkg(Path(temporary) / "release.pkg", "2.0.1", "1.1.1", Path(temporary))
            self.assertEqual(list(Path(temporary).iterdir()), [])


class SigningTests(unittest.TestCase):
    def test_installer_selection_uses_basic_policy_and_correct_team_and_type(self):
        allowed = ("3rd Party Mac Developer Installer:", "Mac Installer Distribution:")
        for name in ("3rd Party Mac Developer Installer: magisky (ABCDEFGHIJ)",
                     "Mac Installer Distribution: magisky (ABCDEFGHIJ)",
                     "Mac Installer Distribution: other (XXXXXXXXXX)",
                     "Developer ID Installer: magisky (ABCDEFGHIJ)",
                     "Apple Distribution: magisky (ABCDEFGHIJ)"):
            with self.subTest(name=name), mock.patch.object(apple, "run") as run:
                run.return_value = f' 1) {IDENTITY} "{name}"\n'.encode()
                if name.startswith(allowed) and name.endswith("(ABCDEFGHIJ)"):
                    self.assertEqual(apple.signing_identity(Path("private.keychain-db"), "ABCDEFGHIJ",
                                                           allowed, policy="basic"), IDENTITY)
                else:
                    with self.assertRaises(ValueError):
                        apple.signing_identity(Path("private.keychain-db"), "ABCDEFGHIJ", allowed, policy="basic")
                run.assert_called_once_with("security", "find-identity", "-v", "-p", "basic",
                                            "private.keychain-db", capture=True)

    def test_missing_or_ambiguous_identity_is_rejected(self):
        for output in (b"0 valid identities found", (f'{IDENTITY} "Apple Distribution: A (ABCDEFGHIJ)"\n' * 2).encode()):
            with mock.patch.object(apple, "run", return_value=output), self.assertRaises(ValueError):
                apple.signing_identity(Path("keychain"), "ABCDEFGHIJ", ("Apple Distribution:",))

    def test_notarization_staples_and_assesses_both_app_and_dmg(self):
        for source, target, assessment in (("app.zip", "reschool.app", "execute"),
                                           ("release.dmg", "release.dmg", "open")):
            with mock.patch.object(apple, "run") as run:
                run.return_value = json.dumps({"status": "Accepted", "id": SUBMISSION}).encode()
                self.assertEqual(apple.notarize(Path(source), Path(target), Path("private.p8"),
                                               "ABCDEFGHIJ", SUBMISSION), SUBMISSION)
                self.assertEqual(run.call_args_list[0].kwargs, {"capture": True})
                self.assertEqual(run.call_args_list[1], mock.call("xcrun", "stapler", "staple", target))
                self.assertEqual(run.call_args_list[2], mock.call("xcrun", "stapler", "validate", target))
                self.assertEqual(run.call_args_list[3].args[:4], ("spctl", "--assess", "--type", assessment))

    def test_notary_rejection_prints_only_safe_submission_id(self):
        for submission in (SUBMISSION, "private-output\n::error::injected", None):
            with mock.patch.object(apple, "run") as run, mock.patch("sys.stdout", new_callable=io.StringIO) as output:
                run.return_value = json.dumps({"status": "Invalid", "id": submission,
                                              "message": "private-output"}).encode()
                with self.assertRaisesRegex(ValueError, "did not accept"):
                    apple.notarize(Path("app.zip"), Path("app.app"), Path("key.p8"), "ABCDEFGHIJ", SUBMISSION)
                self.assertEqual(run.call_count, 1)
                self.assertEqual(output.getvalue(), f"Notarization submission ID: {SUBMISSION}\n"
                                 if submission == SUBMISSION else "")

    def test_malformed_notary_responses_are_generic_errors(self):
        for response in (b"private-output", b"[]", b"null", b"\xff"):
            with mock.patch.object(apple, "run", return_value=response), \
                 self.assertRaisesRegex(ValueError, "^Invalid notarization response$"):
                apple.notarize(Path("app.zip"), Path("app.app"), Path("key.p8"), "ABCDEFGHIJ", SUBMISSION)


class ReleaseFlowTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.target = "macos-testflight"
        self.failure = None
        self.options = None
        self.environment = {"RUNNER_TEMP": str(self.root), "APPLE_TEAM_ID": "ABCDEFGHIJ",
                            "ASC_KEY_ID": "ABCDEFGHIJ", "ASC_ISSUER_ID": SUBMISSION,
                            "GITHUB_SHA": "fixture-commit", "GITHUB_ACTIONS": "true"}
        for prefix in ("APPLE_CERTIFICATE", "APPLE_INSTALLER"):
            self.environment[prefix + "_P12_BASE64"] = apple.base64.b64encode(b"fixture-p12").decode()
            self.environment[prefix + "_P12_PASSWORD"] = "fixture-password"
        self.environment["ASC_PRIVATE_KEY_BASE64"] = apple.base64.b64encode(b"fixture-p8").decode()
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(apple, "ROOT", self.root).start()
        mock.patch.object(apple.Path, "home", return_value=self.root / "home").start()
        self.prepare = mock.patch.object(apple, "prepare").start()
        self.run = mock.patch.object(apple, "run", side_effect=self.command).start()

    def command(self, *args, **kwargs):
        platform = self.target.split("-")[0]
        if args[:2] == ("security", "find-identity"):
            name = "Developer ID Application" if self.target == "macos-direct" else "Apple Distribution"
            sha = IDENTITY
            if "basic" in args:
                name, sha = "3rd Party Mac Developer Installer", "B" * 40
            return f'{sha} "{name}: magisky (ABCDEFGHIJ)"\n'.encode()
        if args[:2] == ("security", "cms"):
            return Path(args[-1]).read_bytes()
        if args[0] == "xcodebuild" and args[-1] == "archive":
            make_app(self.root / "build/apple/Runner.xcarchive/Products/Applications/reschool.app", platform)
        if args[:2] == ("xcodebuild", "-exportArchive"):
            self.options = plistlib.loads(Path(args[-1]).read_bytes())
            export = self.root / "build/apple/export"
            export.mkdir()
            if self.target == "macos-direct":
                make_app(export / "reschool.app")
            else:
                (export / ("release.ipa" if platform == "ios" else "release.pkg")).write_bytes(b"fixture-package")
        if args[:2] == ("pkgutil", "--expand-full"):
            make_app(Path(args[-1]) / "component.pkg/Payload/Applications/reschool.app")
        if args[:3] == ("ditto", "-x", "-k"):
            make_app(Path(args[-1]) / "Payload/reschool.app", "ios")
        elif args[0] == "ditto" and args[1] == "-c":
            Path(args[-1]).write_bytes(b"fixture-zip")
        elif args[0] == "ditto":
            shutil.copytree(args[1], args[2])
        if args[:3] == ("xcrun", "notarytool", "submit"):
            return json.dumps({"status": "Accepted", "id": SUBMISSION}).encode()
        if args[:2] == ("xcrun", "altool"):
            if self.failure == args[2]:
                return b"Validation failed (409) Invalid Signature\nVERIFY FAILED with 1 error\n"
            return b"VERIFY SUCCEEDED with no errors" if args[2] == "--validate-app" else b"UPLOAD SUCCEEDED with no errors"
        if args[:3] == ("xcrun", "stapler", "staple") and args[-1].endswith(".app"):
            (Path(args[-1]) / "fixture-ticket").touch()
        if args[:3] == ("xcrun", "stapler", "validate") and args[-1].endswith(".dmg") and self.failure:
            raise RuntimeError("stapler failed (exit 1)")
        if args[0] == "hdiutil":
            staging = Path(args[args.index("-srcfolder") + 1])
            self.assertTrue((staging / "reschool.app/fixture-ticket").is_file())
            self.assertTrue((staging / "Applications").is_symlink())
            Path(args[-1]).write_bytes(b"fixture-signed-dmg")
        return mac_tool_output(*args, **kwargs)

    def execute(self, upload=False, bad_certificate=False):
        platform = self.target.split("-")[0]
        for widget in (False, True):
            profile = ReleaseValidationTests().profile()
            profile["Platform"] = ["iOS" if platform == "ios" else "OSX"]
            if widget:
                profile["UUID"] = "87654321-1234-1234-1234-123456789012"
                profile["Entitlements"]["application-identifier"] += (
                    ".ReSchoolWidgets" if platform == "ios" else ".ReSchoolMacWidgets")
                if bad_certificate:
                    profile["DeveloperCertificates"] = [b"different-certificate"]
            name = "APPLE_WIDGET_PROFILE_BASE64" if widget else "APPLE_APP_PROFILE_BASE64"
            self.environment[name] = apple.base64.b64encode(plistlib.dumps(profile)).decode()
        with mock.patch.dict(os.environ, self.environment, clear=True), mock.patch("sys.stdout", new_callable=io.StringIO):
            apple.release(mock.Mock(target=self.target, upload=upload), "2.0.1", "1.1.1")

    def check_metadata(self, upload=False):
        direct = self.target == "macos-direct"
        platform = self.target.split("-")[0]
        output = self.root / "build/apple/artifacts"
        data = json.loads((output / "release.json").read_text())
        artifact = output / data["artifact"]
        self.assertEqual(data, {
            "commit": "fixture-commit", "target": self.target, "version": "2.0.1", "build": "1.1.1",
            "artifact": artifact.name, "platform": platform, "native_macos": platform == "macos",
            "uploaded_to_testflight": upload and not direct, "notarized": direct,
            "app_notarized": direct, "notarization_submission_ids": {"app": SUBMISSION, "dmg": SUBMISSION} if direct else {},
            "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
        })
        self.assertFalse((self.root / "reschool-apple-signing").exists())
        calls = [call.args for call in self.run.call_args_list]
        archive = next(args for args in calls if args[0] == "xcodebuild" and args[-1] == "archive")
        self.assertIn("generic/platform=macOS" if platform == "macos" else "generic/platform=iOS", archive)
        for setting in apple.MACOS_BUILD_SETTINGS:
            self.assertEqual(setting in archive, platform == "macos")
        self.assertEqual(sum(args[:2] == ("xcrun", "notarytool") for args in calls), 2 if direct else 0)
        self.assertEqual(sum(args[:2] == ("xcrun", "altool") for args in calls), 2 if upload and not direct else 0)
        return calls

    def test_macos_store_export_verifies_payload_without_cloud_calls(self):
        for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_BASE64"):
            self.environment.pop(name)
        self.execute()
        calls = self.check_metadata()
        self.assertEqual(self.options["installerSigningCertificate"], "B" * 40)
        self.assertEqual(self.options["signingCertificate"], IDENTITY)
        self.assertEqual(self.options["method"], "app-store-connect")
        self.assertTrue(any(args[:2] == ("pkgutil", "--expand-full") for args in calls))

    def test_macos_store_upload_runs_only_altool_after_pkg_verification(self):
        self.execute(upload=True)
        calls = self.check_metadata(upload=True)
        verified = max(i for i, args in enumerate(calls) if args[:2] == ("codesign", "-d"))
        uploaded = min(i for i, args in enumerate(calls) if args[:2] == ("xcrun", "altool"))
        self.assertLess(verified, uploaded)

    def test_apple_rejection_stops_release_even_when_altool_exits_zero(self):
        self.target = "ios-testflight"
        for operation in ("--validate-app", "--upload-app"):
            with self.subTest(operation=operation):
                self.failure = operation
                self.run.reset_mock()
                shutil.rmtree(self.root / "build", ignore_errors=True)
                with self.assertRaisesRegex(RuntimeError, "Apple did not confirm success"):
                    self.execute(upload=True)
                calls = [call.args[2] for call in self.run.call_args_list if call.args[:2] == ("xcrun", "altool")]
                self.assertEqual(calls, ["--validate-app"] if operation == "--validate-app" else ["--validate-app", "--upload-app"])
                self.assertFalse((self.root / "build/apple/artifacts/release.json").exists())
                self.assertFalse((self.root / "reschool-apple-signing").exists())

    def test_direct_notarizes_app_before_packaging_and_dmg_before_metadata(self):
        self.target = "macos-direct"
        self.execute()
        calls = self.check_metadata()
        self.assertEqual(self.options["method"], "developer-id")
        self.assertNotIn("installerSigningCertificate", self.options)
        assessments = [i for i, args in enumerate(calls) if args[0] == "spctl"]
        packaging = next(i for i, args in enumerate(calls) if args[0] == "hdiutil")
        self.assertEqual(len(assessments), 2)
        self.assertLess(assessments[0], packaging)
        self.assertLess(packaging, assessments[1])

    def test_direct_ticket_failure_does_not_write_success_metadata(self):
        self.target = "macos-direct"
        self.failure = "dmg-ticket"
        with self.assertRaisesRegex(RuntimeError, "stapler failed"):
            self.execute()
        self.assertFalse((self.root / "build/apple/artifacts/release.json").exists())
        self.assertFalse((self.root / "reschool-apple-signing").exists())

    def test_profile_certificate_mismatch_stops_before_build(self):
        with self.assertRaisesRegex(ValueError, "selected signing certificate"):
            self.execute(bad_certificate=True)
        self.prepare.assert_called_once()
        self.assertFalse(any(call.args[0] == "xcodebuild" for call in self.run.call_args_list))

    def test_wrong_installer_team_stops_before_build(self):
        def wrong_installer(*args, **kwargs):
            if args[:2] == ("security", "find-identity") and "basic" in args:
                return f'{IDENTITY} "3rd Party Mac Developer Installer: other (XXXXXXXXXX)"'.encode()
            return self.command(*args, **kwargs)
        self.run.side_effect = wrong_installer
        with self.assertRaisesRegex(ValueError, "matching distribution signing identity"):
            self.execute()
        self.prepare.assert_called_once()
        self.assertFalse(any(call.args[0] == "xcodebuild" for call in self.run.call_args_list))

    def test_app_notary_rejection_stops_before_dmg_packaging(self):
        self.target = "macos-direct"
        def rejected(*args, **kwargs):
            if args[:3] == ("xcrun", "notarytool", "submit"):
                return json.dumps({"status": "Invalid", "id": SUBMISSION}).encode()
            return self.command(*args, **kwargs)
        self.run.side_effect = rejected
        with self.assertRaisesRegex(ValueError, "did not accept"):
            self.execute()
        self.assertFalse(any(call.args[0] == "hdiutil" for call in self.run.call_args_list))
        self.assertFalse((self.root / "build/apple/artifacts/release.json").exists())

    def test_ios_signed_upload_retains_existing_export_and_upload_behavior(self):
        self.target = "ios-testflight"
        self.execute(upload=True)
        calls = self.check_metadata(upload=True)
        self.assertNotIn("installerSigningCertificate", self.options)
        self.assertFalse(any(args[0] == "lipo" or args[:2] == ("xcrun", "vtool") for args in calls))
        uploads = [args for args in calls if args[:2] == ("xcrun", "altool")]
        self.assertEqual([args[2] for args in uploads], ["--validate-app", "--upload-app"])
        self.assertTrue(all(args[args.index("--type") + 1] == "ios" for args in uploads))

    def test_unsigned_mac_command_forces_native_universal_without_cloud_or_signing(self):
        make_app(self.root / "build/apple/DerivedData/Build/Products/Release/reschool.app")
        with mock.patch.dict(os.environ, self.environment, clear=True), \
             mock.patch.object(apple.sys, "platform", "darwin"), mock.patch.object(apple.os, "umask"), \
             mock.patch.object(apple.sys, "argv", ["apple_release.py", "unsigned", "--target", "macos-testflight",
                                                "--version", "2.0.1", "--build", "101"]):
            apple.main()
        command = self.run.call_args_list[0].args
        for setting in (*apple.MACOS_BUILD_SETTINGS, "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO"):
            self.assertIn(setting, command)
        calls = [call.args for call in self.run.call_args_list]
        self.assertEqual(sum(args[0] == "lipo" for args in calls), 2)
        self.assertFalse(any(args[0] in ("security", "codesign", "spctl") or
                             args[:2] in (("xcrun", "altool"), ("xcrun", "notarytool")) for args in calls))


class TestFlightSubmissionTests(unittest.TestCase):
    def test_success_must_be_confirmed_for_each_operation(self):
        for responses in ((b"VERIFY SUCCEEDED with no errors", b"UPLOAD SUCCEEDED with no errors"),
                          (b"No errors validating archive.", b"No errors uploading archive.")):
            with mock.patch.object(apple, "run", side_effect=responses) as command, \
                 mock.patch("sys.stdout", new_callable=io.StringIO):
                apple.submit_to_testflight(Path("app.ipa"), "ios", "KEY", "ISSUER", Path("state"))
                self.assertEqual(command.call_count, 2)
                for call in command.call_args_list:
                    self.assertTrue(call.kwargs["capture_stderr"])

    def test_missing_or_conflicting_acknowledgement_fails_closed(self):
        for response in (b"", b"Connecting to Apple", b"UPLOAD SUCCEEDED",
                         b"VERIFY SUCCEEDED\nERROR: rejected",
                         b"VERIFY FAILED with 1 error"):
            with self.subTest(response=response), \
                 mock.patch.object(apple, "run", return_value=response) as command, \
                 mock.patch("sys.stdout", new_callable=io.StringIO), \
                 self.assertRaisesRegex(RuntimeError, "Apple did not confirm success"):
                apple.submit_to_testflight(Path("app.ipa"), "ios", "KEY", "ISSUER", Path("state"))
            self.assertEqual(command.call_count, 1)


class RunTests(unittest.TestCase):
    def test_can_capture_altool_stderr_with_stdout(self):
        result = apple.run(sys.executable, "-c", "import sys; print('VERIFY SUCCEEDED', file=sys.stderr)",
                           capture=True, capture_stderr=True)
        self.assertIn(b"VERIFY SUCCEEDED", result)

    def test_strips_original_secret_environment_and_applies_explicit_overrides(self):
        environment = {
            "APPLE_CERTIFICATE_P12_PASSWORD": "dummy-apple-secret",
            "ASC_PRIVATE_KEY_BASE64": "dummy-asc-secret",
            "APPLE_FUTURE_SECRET": "dummy-future-secret",
            "PATH": "dummy-path",
            "GITHUB_ACTIONS": "true",
            "OTHER_APPLE_SETTING": "not-prefixed",
        }
        with tempfile.TemporaryDirectory() as temporary:
            extra_env = {"API_PRIVATE_KEYS_DIR": temporary, "ASC_KEY_ID": "explicit-key-id"}
            for capture in (False, True):
                with self.subTest(capture=capture), \
                     mock.patch.dict(os.environ, environment, clear=True), \
                     mock.patch.object(apple.subprocess, "run") as subprocess_run:
                    subprocess_run.return_value = mock.Mock(returncode=0, stdout=b"output")
                    result = apple.run("dummy-tool", "argument", cwd=Path(temporary),
                                       capture=capture, extra_env=extra_env)
                    self.assertEqual(result, b"output" if capture else b"")
                    self.assertEqual(subprocess_run.call_count, 1)
                    args, kwargs = subprocess_run.call_args
                    self.assertEqual(args, (("dummy-tool", "argument"),))
                    child_env = kwargs["env"]
                    # сравниваем булевы значения, чтобы в тексте упавшего теста не всплыли секреты
                    for name, value in environment.items():
                        if name.startswith(("APPLE_", "ASC_")):
                            self.assertFalse(value in child_env.values(), name)
                            if name not in extra_env:
                                self.assertNotIn(name, child_env)
                        else:
                            self.assertTrue(child_env.get(name) == value, name)
                        self.assertTrue(os.environ.get(name) == value, name)
                    for name, value in extra_env.items():
                        self.assertTrue(child_env.get(name) == value, name)
                    self.assertEqual(kwargs["cwd"], Path(temporary))
                    self.assertFalse(kwargs["check"])
                    self.assertEqual(kwargs["stdout"], apple.subprocess.PIPE if capture else None)
                    self.assertEqual(kwargs["stderr"], apple.subprocess.PIPE if capture else None)

    def test_failed_command_does_not_expose_arguments_or_output(self):
        with tempfile.TemporaryDirectory() as temporary, \
             mock.patch.dict(os.environ, {}, clear=True), \
             mock.patch.object(apple.subprocess, "run") as subprocess_run:
            subprocess_run.return_value = mock.Mock(
                returncode=7, stdout=b"dummy-sensitive-output", stderr=b"dummy-sensitive-error")
            with self.assertRaises(RuntimeError) as error:
                apple.run(str(Path(temporary) / "dummy-tool"), "dummy-password",
                          cwd=Path(temporary), capture=True)
            self.assertTrue(str(error.exception) == "dummy-tool failed (exit 7)")


class CleanupTests(unittest.TestCase):
    def test_keychain_failures_preserve_journals_and_allow_successful_retry(self):
        for restore_fails, delete_fails in ((True, False), (False, True), (True, True)):
            with self.subTest(restore_fails=restore_fails, delete_fails=delete_fails), \
                 tempfile.TemporaryDirectory() as temporary, \
                 mock.patch.dict(os.environ, {"RUNNER_TEMP": temporary}, clear=True), \
                 mock.patch.object(apple, "run") as run:
                root = Path(temporary)
                state = root / "reschool-apple-signing"
                state.mkdir()
                keychain = state / "release.keychain-db"
                keychain.touch()
                original_keychains = [str(root / "original.keychain-db"),
                                      str(root / "another.keychain-db")]
                profiles = [root / "app.mobileprovision", root / "widget.provisionprofile"]
                for profile in profiles:
                    profile.touch()
                unrelated = root / "unrelated.mobileprovision"
                unrelated.touch()
                journals = {
                    "keychains.json": json.dumps(original_keychains),
                    "profiles.json": json.dumps([str(profile) for profile in profiles]),
                }
                for name, contents in journals.items():
                    (state / name).write_text(contents)
                raw_inputs = [state / name for name in (
                    "AuthKey_dummy.p8", "certificate.p12", "installer.p12",
                    "Runner.profile", "Widget.profile")]
                for path in raw_inputs:
                    path.write_bytes(b"dummy-private-input")
                run.side_effect = [
                    RuntimeError("restore failed") if restore_fails else b"",
                    RuntimeError("delete failed") if delete_fails else b"",
                ]
                expected_calls = [
                    mock.call("security", "list-keychains", "-d", "user", "-s",
                              *original_keychains, capture=True),
                    mock.call("security", "delete-keychain", str(keychain), capture=True),
                ]
                with self.assertRaisesRegex(RuntimeError, "Keychain cleanup failed"):
                    apple.cleanup()
                self.assertEqual(run.call_args_list, expected_calls)
                self.assertTrue(state.is_dir())
                for name, contents in journals.items():
                    self.assertEqual((state / name).read_text(), contents)
                for path in raw_inputs + profiles:
                    self.assertFalse(path.exists(), path.name)
                self.assertTrue(unrelated.exists())

                run.reset_mock(side_effect=True)
                run.return_value = b""
                apple.cleanup()
                self.assertEqual(run.call_args_list, expected_calls)
                self.assertFalse(state.exists())
                for profile in profiles:
                    self.assertFalse(profile.exists())
                self.assertTrue(unrelated.exists())

    def test_absent_state_is_a_no_op(self):
        with tempfile.TemporaryDirectory() as temporary, \
             mock.patch.dict(os.environ, {"RUNNER_TEMP": temporary}, clear=True), \
             mock.patch.object(apple, "run") as run:
            unrelated = Path(temporary) / "unrelated.profile"
            unrelated.touch()
            apple.cleanup()
            run.assert_not_called()
            self.assertEqual(list(Path(temporary).iterdir()), [unrelated])


if __name__ == "__main__":
    unittest.main()
