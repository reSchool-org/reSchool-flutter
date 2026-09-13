import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "package_cloud_server", ROOT / ".github/scripts/package_cloud_server.py")
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class CloudServerPackageTests(unittest.TestCase):
    def test_ssh_can_extract_the_installer_from_the_shipped_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "server.tar.gz"
            with mock.patch.object(packager, "OUTPUT", archive):
                packager.package()
                extracted = subprocess.check_output([
                    "tar", "-xzOf", str(archive), "deploy/cloud-bootstrap.sh"])
                self.assertEqual(extracted, (ROOT / "server/deploy/cloud-bootstrap.sh").read_bytes())
                subprocess.run(["bash", "-n"], input=extracted, check=True)
                packager.package(check=True)
        # The installer must remain inside the archive, outside Flutter assets.
        self.assertFalse((ROOT / "assets/cloud/bootstrap.txt").exists())
        self.assertFalse((ROOT / "assets/cloud/bootstrap.sh").exists())
