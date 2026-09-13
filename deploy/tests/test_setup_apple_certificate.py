import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch


spec = importlib.util.spec_from_file_location(
    "setup_certificate", Path(__file__).parents[1] / "setup_apple_certificate.py")
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupCertificateTests(unittest.TestCase):
    def test_password_requires_interactive_terminal(self):
        with patch("sys.argv", ["setup", "--p12", "/unused.p12"]), \
                patch("sys.stdin.isatty", return_value=False), \
                patch.object(setup, "command") as command:
            with self.assertRaises(RuntimeError):
                setup.main()
            command.assert_not_called()

    def run_setup(self, directory, *, valid_password=True, branch="main", kind=None,
                  environment=None, cn="Apple Distribution:", team="AQ52Q995ZR", reject=False,
                  also_repo=None, second_branch="main", repo=None):
        source = Path(directory) / "identity.p12"
        source.write_bytes(b"test fixture, not a real private key")
        environment_config = {"deployment_branch_policy": {
            "protected_branches": False, "custom_branch_policies": True},
            "protection_rules": []}
        branches = {"total_count": 1, "branch_policies": [{"name": branch, "type": "branch"}]}
        outputs = [json.dumps(environment_config).encode(), json.dumps(branches).encode()]
        if also_repo is not None:
            outputs += [json.dumps(environment_config).encode(), json.dumps({
                "total_count": 1, "branch_policies": [{"name": second_branch, "type": "branch"}]}).encode()]
        outputs += [b"-----BEGIN CERTIFICATE-----\nfixture\n-----END CERTIFICATE-----",
                    f"subject=CN={cn} Test,OU={team},O=Test,C=US\n".encode(),
                    b""] + [b""] * (6 if also_repo is not None else 3)
        output = io.StringIO()
        argv = ["setup", "--p12", str(source)]
        if kind is not None:
            argv += ["--kind", kind]
        if environment is not None:
            argv += ["--environment", environment]
        if also_repo is not None:
            argv += ["--also-repo", also_repo]
        if repo is not None:
            argv += ["--repo", repo]

        def password_prompt(_):
            self.assertEqual(command.call_count, 4 if also_repo is not None else 2)
            self.assertTrue(all(call.args[:2] == ("gh", "api") for call in command.call_args_list))
            return "fixture-password"

        with patch("sys.argv", argv), \
                patch("sys.stdin.isatty", return_value=True), \
                patch.object(setup.getpass, "getpass", side_effect=password_prompt) as password, \
                patch.object(Path, "read_bytes", autospec=True, side_effect=Path.read_bytes) as read, \
                patch.object(setup, "command", side_effect=outputs) as command, \
                patch.object(setup.subprocess, "run", return_value=Mock(
                    returncode=0 if valid_password else 1,
                    stderr=b"Shrouded Keybag" if valid_password else b"Mac verify error")) as run, \
                contextlib.redirect_stdout(output):
            if reject or not valid_password or branch != "main" or second_branch != "main":
                with self.assertRaises(RuntimeError):
                    setup.main()
                self.assertFalse(any(call.args[:3] == ("gh", "secret", "set")
                                     for call in command.call_args_list))
                if branch != "main" or second_branch != "main":
                    password.assert_not_called()
                    run.assert_not_called()
            else:
                setup.main()
                calls = [call for call in command.call_args_list
                         if call.args[:3] == ("gh", "secret", "set")]
                repos = [repo or "reSchool-org/reSchool-Flutter-test"] + ([also_repo] if also_repo is not None else [])
                self.assertEqual(len(calls), 3 * len(repos))
                prefix = "APPLE_INSTALLER" if kind == "installer" else "APPLE_CERTIFICATE"
                self.assertEqual([call.args[3] for call in calls], [
                    prefix + "_P12_BASE64", prefix + "_P12_PASSWORD", "APPLE_TEAM_ID"] * len(repos))
                self.assertEqual([call.args[5] for call in calls], [repo for repo in repos for _ in range(3)])
                if also_repo is not None:
                    for first, second in zip(calls[:3], calls[3:]):
                        self.assertEqual(first.kwargs, second.kwargs)
                password.assert_called_once()
                read.assert_called_once_with(source)
                run.assert_called_once()
                for call in calls:
                    self.assertNotIn("fixture-password", call.args)
                    self.assertEqual(call.args[-1], environment or "apple-ios-testflight")
                password_call = next(call for call in calls
                                     if call.args[3] == prefix + "_P12_PASSWORD")
                self.assertEqual(password_call.kwargs["data"], b"fixture-password")
                self.assertTrue(run.call_args.kwargs["capture_output"])
                self.assertEqual(run.call_args.kwargs["input"], b"fixture-password\n")
                self.assertNotIn("fixture-password", repr(run.call_args.args))
            self.assertNotIn("fixture-password", output.getvalue())
            self.assertEqual(source.stat().st_mode & 0o777, 0o600)

    def test_upload_uses_stdin_not_password_arguments(self):
        with tempfile.TemporaryDirectory() as directory:
            self.run_setup(directory)

    def test_wrong_password_never_uploads(self):
        with tempfile.TemporaryDirectory() as directory:
            self.run_setup(directory, valid_password=False)

    def test_wrong_branch_never_uploads(self):
        with tempfile.TemporaryDirectory() as directory:
            self.run_setup(directory, branch="*")

    def test_dual_repo_mac_identities_prompt_and_load_once(self):
        for kind, environment, cn in (
            ("installer", "apple-macos-testflight", "Mac Installer Distribution:"),
            ("developer-id", "apple-macos-direct", "Developer ID Application:"),
        ):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as directory:
                self.run_setup(directory, kind=kind, environment=environment, cn=cn,
                               also_repo="reSchool-org/reSchool-flutter")

    def test_invalid_second_branch_blocks_password_and_all_uploads(self):
        with tempfile.TemporaryDirectory() as directory:
            self.run_setup(directory, also_repo="reSchool-org/reSchool-flutter", second_branch="*")

    def test_explicit_primary_repo_does_not_upload_to_default(self):
        with tempfile.TemporaryDirectory() as directory:
            self.run_setup(directory, repo="reSchool-org/reSchool-flutter")

    def test_invalid_or_duplicate_repo_rejected_before_io(self):
        invalid = ["", "owner", "owner/repo/extra", "../repo", "owner/..", "owner/repo?query=1",
                   "https://github.com/owner/repo", "owner/repo\n", "--repo/other", "owner/repo space"]
        for arguments in ([flag + "=" + value] for flag in ("--repo", "--also-repo") for value in invalid):
            with self.subTest(arguments=arguments), \
                    patch("sys.argv", ["setup", "--p12", "/unused.p12", *arguments]), \
                    patch.object(setup, "command") as command, \
                    patch.object(setup.getpass, "getpass") as password:
                with self.assertRaises(RuntimeError):
                    setup.main()
                command.assert_not_called()
                password.assert_not_called()
        for repo in ("reSchool-org/reSchool-Flutter-test", "RESCHOOL-ORG/RESCHOOL-FLUTTER-TEST"):
            with self.subTest(repo=repo), \
                    patch("sys.argv", ["setup", "--p12", "/unused.p12", "--also-repo", repo]), \
                    patch.object(setup, "command") as command, \
                    patch.object(setup.getpass, "getpass") as password:
                with self.assertRaisesRegex(RuntimeError, "Duplicate"):
                    setup.main()
                command.assert_not_called()
                password.assert_not_called()

    def test_mac_kinds_and_secret_destinations(self):
        cases = [
            ("distribution", "apple-macos-testflight", "Apple Distribution:"),
            ("distribution", "apple-macos-testflight", "3rd Party Mac Developer Application:"),
            ("installer", "apple-macos-testflight", "3rd Party Mac Developer Installer:"),
            ("installer", "apple-macos-testflight", "Mac Installer Distribution:"),
            ("developer-id", "apple-macos-direct", "Developer ID Application:"),
        ]
        for kind, environment, cn in cases:
            with self.subTest(kind=kind, cn=cn), tempfile.TemporaryDirectory() as directory:
                self.run_setup(directory, kind=kind, environment=environment, cn=cn)

    def test_invalid_kind_destination_stops_before_any_io_or_password(self):
        allowed = {"distribution": {"apple-ios-testflight", "apple-macos-testflight"},
                   "installer": {"apple-macos-testflight"}, "developer-id": {"apple-macos-direct"}}
        for kind, destinations in allowed.items():
            for environment in ("apple-ios-testflight", "apple-macos-testflight", "apple-macos-direct", "other"):
                if environment in destinations:
                    continue
                with self.subTest(kind=kind, environment=environment), \
                        patch("sys.argv", ["setup", "--p12", "/unused.p12", "--kind", kind,
                                           "--environment", environment]), \
                        patch.object(setup, "command") as command, \
                        patch.object(setup.getpass, "getpass") as password, \
                        patch.object(setup.subprocess, "run") as run:
                    with self.assertRaisesRegex(RuntimeError, "destination"):
                        setup.main()
                    command.assert_not_called()
                    password.assert_not_called()
                    run.assert_not_called()

    def test_wrong_certificate_type_or_team_never_uploads(self):
        cases = [
            ("distribution", "apple-ios-testflight", "Developer ID Application:", "AQ52Q995ZR"),
            ("distribution", "apple-ios-testflight", "3rd Party Mac Developer Application:", "AQ52Q995ZR"),
            ("distribution", "apple-macos-testflight", "Developer ID Application:", "AQ52Q995ZR"),
            ("installer", "apple-macos-testflight", "Developer ID Installer:", "AQ52Q995ZR"),
            ("installer", "apple-macos-testflight", "Apple Distribution:", "AQ52Q995ZR"),
            ("developer-id", "apple-macos-direct", "Apple Distribution:", "AQ52Q995ZR"),
            ("developer-id", "apple-macos-direct", "Developer ID Application:", "XXXXXXXXXX"),
            ("installer", "apple-macos-testflight", "Mac Installer Distribution:", "XXXXXXXXXX"),
            ("distribution", "apple-ios-testflight", "Apple Distribution:", "XXXXXXXXXX"),
            ("distribution", "apple-ios-testflight", "Other\\,CN=Apple Distribution:", "AQ52Q995ZR"),
        ]
        for kind, environment, cn, team in cases:
            with self.subTest(kind=kind, cn=cn, team=team), tempfile.TemporaryDirectory() as directory:
                self.run_setup(directory, kind=kind, environment=environment, cn=cn, team=team, reject=True)


if __name__ == "__main__":
    unittest.main()
