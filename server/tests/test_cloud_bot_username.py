"""проверяем имена ботов в общих и прежних настройках телеграма"""

import unittest
from unittest.mock import MagicMock, patch

import requests
from flask import Flask, g

from server_advanced.routes import cloud


class CloudBotUsernameTests(unittest.TestCase):
    def setUp(self):
        self.app = Flask(__name__)
        cloud._telegram_bot_username.cache_clear()
        self.addCleanup(cloud._telegram_bot_username.cache_clear)
        self.shared = self.enterContext(patch.object(cloud, 'server_bot', return_value=None))
        self.enterContext(patch.object(cloud, '_require_registration_owner', return_value=None))
        self.conn = MagicMock()
        self.conn.cursor.return_value.fetchone.return_value = dict(
            username='student', full_name='Ученик', grade_class='9А',
            check_interval_minutes=10, check_interval_max_minutes=None,
            telegram_enabled=True, telegram_user_id='123', telegram_bot_token='123:legacy',
            session_invalid=False, last_check_at=None,
        )
        self.enterContext(patch.object(cloud, 'get_db_connection', return_value=self.conn))
        self.get = self.enterContext(patch.object(cloud.requests, 'get'))
        self.get.return_value.json.return_value = {'ok': True, 'result': {'username': 'school_bot'}}

    def status(self, role='admin'):
        with self.app.test_request_context('/cloud/status', method='POST',
                                           json={'registrationId': 'registration'}):
            g.cloud_role = role
            g.cloud_registration_id = 'registration'
            return cloud.status().get_json()

    def test_legacy_bot_name_is_resolved_for_admin_and_user(self):
        for role in ('admin', 'user'):
            result = self.status(role)
            self.assertTrue(result['telegramBotConfigured'])
            self.assertEqual(result['telegramBotUsername'], 'school_bot')
            self.assertEqual(result['telegramUserId'], '123')
            self.assertNotIn('123:legacy', str(result))
        self.get.assert_called_once_with('https://api.telegram.org/bot123:legacy/getMe', timeout=5)

    def test_saved_shared_bot_name_takes_precedence(self):
        self.shared.return_value = {'token': '456:shared', 'username': 'shared_bot'}
        self.assertEqual(self.status()['telegramBotUsername'], 'shared_bot')
        self.get.assert_not_called()

    def test_shared_bot_with_missing_name_is_resolved(self):
        self.shared.return_value = {'token': '456:shared', 'username': None}
        self.assertEqual(self.status()['telegramBotUsername'], 'school_bot')
        self.get.assert_called_once_with('https://api.telegram.org/bot456:shared/getMe', timeout=5)

    def test_telegram_outage_preserves_status_and_is_cached(self):
        self.get.side_effect = requests.Timeout('unavailable')
        for _ in range(2):
            result = self.status()
            self.assertTrue(result['monitoring'])
            self.assertTrue(result['telegramBotConfigured'])
            self.assertEqual(result['telegramBotUsername'], '')
        self.get.assert_called_once()

    def test_cache_refreshes_name_and_is_separate_for_each_token(self):
        self.assertEqual(cloud._telegram_bot_username('123:legacy', 1), 'school_bot')
        self.get.return_value.json.return_value['result']['username'] = 'renamed_bot'
        self.assertEqual(cloud._telegram_bot_username('123:legacy', 1), 'school_bot')
        self.assertEqual(cloud._telegram_bot_username('123:legacy', 2), 'renamed_bot')
        self.assertEqual(cloud._telegram_bot_username('456:shared', 2), 'renamed_bot')
        self.assertEqual(self.get.call_count, 3)

    def test_classmate_does_not_trigger_telegram_lookup(self):
        result = self.status('classmate')
        self.assertFalse(any(key.startswith('telegram') for key in result))
        self.get.assert_not_called()


if __name__ == '__main__':
    unittest.main()
