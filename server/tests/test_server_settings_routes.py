"""проверяем права администратора, отсутствие секретов в логах и сбои службы хоста"""
import io
import json
import unittest
from contextlib import redirect_stdout
from unittest.mock import MagicMock, patch

from server_advanced.app import app
from server_advanced.routes import server_settings


class RoutesTests(unittest.TestCase):
    def setUp(self):
        app.config['TESTING'] = True
        self.client = app.test_client()
        auth = patch('server_advanced.app.API_TOKEN', 'test-admin-token')
        auth.start()
        self.addCleanup(auth.stop)
        blocked = patch('server_advanced.app.is_ip_blocked', return_value=False)
        blocked.start()
        self.addCleanup(blocked.stop)

    def test_anonymous_and_member_cannot_read_or_modify_settings(self):
        for path in ['/server-settings', '/server-settings/operation', '/server-settings/health', '/server-updates', '/server-updates/check']:
            self.assertEqual(self.client.get(path).status_code, 401)
            with patch('server_advanced.app.get_classmate_by_token', return_value={'id': 'member', 'grade_class': '9A', 'display_name': 'Example'}):
                self.assertEqual(self.client.get(path, headers={'X-API-Token': 'member'}).status_code, 403)
        self.assertEqual(self.client.post('/server-settings', json={}).status_code, 401)

    def test_update_routes_forward_only_version_and_id(self):
        connection = MagicMock()
        connection.getresponse.return_value.status = 200
        connection.getresponse.return_value.read.return_value = b'{"operation":{"status":"queued"}}'
        with patch.object(server_settings, 'UnixConnection', return_value=connection):
            response = self.client.post('/server-updates', json={
                'version': '2.1.0', 'operationId': 'a' * 36,
                'url': 'https://attacker.example', 'registrationSecret': 'private',
            }, headers={'X-API-Token': 'test-admin-token'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers['Cache-Control'], 'no-store')
        sent = json.loads(connection.request.call_args.args[2])
        self.assertEqual(sent, {'version': '2.1.0', 'operationId': 'a' * 36})
        self.assertEqual(connection.request.call_args.args[1], '/updates')

    def test_old_update_manager_returns_setup_message(self):
        connection = MagicMock()
        connection.getresponse.return_value.status = 404
        with patch.object(server_settings, 'UnixConnection', return_value=connection):
            response = self.client.get('/server-updates', headers={'X-API-Token': 'test-admin-token'})
        self.assertEqual(response.status_code, 503)
        self.assertIn('SSH', response.json['error'])

    def test_secrets_are_not_logged_even_in_debug_mode(self):
        connection = MagicMock()
        response = connection.getresponse.return_value
        response.status = 200
        response.read.return_value = b'{"operation":{"status":"queued"}}'
        logs = io.StringIO()
        with patch.object(server_settings, 'UnixConnection', return_value=connection), patch('server_advanced.app.REQUEST_LOG_FULL_DEBUG', True), redirect_stdout(logs):
            result = self.client.post('/server-settings', json={
                'revision': 'abc', 'operationId': 'a' * 36,
                'changes': {'GEMINI_API_KEY': 'secret-do-not-log', 'ESCHOOL_PASSWORD': 'private-password'},
                'registrationSecret': 'also-private',
            }, headers={'X-API-Token': 'test-admin-token'})
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.headers['Cache-Control'], 'no-store')
        self.assertNotIn('secret-do-not-log', logs.getvalue())
        self.assertNotIn('private-password', logs.getvalue())
        sent = json.loads(connection.request.call_args.args[2])
        self.assertNotIn('registrationSecret', sent)
        self.assertEqual(sent['changes']['GEMINI_API_KEY'], 'secret-do-not-log')

    def test_missing_manager_has_actionable_error(self):
        with patch.object(server_settings, 'UnixConnection') as cls:
            cls.return_value.request.side_effect = OSError('internal secret')
            result = self.client.get('/server-settings', headers={'X-API-Token': 'test-admin-token'})
        self.assertEqual(result.status_code, 503)
        self.assertNotIn('internal secret', result.get_data(as_text=True))
        self.assertIn('Сервис настройки', result.json['error'])

    def test_invalid_json_and_oversized_requests_rejected(self):
        headers = {'X-API-Token': 'test-admin-token'}
        self.assertEqual(self.client.post('/server-settings', json=[], headers=headers).status_code, 400)
        self.assertEqual(self.client.post('/server-settings', data=b'x' * 65537, headers=headers).status_code, 413)

    def test_health_checks_database_without_exposing_details(self):
        conn = MagicMock()
        with patch('server_advanced.database.get_db_connection', return_value=conn):
            response = self.client.get('/server-settings/health', headers={'X-API-Token': 'test-admin-token'})
        self.assertEqual(response.json, {'ok': True})
        conn.close.assert_called_once()
        with patch('server_advanced.database.get_db_connection', return_value=None):
            self.assertEqual(self.client.get('/server-settings/health', headers={'X-API-Token': 'test-admin-token'}).status_code, 503)


if __name__ == '__main__':
    unittest.main()
