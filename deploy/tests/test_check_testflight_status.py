import datetime
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import check_testflight_status as status


class TestFlightStatusTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime.now(datetime.timezone.utc)
        self.build = {
            "id": "build-1", "attributes": {
                "processingState": "VALID", "expired": False,
                "expirationDate": "2099-01-01T00:00:00Z", "version": "1.5.1",
            },
            "relationships": {
                "preReleaseVersion": {"data": {"type": "preReleaseVersions", "id": "version-1"}},
                "buildBetaDetail": {"data": {"type": "buildBetaDetails", "id": "detail-1"}},
            },
        }
        self.version = {"platform": "IOS", "version": "2.0.0"}
        self.detail = {"externalBuildState": "IN_BETA_TESTING"}
        self.included = {
            ("preReleaseVersions", "version-1"): {"attributes": self.version},
            ("buildBetaDetails", "detail-1"): {"attributes": self.detail},
        }
        self.group = {"attributes": {
            "isInternalGroup": False, "publicLinkEnabled": True,
            "publicLink": status.DEFAULT_PUBLIC_URL,
        }}
        self.release = {"id": 42, "tag_name": "v2.0.0", "draft": False,
                        "prerelease": False, "assets": []}

    def client(self):
        client = Mock()
        client.listing.side_effect = [
            ([{"id": "app-1", "attributes": {"bundleId": status.BUNDLE}}], {}),
            ([self.build], self.included), ([self.group], {}),
        ]
        return client

    def test_only_external_testing_state_is_publishable(self):
        self.assertTrue(status.externally_testing(self.build, self.included, "2.0.0", self.now))
        for state in ("READY_FOR_BETA_TESTING", "BETA_APPROVED", "IN_BETA_REVIEW",
                      "WAITING_FOR_BETA_REVIEW", "READY_FOR_BETA_SUBMISSION", "BETA_REJECTED",
                      "EXPIRED", "MISSING_EXPORT_COMPLIANCE", "PROCESSING", None):
            with self.subTest(state=state), patch.dict(self.detail, {
                    "externalBuildState": state, "internalBuildState": "IN_BETA_TESTING"}):
                self.assertFalse(status.externally_testing(self.build, self.included, "2.0.0", self.now))

    def test_wrong_version_platform_expired_or_invalid_build_is_not_publishable(self):
        for resource, changes in [
            (self.version, {"platform": "MAC_OS"}), (self.version, {"version": "1.9.0"}),
            (self.build["attributes"], {"expired": True}),
            (self.build["attributes"], {"processingState": "INVALID"}),
            (self.build["attributes"], {"buildAudienceType": "INTERNAL_ONLY"}),
            (self.build["attributes"], {"expirationDate": "2000-01-01T00:00:00Z"}),
            (self.build["attributes"], {"expirationDate": "invalid"}),
            (self.build["attributes"], {"expirationDate": "2099-01-01"}),
        ]:
            with self.subTest(changes=changes), patch.dict(resource, changes):
                self.assertFalse(status.externally_testing(self.build, self.included, "2.0.0", self.now))
        self.assertFalse(status.externally_testing(self.build, {}, "2.0.0", self.now))

    def test_public_link_must_belong_to_external_group_containing_build(self):
        client = self.client()
        self.assertEqual(status.find_external_build(client, "2.0.0", status.DEFAULT_PUBLIC_URL), self.build)
        query = client.listing.call_args.kwargs
        self.assertEqual(query["filter[builds]"], "build-1")
        self.assertEqual(query["filter[app]"], "app-1")
        for change in ({"isInternalGroup": True}, {"publicLinkEnabled": False},
                       {"publicLink": "https://testflight.apple.com/join/Other"}):
            with self.subTest(change=change), patch.dict(self.group["attributes"], change):
                self.assertIsNone(status.find_external_build(self.client(), "2.0.0", status.DEFAULT_PUBLIC_URL))

    def test_publishes_exact_app_txt_without_overwrite(self):
        def command(*args, **kwargs):
            if args[1:3] == ("release", "upload"):
                self.assertEqual(args[3], "v2.0.0")
                path = Path(args[4])
                self.assertEqual(path.name, "app.txt")
                self.assertEqual(path.read_text(), status.DEFAULT_PUBLIC_URL + "\n")
                self.assertNotIn("--clobber", args)
                return b""
            return json.dumps(self.release).encode()
        with patch.object(status, "command", side_effect=command) as run:
            self.assertTrue(status.publish_if_ready("owner/repo", status.DEFAULT_PUBLIC_URL, self.client))
        self.assertEqual(run.call_count, 3)

    def test_missing_release_or_existing_marker_skips_apple_credentials(self):
        factory = Mock()
        for response in (None, json.dumps({**self.release, "assets": [{"name": "app.txt"}]}).encode()):
            with patch.object(status, "command", return_value=response):
                self.assertFalse(status.publish_if_ready("owner/repo", status.DEFAULT_PUBLIC_URL, factory))
        factory.assert_not_called()

    def test_pending_review_does_not_upload(self):
        with patch.dict(self.detail, {"externalBuildState": "IN_BETA_REVIEW"}), \
                patch.object(status, "command", return_value=json.dumps(self.release).encode()) as run:
            self.assertFalse(status.publish_if_ready("owner/repo", status.DEFAULT_PUBLIC_URL, self.client))
        self.assertEqual(run.call_count, 1)

    def test_api_failure_is_an_error_without_upload(self):
        client = Mock()
        client.listing.side_effect = status.SafeError("HTTP_403")
        with patch.object(status, "command", return_value=json.dumps(self.release).encode()) as run:
            with self.assertRaises(status.SafeError):
                status.publish_if_ready("owner/repo", status.DEFAULT_PUBLIC_URL, lambda: client)
        self.assertEqual(run.call_count, 1)

    def test_release_replacement_is_not_published(self):
        with patch.object(status, "command", side_effect=[json.dumps(self.release).encode(),
                json.dumps({**self.release, "id": 43}).encode()]) as run:
            with self.assertRaisesRegex(ValueError, "changed"):
                status.publish_if_ready("owner/repo", status.DEFAULT_PUBLIC_URL, self.client)
        self.assertEqual(run.call_count, 2)

    def test_rejects_unsupported_tag_or_link_before_apple_check(self):
        factory = Mock()
        with patch.object(status, "command", return_value=json.dumps({**self.release, "tag_name": "v2.0.0-rc1"}).encode()):
            with self.assertRaises(ValueError):
                status.publish_if_ready("owner/repo", status.DEFAULT_PUBLIC_URL, factory)
        with self.assertRaises(ValueError):
            status.publish_if_ready("owner/repo", "https://other.example/join/link", factory)
        factory.assert_not_called()


if __name__ == "__main__":
    unittest.main()
