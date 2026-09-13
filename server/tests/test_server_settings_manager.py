"""проверяем сохранение байтов, буквальные значения, конфликты и откат настроек хоста"""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'settings_manager'))
from manager import SettingsManager, atomic_write, patch_env
from schema import FIELDS, validate


class SettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.original = b'# keep all comments\r\nAPI_TOKEN=old-secret\r\nCF3_ENCRYPTION_KEY=unchanged\r\nGEMINI_MODEL=old\r\nOTHER="keep exactly"\r\n'
        (self.root / '.env').write_bytes(self.original)
        (self.root / 'compose.yml').write_text('services:\n  probe:\n    image: busybox\n    env_file: .env\n')
        self.manager = SettingsManager(self.root, self.root / 'socket', ['compose.yml'])

    def test_unchanged_bytes_and_only_selected_field(self):
        self.assertEqual(patch_env(self.original, {}), self.original)
        patched = patch_env(self.original, {'GEMINI_MODEL': 'new'})
        self.assertEqual(patched.replace(b'GEMINI_MODEL="new"\n', b'GEMINI_MODEL=old\r\n'), self.original)

    @unittest.skipUnless(shutil.which('docker'), 'Docker Compose parser required')
    def test_compose_roundtrip_special_characters(self):
        for value in ["pass'$#foo", 'slash\\quote\'end', 'tail\\', '${TOKEN} $HOME # comment', '\\${VAR}', ' leading trailing ', 'привет', 'double"quotes', '']:
            with self.subTest(value=value):
                (self.root / '.env').write_bytes(patch_env(b'', {'EXAMPLE': value}))
                result = subprocess.run(['docker', 'compose', '-f', str(self.root / 'compose.yml'), 'config', '--format', 'json'], capture_output=True, check=True)
                # compose экранирует доллары для повторного использования вывода как yaml
                actual = json.loads(result.stdout)['services']['probe']['environment']['EXAMPLE'].replace('$$', '$')
                self.assertEqual(actual, value)

    def test_protected_unknown_invalid_values_rejected(self):
        fields = list(FIELDS.values())
        for changes in [{'API_TOKEN': 'new'}, {'CF3_ENCRYPTION_KEY': 'new'}, {'DB_NAME': 'new'}, {'PATH': '/tmp'}, {'GEMINI_MODEL': 'bad\nAPI_TOKEN=new'}, {'ANALYSIS_ENABLED': 'yes'}, {'TEXTBOOK_INDEX_CHUNK': '17'}, {'GEMINI_TIMEOUT_SECONDS': '-1'}, {'GEMINI_API_KEY': 1}, {'GEMINI_MODEL': ''}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate(changes, fields)
        validate({'GEMINI_API_KEY': '', 'ANALYSIS_ENABLED': 'false'}, fields)

    def test_stale_revision_has_no_effect(self):
        with self.assertRaises(ValueError):
            self.manager.submit({'revision': 'outdated', 'operationId': 'a' * 36, 'changes': {'GEMINI_MODEL': 'new'}})
        self.assertEqual((self.root / '.env').read_bytes(), self.original)
        self.assertIsNone(self.manager.operation)

    def test_ai_provider_settings_validation_and_secret_masking(self):
        fields = list(FIELDS.values())
        validate({'AI_PROVIDER': 'openrouter', 'OPENROUTER_API_KEY': 'router-secret',
                  'OPENROUTER_MODEL': 'google/gemini-3.8-flash', 'OPENROUTER_TIMEOUT_SECONDS': '900'}, fields)
        for changes in [{'AI_PROVIDER': 'unknown'}, {'AI_PROVIDER': ''},
                        {'OPENROUTER_MODEL': ' '}, {'OPENROUTER_TIMEOUT_SECONDS': '0'}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate(changes, fields)
        config = {'services': {'server_advanced': {'environment': {}}}}
        containers = {'server_advanced': {'Config': {'Env': [
            'AI_PROVIDER=openrouter', 'OPENROUTER_API_KEY=router-secret',
        ]}}}
        with patch.object(self.manager, 'config', return_value=config), patch.object(self.manager, 'containers', return_value=containers), patch.object(self.manager, 'run', return_value=json.dumps(config)):
            snapshot = self.manager.snapshot()
        self.assertNotIn('router-secret', json.dumps(snapshot))
        key = next(f for f in snapshot['fields'] if f['key'] == 'OPENROUTER_API_KEY')
        self.assertEqual(key['value'], '')
        self.assertTrue(key['configured'])
        self.assertTrue(key['secret'])

    def test_save_applies_and_backs_up_exact_bytes(self):
        payload = {'revision': self.manager.revision(), 'operationId': 'a' * 36, 'changes': {'GEMINI_MODEL': 'new'}}
        with patch.object(self.manager, 'snapshot', return_value={'fields': [{**f, 'value': f['default']} for f in FIELDS.values()]}), patch('manager.threading.Thread'):
            result = self.manager.submit(payload)
        self.assertEqual(result['status'], 'queued')
        self.assertEqual((self.manager.backups / result['backup']).read_bytes(), self.original)
        with patch.object(self.manager, 'config'), patch.object(self.manager, 'recreate') as recreate, patch.object(self.manager, 'healthy', return_value=True), patch('manager.time.sleep'):
            self.manager.apply(self.original, payload['changes'])
        recreate.assert_called_once()
        self.assertEqual(self.manager.operation['status'], 'applied')
        self.assertEqual((self.root / '.env').stat().st_mode & 0o777, 0o600)
        self.assertNotIn('old-secret', self.manager.state_path.read_text())
        # повтор запроса не должен повторно перезапускать сервер даже после смены версии
        self.assertEqual(self.manager.submit(payload)['status'], 'applied')

    def test_startup_failure_restores_previous_file(self):
        backup = self.manager.backups / 'previous.env'
        atomic_write(backup, self.original)
        self.manager.operation = {'id': 'a' * 36, 'backup': backup.name, 'status': 'queued'}
        with patch.object(self.manager, 'config'), patch.object(self.manager, 'recreate') as restart, patch.object(self.manager, 'healthy', side_effect=[False, True]), patch('manager.time.sleep'):
            self.manager.apply(self.original, {'GEMINI_MODEL': 'new'})
        self.assertEqual(restart.call_count, 2)
        self.assertEqual(self.manager.operation['status'], 'rolled_back')
        self.assertEqual((self.root / '.env').read_bytes(), self.original)

    def test_crash_recovery_uses_persisted_backup(self):
        backup = self.manager.backups / 'previous.env'
        atomic_write(backup, self.original)
        self.manager.set_operation(id='a' * 36, backup=backup.name, status='applying')
        (self.root / '.env').write_bytes(b'GEMINI_MODEL=broken\n')
        restarted = SettingsManager(self.root, self.root / 'socket', ['compose.yml'])
        with patch.object(restarted, 'recreate'), patch.object(restarted, 'healthy', return_value=True):
            restarted.recover()
        self.assertEqual((self.root / '.env').read_bytes(), self.original)
        self.assertEqual(restarted.operation['status'], 'rolled_back')

    def test_external_edit_before_apply_is_not_overwritten(self):
        self.manager.operation = {'id': 'a' * 36, 'status': 'queued'}
        external = self.original + b'# external edit\n'
        (self.root / '.env').write_bytes(external)
        with patch('manager.time.sleep'):
            self.manager.apply(self.original, {'GEMINI_MODEL': 'new'})
        self.assertEqual((self.root / '.env').read_bytes(), external)
        self.assertEqual(self.manager.operation['status'], 'cancelled')

class CredentialSessionTests(unittest.TestCase):
    def test_existing_session_adopted_but_changes_and_rollback_force_login(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('credential_marker', Path(__file__).resolve().parents[1] / 'server_advanced' / 'server_credentials.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            changed = module.credentials_changed
            self.assertFalse(changed(directory, 'old-user', 'old-pass', 'key'))
            self.assertFalse(changed(directory, 'old-user', 'old-pass', 'key'))
            self.assertTrue(changed(directory, 'new-user', 'new-pass', 'key'))
            self.assertTrue(changed(directory, 'new-user', 'new-pass', 'key'))
            self.assertTrue(changed(directory, 'old-user', 'old-pass', 'key'))
            self.assertNotIn('old-pass', (Path(directory) / 'server-credentials.json').read_text())


if __name__ == '__main__':
    unittest.main()
