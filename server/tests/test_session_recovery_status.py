"""Успех восстановления нельзя сообщать, если флаг остановки не сохранён."""

import unittest
from unittest.mock import MagicMock, Mock, patch

from flask import Flask

from server_advanced import keep_alive, telegram_bot
from server_advanced.routes import notifications


class SessionRecoveryStatusTests(unittest.TestCase):
    def setUp(self):
        self.app = Flask(__name__)
        self.read = MagicMock()
        self.read.cursor.return_value.fetchone.return_value = {
            'id': 'primary', 'username': 'student', 'password_encrypted': 'encrypted',
        }
        self.write = MagicMock()
        self.enterContext(patch.object(notifications, '_require_registration_owner', return_value=None))
        self.enterContext(patch.object(notifications, 'login_and_get_data',
            return_value=([], [], [], 'Student', {'JSESSIONID': 'restored'}, 123)))
        self.enterContext(patch.object(notifications, 'init_encryption'))
        self.enterContext(patch.object(notifications, 'decrypt_password', return_value='password'))
        self.enterContext(patch.object(notifications, 'encrypt_password', return_value='encrypted'))

    def test_api_does_not_report_success_when_database_write_fails(self):
        for handler in (notifications.retry_session, notifications.update_password):
            for connection in (None, self.write):
                with self.subTest(handler=handler.__name__, available=connection is not None):
                    self.write.commit.side_effect = RuntimeError('write failed')
                    with self.app.test_request_context(method='POST',
                            json={'registrationId': 'peer', 'password': 'password'}), \
                            patch.object(notifications, 'get_db_connection', side_effect=[self.read, connection]), \
                            patch.object(notifications, 'update_session') as update:
                        response, status = handler.__wrapped__()
                    self.assertGreaterEqual(status, 500)
                    self.assertNotIn('success', response.get_json())
                    update.assert_not_called()

    def test_telegram_retry_reports_success_only_after_database_commit(self):
        for outcome in ('unavailable', 'failed', 'saved'):
            with self.subTest(outcome=outcome):
                self.write.commit.side_effect = RuntimeError('write failed') if outcome == 'failed' else None
                with patch.object(telegram_bot, 'get_db_connection',
                        side_effect=[self.read, None if outcome == 'unavailable' else self.write]), \
                        patch.object(telegram_bot, 'init_encryption'), \
                        patch.object(telegram_bot, 'decrypt_password', return_value='password'), \
                        patch.object(telegram_bot, '_send_text') as send, \
                        patch.object(keep_alive, 'update_session') as update:
                    telegram_bot._perform_retry_session(Mock(), 123, 'primary')
                text = send.call_args.args[2]
                if outcome == 'saved':
                    self.assertIn('Подключение восстановлено', text)
                    update.assert_called_once_with('primary', {'JSESSIONID': 'restored'})
                else:
                    self.assertIn('Не удалось сохранить', text)
                    self.assertNotIn('Мониторинг возобновлён', text)
                    update.assert_not_called()
