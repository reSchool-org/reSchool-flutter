import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).parents[1]))
import publish_apple_release as publisher


COMMIT = "a" * 40
VERSION = "2.0.0"
REPO = "example/reschool"
TAG = "v" + VERSION
MARKER = f"<!-- reschool-apple-release:{COMMIT} -->"
TARGETS = ("ios-testflight", "macos-testflight", "macos-direct")
PUBLIC = {"ios-testflight": "reSchool-ios.ipa", "macos-direct": "reSchool-macos.dmg"}


class ArtifactFixture(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.inputs = self.root / "inputs"
        self.inputs.mkdir()
        self.data = {}
        for target, suffix in zip(TARGETS, (".ipa", ".pkg", ".dmg")):
            directory = self.inputs / ("apple-" + target + "-123-1")
            directory.mkdir()
            artifact = directory / ("original" + suffix)
            artifact.write_bytes(("dummy distribution: " + target).encode())
            direct = target == "macos-direct"
            self.data[target] = {
                "target": target, "commit": COMMIT, "version": VERSION,
                "build": "1.1.1", "artifact": artifact.name,
                "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
                "platform": "ios" if target == "ios-testflight" else "macos",
                "native_macos": target != "ios-testflight",
                "uploaded_to_testflight": not direct,
                "notarized": direct, "app_notarized": direct,
                "notarization_submission_ids": {},
            }
            self.metadata(target).write_text(json.dumps(self.data[target]))
        # неожиданные команды должны падать локально, а не звать gh и подписывающие утилиты
        self.process = self.enterContext(mock.patch.object(
            publisher.subprocess, "run", side_effect=AssertionError("Unexpected subprocess")))
        self.gh = self.enterContext(mock.patch.object(
            publisher, "command", side_effect=AssertionError("Unexpected GitHub call")))
        self.output = self.enterContext(mock.patch("sys.stdout", new_callable=io.StringIO))

    def metadata(self, target):
        return self.inputs / ("apple-" + target + "-123-1") / "release.json"

    def artifact(self, target):
        return self.metadata(target).parent / self.data[target]["artifact"]

    def publish(self, **overrides):
        options = dict(root=self.inputs, repo=REPO, commit=COMMIT,
                       version=VERSION, targets=list(TARGETS))
        options.update(overrides)
        publisher.publish(**options)

    def reject(self, message, **overrides):
        with self.assertRaisesRegex(ValueError, message):
            self.publish(**overrides)
        self.gh.assert_not_called()
        self.process.assert_not_called()


class VerifiedAssetsTests(ArtifactFixture):
    def test_all_targets_verified_but_only_ipa_and_dmg_returned(self):
        records = publisher.verified_assets(self.inputs, list(TARGETS), VERSION, COMMIT)
        self.assertEqual(set(records), set(PUBLIC))
        for target, (artifact, data) in records.items():
            self.assertEqual(artifact, self.artifact(target))
            self.assertEqual(data, self.data[target])
        # символы могут лежать рядом со сборками, но публичными файлами релиза становиться не должны
        (self.metadata("ios-testflight").parent / "dSYMs.zip").write_bytes(b"dummy symbols")
        self.assertEqual(publisher.verified_assets(self.inputs, TARGETS, VERSION, COMMIT), records)

    def test_invalid_target_selection(self):
        for targets in ([], ["unknown"], ["ios-testflight", "ios-testflight"]):
            with self.subTest(targets=targets):
                self.reject("Invalid expected release targets", targets=targets)

    def test_missing_duplicate_and_unexpected_targets(self):
        metadata = self.metadata("macos-testflight")
        directory = metadata.parent
        moved = self.root / directory.name
        directory.rename(moved)
        self.reject("All requested distribution jobs")
        moved.rename(directory)
        duplicate = self.inputs / "duplicate"
        duplicate.mkdir()
        (duplicate / "release.json").write_bytes(metadata.read_bytes())
        artifact = self.artifact("macos-testflight")
        (duplicate / artifact.name).write_bytes(artifact.read_bytes())
        self.reject("Duplicate or unexpected release target")
        (duplicate / "release.json").unlink()
        (duplicate / artifact.name).unlink()
        duplicate.rmdir()
        self.reject("Duplicate or unexpected release target", targets=list(PUBLIC))

    def test_required_metadata_fields_on_every_target(self):
        bad_values = {
            "target": "unknown", "commit": "b" * 40, "version": "1.0.8",
            "artifact": "", "sha256": "0" * 64, "platform": "maccatalyst",
        }
        for target in TARGETS:
            for key, value in bad_values.items():
                for missing in (False, True):
                    with self.subTest(target=target, key=key, missing=missing):
                        data = dict(self.data[target])
                        if missing:
                            data.pop(key)
                        else:
                            data[key] = value
                        self.metadata(target).write_text(json.dumps(data))
                        self.reject(".+")
                        self.metadata(target).write_text(json.dumps(self.data[target]))

    def test_native_and_both_notarization_flags_require_literal_true(self):
        for target, keys in (("macos-testflight", ("native_macos",)),
                             ("macos-direct", ("native_macos", "notarized", "app_notarized"))):
            for key in keys:
                for value in (False, 1, "true", None):
                    with self.subTest(target=target, key=key, value=value):
                        data = dict(self.data[target])
                        if value is None:
                            data.pop(key)
                        else:
                            data[key] = value
                        self.metadata(target).write_text(json.dumps(data))
                        self.reject("native desktop|Both the macOS app and DMG")
                        self.metadata(target).write_text(json.dumps(self.data[target]))

    def test_missing_malformed_and_oversized_metadata(self):
        metadata = self.metadata("ios-testflight")
        metadata.unlink()
        self.reject("Missing or invalid release metadata")
        for contents in ("", "{", "{}", " " * 16385):
            with self.subTest(contents=contents[:20]):
                metadata.write_text(contents)
                self.reject(".+")

    def test_input_root_and_entries_must_be_real_directories(self):
        link = self.root / "linked-inputs"
        link.symlink_to(self.inputs, target_is_directory=True)
        file = self.root / "file"
        file.write_bytes(b"dummy")
        for root in (link, file, self.root / "absent"):
            with self.subTest(root=root.name):
                self.reject("real directory", root=root)
        (self.inputs / "unexpected.txt").write_bytes(b"dummy")
        self.reject("Unexpected artifact input")

    def test_wrong_json_shapes_fail_closed_before_github(self):
        target = "ios-testflight"
        for data in ([], None, 12, {**self.data[target], "target": []},
                     {**self.data[target], "sha256": None}):
            with self.subTest(data=data):
                self.metadata(target).write_text(json.dumps(data))
                # main пока не ловит ошибки типов, приведение к ValueError
                # должно сохранить это поведение, то есть падать, а не продолжать
                with self.assertRaises((ValueError, TypeError, AttributeError)):
                    self.publish()
                self.gh.assert_not_called()
                self.process.assert_not_called()

    def test_rejects_symlinks_at_each_artifact_level(self):
        for path in (self.metadata("ios-testflight").parent,
                     self.metadata("ios-testflight"), self.artifact("ios-testflight")):
            with self.subTest(path=path.name):
                outside = self.root / path.name
                path.rename(outside)
                path.symlink_to(outside, target_is_directory=outside.is_dir())
                self.reject("Unexpected artifact input|invalid release metadata|Missing signed")
                path.unlink()
                outside.rename(path)

    def test_rejects_traversal_absolute_and_unsafe_artifact_names(self):
        target = "ios-testflight"
        outside = self.root / "outside.ipa"
        outside.write_bytes(self.artifact(target).read_bytes())
        for name in ("../../outside.ipa", str(outside), "sub/original.ipa",
                     "..\\outside.ipa", ".", "..", "bad name.ipa", "--bad;.ipa", 12):
            with self.subTest(name=name):
                data = {**self.data[target], "artifact": name}
                self.metadata(target).write_text(json.dumps(data))
                self.reject("Invalid artifact filename|Missing signed")

    def test_missing_empty_wrong_suffix_and_corrupt_artifacts_on_every_target(self):
        for target in TARGETS:
            artifact = self.artifact(target)
            original = artifact.read_bytes()
            for content in (None, b"", b"corrupted distribution"):
                with self.subTest(target=target, content=content):
                    if content is None:
                        artifact.unlink()
                    else:
                        artifact.write_bytes(content)
                    self.reject("Missing signed|checksum mismatch")
                    artifact.write_bytes(original)
            wrong = artifact.with_suffix(".zip")
            artifact.rename(wrong)
            self.metadata(target).write_text(json.dumps({**self.data[target], "artifact": wrong.name}))
            self.reject("Missing signed")
            wrong.rename(artifact)
            self.metadata(target).write_text(json.dumps(self.data[target]))

    def test_sha256_must_be_full_lowercase_hex(self):
        target = "ios-testflight"
        for digest in ("", "a" * 63, "a" * 65, "g" * 64,
                       self.data[target]["sha256"].upper(), "sha256:" + self.data[target]["sha256"]):
            with self.subTest(digest=digest):
                self.metadata(target).write_text(json.dumps({**self.data[target], "sha256": digest}))
                self.reject("checksum mismatch")

    def test_pkg_only_is_not_a_public_release(self):
        for target in PUBLIC:
            self.metadata(target).parent.rename(self.root / target)
        self.assertEqual(publisher.verified_assets(
            self.inputs, ["macos-testflight"], VERSION, COMMIT), {})
        self.reject("Only IPA and DMG", targets=["macos-testflight"])


class PublicationTests(ArtifactFixture):
    def mock_github(self, release=None, tag_commit=None, fail_write=None):
        self.staged = {}
        self.staging_paths = []
        reads = {
            f"repos/{REPO}/releases/tags/{TAG}": None if release is None else json.dumps(release).encode(),
            f"repos/{REPO}/git/ref/tags/{TAG}": None if tag_commit is None else b'{"ref":"refs/tags/v2.0.0"}',
            # даже для аннотированных тегов идём через /commits, а не берём sha самого тега
            f"repos/{REPO}/commits/{TAG}": json.dumps({"sha": tag_commit}).encode(),
        }

        def command(*args, **kwargs):
            self.assertEqual(args[0], "gh")
            if args[1] == "api":
                self.assertEqual(len(args), 3)
                self.assertIn(args[2], reads)
                self.assertEqual(kwargs, {} if "/commits/" in args[2] else {"missing_ok": True})
                return reads[args[2]]
            self.assertEqual(args[1], "release")
            self.assertIn(args[2], ("create", "upload", "edit"))
            self.assertEqual(args[3], TAG)
            self.assertEqual(args[args.index("--repo") + 1], REPO)
            self.assertNotIn("--clobber", args)
            for argument in args[4:]:
                if argument.startswith(tempfile.gettempdir() + "/"):
                    path = Path(argument)
                    self.staging_paths.append(path)
                    self.staged[path.name] = path.read_bytes()
            if args[2] == fail_write:
                raise RuntimeError("simulated GitHub failure")
            return b""

        self.gh.side_effect = command

    def writes(self):
        return [call.args for call in self.gh.call_args_list if call.args[1] == "release"]

    def test_new_release_stages_stable_assets_and_sidecars_before_publishing(self):
        self.mock_github()
        self.publish()
        writes = self.writes()
        self.assertEqual([args[2] for args in writes], ["create", "edit"])
        create = writes[0]
        self.assertIn("--draft", create)
        self.assertEqual(create[create.index("--target") + 1], COMMIT)
        self.assertEqual(create[create.index("--title") + 1], "reSchool " + VERSION)
        notes = create[create.index("--notes") + 1]
        self.assertIn(MARKER, notes)
        self.assertIn("TestFlight", notes)
        self.assertIn("notarized", notes)
        self.assertEqual(writes[1], ("gh", "release", "edit", TAG, "--repo", REPO, "--draft=false"))
        self.assertEqual(set(self.staged), {
            name + suffix for name in PUBLIC.values() for suffix in ("", ".sha256", ".release.json")})
        for target, name in PUBLIC.items():
            data = self.data[target]
            self.assertEqual(self.staged[name], self.artifact(target).read_bytes())
            self.assertEqual(self.staged[name + ".sha256"], f"{data['sha256']}  {name}\n".encode())
            self.assertEqual(json.loads(self.staged[name + ".release.json"]), {**data, "release_asset": name})
        self.assertTrue(self.staging_paths)
        self.assertTrue(all(not path.parent.exists() for path in self.staging_paths))
        self.assertEqual(self.output.getvalue(), f"https://github.com/{REPO}/releases/tag/{TAG}\n")
        self.process.assert_not_called()

    def test_wrong_tag_commit_fails_before_any_write_even_for_managed_draft(self):
        for release in (None, {"draft": False}, {"draft": True, "body": MARKER, "target_commitish": COMMIT}):
            for wrong in ("b" * 40, COMMIT[:7]):
                with self.subTest(release=release, wrong=wrong):
                    self.gh.reset_mock()
                    self.mock_github(release, wrong)
                    with self.assertRaisesRegex(ValueError, "another commit"):
                        self.publish()
                    self.assertEqual(self.writes(), [])
                    self.assertEqual(self.gh.call_args_list[-1],
                                     mock.call("gh", "api", f"repos/{REPO}/commits/{TAG}"))

    def test_unverifiable_release_and_unmanaged_draft_are_not_modified(self):
        cases = [({"draft": False}, None),
                 ({"draft": True, "body": MARKER, "target_commitish": "main"}, None),
                 ({"draft": True, "body": "unrelated", "target_commitish": COMMIT}, COMMIT),
                 ({"draft": True, "body": None}, COMMIT),
                 ({"draft": True, "body": MARKER.replace(COMMIT, "b" * 40)}, COMMIT)]
        for release, commit in cases:
            with self.subTest(release=release, commit=commit):
                self.gh.reset_mock()
                self.mock_github(release, commit)
                with self.assertRaisesRegex(ValueError, "no verifiable tag|unrelated draft"):
                    self.publish()
                self.assertEqual(self.writes(), [])

    def test_managed_draft_resumes_with_or_without_existing_tag(self):
        for tag_commit in (None, COMMIT):
            with self.subTest(tag_commit=tag_commit):
                self.gh.reset_mock()
                self.mock_github({"draft": True, "body": MARKER, "target_commitish": COMMIT}, tag_commit)
                self.publish()
                self.assertEqual([args[2] for args in self.writes()], ["upload", "edit"])
                self.assertEqual(len(self.staged), 6)

    def test_identical_shipped_assets_are_noop_and_each_conflicting_sidecar_is_refused(self):
        self.mock_github()
        self.publish()
        assets = [{"name": name, "digest": "sha256:" + hashlib.sha256(content).hexdigest()}
                  for name, content in self.staged.items()]
        release = {"draft": False, "assets": assets}
        self.gh.reset_mock()
        self.mock_github(release, COMMIT)
        self.publish()
        self.assertEqual(self.writes(), [])
        for asset in assets:
            for digest in (None, "sha256:" + "0" * 64):
                with self.subTest(asset=asset["name"], digest=digest):
                    self.gh.reset_mock()
                    # если хоть один файл конфликтует, частичный релиз всё равно ничего не заливает
                    self.mock_github({"draft": False, "assets": [{**asset, "digest": digest}]}, COMMIT)
                    with self.assertRaisesRegex(ValueError, "different asset already exists"):
                        self.publish()
                    self.assertEqual(self.writes(), [])

    def test_partial_published_release_uploads_only_missing_assets_without_editing(self):
        name = PUBLIC["ios-testflight"]
        release = {"draft": False, "assets": [
            {"name": name, "digest": "sha256:" + self.data["ios-testflight"]["sha256"]},
            {"name": "unrelated.txt", "digest": "sha256:" + "0" * 64},
        ]}
        self.mock_github(release, COMMIT)
        self.publish()
        self.assertEqual([args[2] for args in self.writes()], ["upload"])
        self.assertEqual(len(self.staged), 5)
        self.assertNotIn(name, self.staged)
        self.assertNotIn("unrelated.txt", self.staged)

    def test_failed_create_or_upload_never_publishes_and_removes_staging(self):
        for operation, release in (("create", None), ("upload", {
                "draft": True, "body": MARKER, "target_commitish": COMMIT})):
            with self.subTest(operation=operation):
                self.gh.reset_mock()
                self.mock_github(release, fail_write=operation)
                with self.assertRaisesRegex(RuntimeError, "simulated GitHub failure"):
                    self.publish()
                self.assertEqual([args[2] for args in self.writes()], [operation])
                self.assertTrue(self.staging_paths)
                self.assertTrue(all(not path.parent.exists() for path in self.staging_paths))

    def test_invalid_cli_values_fail_before_github(self):
        for options in ({"repo": "--bad"}, {"repo": "owner/repo/extra"},
                        {"commit": "main"}, {"commit": "A" * 40},
                        {"version": "1.0"}, {"version": "2.0.0;bad"}):
            with self.subTest(options=options):
                self.reject(".+", **options)


class CommandTests(unittest.TestCase):
    def test_only_explicit_404_can_be_treated_as_missing(self):
        for code, stderr, missing_ok in ((0, b"", False), (1, b"HTTP 404: Not Found", True),
                                        (1, b"HTTP 404: Not Found", False),
                                        (1, b"HTTP 403: Forbidden", True), (1, b"network error", True)):
            with self.subTest(code=code, stderr=stderr, missing_ok=missing_ok), \
                 mock.patch.object(publisher.subprocess, "run", return_value=mock.Mock(
                     returncode=code, stdout=b"response", stderr=stderr)) as run:
                if code == 0:
                    self.assertEqual(publisher.command("gh", "api", "dummy", missing_ok=missing_ok), b"response")
                elif missing_ok and b"HTTP 404" in stderr:
                    self.assertIsNone(publisher.command("gh", "api", "dummy", missing_ok=missing_ok))
                else:
                    with self.assertRaisesRegex(RuntimeError, "no release assets were overwritten"):
                        publisher.command("gh", "api", "dummy", missing_ok=missing_ok)
                run.assert_called_once_with(("gh", "api", "dummy"), capture_output=True, check=False)


if __name__ == "__main__":
    unittest.main()
