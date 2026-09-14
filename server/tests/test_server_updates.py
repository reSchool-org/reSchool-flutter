"""проверяем выбор релиза, ограничения архива, обновление и восстановление"""
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'settings_manager'))
from manager import SettingsManager
from updater import unpack, version


def archive(extra=None, selected='2.1.0'):
    files = {'VERSION': selected.encode(), 'Dockerfile': b'new image',
             'requirements.txt': b'', 'entrypoint.sh': b'new entrypoint',
             'server_advanced/__main__.py': b'new main', **(extra or {})}
    result = io.BytesIO()
    with tarfile.open(fileobj=result, mode='w:gz') as tar:
        for name, data in files.items():
            member = tarfile.TarInfo(name)
            member.size = len(data)
            tar.addfile(member, io.BytesIO(data))
    return result.getvalue()


class UpdateTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        (self.root / '.env').write_bytes(b'API_TOKEN=secret\n')
        (self.root / 'VERSION').write_text('2.0.1\n')
        (self.root / 'Dockerfile').write_bytes(b'old image')
        self.manager = SettingsManager(self.root, self.root / 'socket', [])
        self.updater = self.manager.updater
        self.updater.release = '2.1.0'
        self.payload = {'operationId': 'a' * 36, 'version': '2.1.0'}

    def submit(self):
        with patch('updater.threading.Thread'):
            return self.updater.submit(self.payload)

    def apply(self, healthy=True, data=None, digest=None):
        data = data or archive()
        digest = digest or hashlib.sha256(data).hexdigest().encode()
        rows = {'server_advanced': {'Image': 'sha256:previous', 'Config': {'Image': 'reschool-server_advanced'}}}
        with patch('updater.download', side_effect=[digest, data]), patch('updater.time.sleep'), patch.object(self.manager, 'containers', return_value=rows), patch.object(self.manager, 'run', return_value=b'db-backup') as run, patch.object(self.manager, 'recreate') as restart, patch.object(self.manager, 'healthy', side_effect=healthy if isinstance(healthy, list) else None, return_value=healthy):
            self.updater.apply('2.1.0')
        return run, restart

    def test_numeric_versions_and_release_filter(self):
        self.assertGreater(version('2.10.0'), version('2.9.0'))
        for invalid in ('2.1', '2.1.0;id', '02.1.0', '2.1.0-beta'):
            with self.assertRaises(ValueError):
                version(invalid)
        releases = [dict(tag_name=tag, prerelease=pre, assets=[{'name': name} for name in ('reschool-server.tar.gz', 'reschool-server.tar.gz.sha256')]) for tag, pre in [('v99.0.0', False), ('server-v3.0.0', True), ('server-v2.10.0', False), ('server-v2.9.0', False)]]
        with patch('updater.download', return_value=json.dumps(releases).encode()):
            state = self.updater.snapshot(check=True)
        self.assertEqual(state['latestVersion'], '2.10.0')
        self.assertTrue(state['updateAvailable'])
        self.assertIsNotNone(state['checkedAt'])

    def test_no_release_and_unknown_install_are_not_up_to_date(self):
        with patch('updater.download', return_value=b'[]'):
            self.assertFalse(self.updater.snapshot(check=True)['updateAvailable'])
        (self.root / 'VERSION').unlink()
        self.assertFalse(self.updater.snapshot()['supported'])
        with self.assertRaises(ValueError):
            self.submit()

    def test_traversal_symlinks_and_version_mismatch_rejected(self):
        with self.assertRaises(ValueError):
            unpack(archive({'../.env': b'bad'}), '2.1.0')
        with self.assertRaises(ValueError):
            unpack(archive(), '3.0.0')
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w:gz') as tar:
            member = tarfile.TarInfo('server_advanced/link.py')
            member.type = tarfile.SYMTYPE
            member.linkname = '/etc/passwd'
            tar.addfile(member)
        with self.assertRaises(ValueError):
            unpack(data.getvalue(), '2.1.0')
        files = unpack(archive({'.env': b'bad', 'docker-compose.yml': b'bad', 'server_advanced/runtime/key.py': b'bad'}), '2.1.0')
        self.assertNotIn('.env', files)
        self.assertNotIn('docker-compose.yml', files)
        self.assertNotIn('server_advanced/runtime/key.py', files)

    def test_idempotence_and_settings_update_exclusion(self):
        self.submit()
        self.assertEqual(self.submit()['id'], self.payload['operationId'])
        with self.assertRaises(ValueError):
            self.updater.submit({**self.payload, 'operationId': 'b' * 36})
        with self.assertRaises(ValueError):
            self.manager.submit({'operationId': 'b' * 36})

    def test_success_keeps_configuration_and_runtime(self):
        runtime = self.root / 'server_advanced/runtime'
        runtime.mkdir(parents=True)
        (runtime / 'tls.pem').write_bytes(b'certificate')
        self.submit()
        run, restart = self.apply()
        self.assertEqual(self.manager.operation['status'], 'applied')
        self.assertEqual(self.updater.current(), '2.1.0')
        self.assertFalse(self.updater.snapshot()['updateAvailable'])
        self.assertEqual((self.root / '.env').read_bytes(), b'API_TOKEN=secret\n')
        self.assertEqual((runtime / 'tls.pem').read_bytes(), b'certificate')
        self.assertTrue((self.manager.backups / self.payload['operationId'] / 'database.dump').exists())
        restart.assert_called_once()
        self.assertTrue(any('build' in call.args[0] for call in run.call_args_list))

    def test_checksum_failure_does_not_restart_or_change_files(self):
        self.submit()
        run, restart = self.apply(digest=b'0' * 64)
        self.assertEqual(self.manager.operation['status'], 'failed')
        self.assertEqual((self.root / 'Dockerfile').read_bytes(), b'old image')
        restart.assert_not_called()
        run.assert_not_called()

    def test_failed_health_restores_files_and_image(self):
        self.submit()
        run, restart = self.apply(healthy=[False, True])
        self.assertEqual(self.manager.operation['status'], 'rolled_back')
        self.assertEqual((self.root / 'Dockerfile').read_bytes(), b'old image')
        self.assertEqual(self.updater.current(), '2.0.1')
        self.assertFalse((self.root / 'server_advanced/__main__.py').exists())
        self.assertEqual(restart.call_count, 2)
        run.assert_any_call(['docker', 'image', 'tag', 'sha256:previous', 'reschool-server_advanced'])

    def test_failed_rollback_requires_recovery_and_blocks_updates(self):
        self.submit()
        self.apply(healthy=False)
        self.assertEqual(self.manager.operation['status'], 'recovery_required')
        with self.assertRaises(ValueError):
            self.updater.submit({**self.payload, 'operationId': 'b' * 36})

    def test_restart_recovers_update_without_env_rollback(self):
        self.submit()
        self.manager.recover()
        self.assertEqual(self.manager.operation['status'], 'cancelled')
        self.manager.set_operation(status='applying', prepared=True)
        with patch.object(self.updater, 'restore') as restore:
            self.manager.recover()
        restore.assert_called_once()

    def test_local_symlink_is_not_followed(self):
        external = self.root / 'external'
        external.write_bytes(b'untouched')
        (self.root / 'Dockerfile').unlink()
        (self.root / 'Dockerfile').symlink_to(external)
        self.submit()
        self.apply()
        self.assertEqual(self.manager.operation['status'], 'failed')
        self.assertEqual(external.read_bytes(), b'untouched')


if __name__ == '__main__':
    unittest.main()
