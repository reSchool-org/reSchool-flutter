"""проверяем роли на отдельной postgres базе, внешние сервисы подменяем"""

import os
import hashlib
import hmac
from pathlib import Path
import sys
import tempfile
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock, patch


@unittest.skipUnless(os.getenv('RESCHOOL_TEST_DATABASE_URL'), 'нужна отдельная RESCHOOL_TEST_DATABASE_URL')
class CloudRolesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from cryptography.fernet import Fernet
        cls.runtime = tempfile.TemporaryDirectory(prefix='reschool_cloud_')
        os.environ.update(DATABASE_URL=os.environ['RESCHOOL_TEST_DATABASE_URL'],
                          CACHE_ENABLED='false', API_TOKEN='test-admin-key', MIN_CHECK_INTERVAL='10',
                          CF3_ENCRYPTION_KEY=Fernet.generate_key().decode(),
                          ENCRYPTION_KEY='', RESCHOOL_RUNTIME_DIR=cls.runtime.name,
                          ANALYSIS_ENABLED='false')
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        from server_advanced.app import app
        from server_advanced import database, encryption
        cls.app, cls.db, cls.encryption = app, database, encryption
        database.init_db()
        encryption.init_encryption()
        cls.app.config['TESTING'] = True

    @classmethod
    def tearDownClass(cls):
        cls.db.get_pool().close()
        cls.runtime.cleanup()

    def setUp(self):
        self.conn = self.db.get_db_connection()
        self.conn.execute('TRUNCATE custom_homework, cloud_invites, cf3_registrations, classmate_registrations, verified_users, cloud_server_bot CASCADE')
        self.conn.commit()
        self.client = self.app.test_client()
        self.admin = {'X-API-Token': 'test-admin-key'}
        self.login = self.enterContext(patch('server_advanced.routes.cloud.login_and_get_data',
            return_value=([{'id': 11, 'text': 'Задание'}], [], [], 'Ученик', {'session': 'test'}, 123)))
        self.enterContext(patch('server_advanced.routes.cloud.get_verified_name', return_value='Иван Иванов'))
        self.enterContext(patch('server_advanced.routes.cloud.update_session'))
        self.enterContext(patch('server_advanced.routes.cloud.restart_server_bot'))
        self.enterContext(patch('server_advanced.app.log'))
        self.enterContext(patch('server_advanced.routes.cloud.log'))

    def tearDown(self):
        self.conn.close()

    def invite(self, grade='9А'):
        result = self.client.post('/cloud/invites', headers=self.admin, json={'gradeClass': grade})
        self.assertEqual(result.status_code, 200, result.json)
        return result.json['inviteToken']

    def join(self, mode='user', invite=None):
        body = {'inviteToken': invite or self.invite(), 'mode': mode, 'fullName': 'Иван Иванов', 'requestId': uuid.uuid4().hex}
        if mode == 'user':
            body.update(username='student', password='school-password')
        result = self.client.post('/cloud/join', json=body)
        self.assertEqual(result.status_code, 200, result.json)
        return result.json

    def test_push_endpoints_and_token_storage_are_removed(self):
        self.admin_device(fcmToken='obsolete-device-token')
        self.assertEqual(self.conn.execute("""SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name IN ('cf3_registrations', 'classmate_registrations')
            AND column_name IN ('fcm_token', 'relay_device_token')""").fetchall(), [])
        for path in ('/update-fcm-token', '/classmate-update-fcm', '/test-notification'):
            result = self.client.post(path, headers=self.admin, json={'fcmToken': 'obsolete-device-token'})
            self.assertEqual(result.status_code, 404)

    def test_monitor_starts_without_any_push_provider(self):
        from server_advanced.routes import notifications
        with patch.object(notifications, '_monitor_thread', None), \
                patch.object(notifications, '_monitor_running', False), \
                patch.object(notifications.threading, 'Thread') as thread, \
                patch.object(notifications, 'restart_all_telegram_bots'), \
                patch('server_advanced.cloud_access.restart_server_bot'):
            notifications.start_notification_monitor()
            thread.return_value.start.assert_called_once()
            self.assertTrue(notifications._monitor_running)

    def test_three_roles_and_private_status(self):
        user = self.join()
        simple = self.join('classmate')
        self.assertEqual(self.login.call_count, 1)
        for registration, role in ((user, 'user'), (simple, 'classmate')):
            headers = {'X-API-Token': registration['apiToken']}
            status = self.client.post('/cloud/status', headers=headers, json={})
            self.assertEqual(status.status_code, 200, status.json)
            self.assertEqual(status.json['role'], role)
            self.assertEqual(status.json['monitoring'], role == 'user')
            self.assertNotIn('telegramBotToken', status.json)
            if role == 'classmate':
                self.assertFalse(any(key.startswith('telegram') for key in status.json))
        admin = self.client.post('/cloud/status', headers=self.admin, json={})
        self.assertEqual(admin.json['role'], 'admin')
        self.assertFalse(admin.json['monitoring'])
        row = self.conn.execute('SELECT password_encrypted, registration_secret_hash, cloud_role FROM cf3_registrations').fetchone()
        self.assertEqual(self.encryption.decrypt_password(row[0]), 'school-password')
        self.assertNotIn('school-password', row[0])
        self.assertNotEqual(row[1], user['registrationSecret'])
        self.assertEqual(row[2], 'user')

    def session_request(self, user, **overrides):
        return self.client.post('/cloud/session', headers={'X-API-Token': user['apiToken']}, json={
            'registrationId': user['registrationId'], 'registrationSecret': user['registrationSecret'],
            'username': 'student', 'prsId': 123, **overrides})

    def admin_device(self, username='student', **settings):
        response = self.client.post('/cloud/account', headers=self.admin, json={
            'username': username, 'password': 'school-password', 'gradeClass': '9А',
            'requestId': uuid.uuid4().hex, **settings})
        self.assertEqual(response.status_code, 200, response.json)
        return response.json

    def admin_request(self, path, device, **settings):
        return self.client.post(path, headers=self.admin, json={
            'registrationId': device['registrationId'],
            'registrationSecret': device['registrationSecret'], **settings})

    def attach_body(self, username='student', password='school-password', request_id=None):
        request_id = request_id or uuid.uuid4().hex
        return {'username': username, 'requestId': request_id, 'deviceName': 'Phone',
            'accountCredentialProof': hmac.new(password.encode(),
                f'reschool:attach:{request_id}:{username}'.encode(), hashlib.sha256).hexdigest()}

    def test_phone_attaches_existing_account_without_login_or_resetting_pc(self):
        first = self.admin_device()
        self.admin_request('/update-interval', first, checkIntervalMinutes=17, checkIntervalMaxMinutes=29)
        self.conn.execute('INSERT INTO cf3_sessions (registration_id, cookies) VALUES (%s, %s)',
                          (first['registrationId'], '{"JSESSIONID": "existing-session"}'))
        self.conn.commit()
        self.login.reset_mock()
        body = self.attach_body()
        response = self.client.post('/cloud/account/attach', headers=self.admin, json=body)
        self.assertEqual(response.status_code, 200, response.json)
        phone = response.json
        self.assertNotEqual(phone['registrationId'], first['registrationId'])
        self.assertNotEqual(phone['registrationSecret'], first['registrationSecret'])
        self.assertEqual(phone['checkIntervalMaxMinutes'], 29)
        self.assertTrue(self.admin_request('/cloud/status', phone).json['monitoring'])
        self.assertTrue(self.admin_request('/cloud/status', first).json['monitoring'])
        self.assertEqual(self.conn.execute('SELECT cookies FROM cf3_sessions WHERE registration_id = %s',
            (phone['registrationId'],)).fetchone()[0], '{"JSESSIONID": "existing-session"}')
        self.assertEqual(self.client.post('/cloud/account/attach', headers=self.admin, json=body).json, phone)
        self.assertEqual(self.conn.execute('SELECT count(*) FROM cf3_registrations').fetchone()[0], 2)
        self.login.assert_not_called()

    def test_attach_requires_proof_and_admin_and_never_enables_an_unknown_account(self):
        first = self.admin_device()
        user = self.join()
        self.login.reset_mock()
        before = self.conn.execute('SELECT count(*) FROM cf3_registrations').fetchone()[0]
        body = self.attach_body()
        for headers in ({}, {'X-API-Token': user['apiToken']}):
            self.assertIn(self.client.post('/cloud/account/attach', headers=headers, json=body).status_code, (401, 403))
        self.assertEqual(self.client.post('/cloud/account/attach', headers=self.admin,
            json={**body, 'accountCredentialProof': ''}).status_code, 400)
        self.assertEqual(self.client.post('/cloud/account/attach', headers=self.admin,
            json=self.attach_body(password='wrong')).status_code, 409)
        self.assertEqual(self.client.post('/cloud/account/attach', headers=self.admin,
            json=self.attach_body(username='unknown')).json, {'monitoring': False})
        self.assertEqual(self.conn.execute('SELECT count(*) FROM cf3_registrations').fetchone()[0], before)
        self.login.assert_not_called()

    def test_attach_request_replay_is_bound_to_account_and_proof(self):
        self.admin_device()
        body = self.attach_body()
        first = self.client.post('/cloud/account/attach', headers=self.admin, json=body)
        self.assertEqual(first.status_code, 200)
        rejected = self.client.post('/cloud/account/attach', headers=self.admin, json={
            **body, 'accountCredentialProof': '0' * 64})
        self.assertEqual(rejected.status_code, 409)
        self.assertNotIn('registrationSecret', rejected.json)
        from server_advanced.logging_utils import redact_data
        self.assertEqual(redact_data(body)['accountCredentialProof'], '[REDACTED]')

    def test_simultaneous_phone_restore_issues_one_device(self):
        self.admin_device()
        body = self.attach_body()
        def attach(_):
            with self.app.test_client() as client:
                return client.post('/cloud/account/attach', headers=self.admin, json=body).json
        with ThreadPoolExecutor(max_workers=2) as pool:
            responses = list(pool.map(attach, range(2)))
        self.assertEqual(responses[0], responses[1])
        self.assertIn('registrationId', responses[0])
        self.assertEqual(self.conn.execute('SELECT count(*) FROM cf3_registrations').fetchone()[0], 2)

    def test_admin_devices_inherit_and_update_account_settings_both_ways(self):
        first = self.admin_device()
        response = self.admin_request('/update-interval', first,
                                      checkIntervalMinutes=17, checkIntervalMaxMinutes=29)
        self.assertEqual(response.status_code, 200, response.json)
        second = self.admin_device(checkIntervalMinutes=10)
        self.assertEqual(second['checkIntervalMinutes'], 17)
        self.assertEqual(second['checkIntervalMaxMinutes'], 29)
        self.assertNotEqual(first['registrationId'], second['registrationId'])
        self.assertNotEqual(first['registrationSecret'], second['registrationSecret'])
        for device, lower, upper in ((second, 31, 42), (first, 20, None)):
            result = self.admin_request('/update-interval', device,
                                        checkIntervalMinutes=lower, checkIntervalMaxMinutes=upper)
            self.assertEqual(result.status_code, 200, result.json)
            for peer in (first, second):
                status = self.admin_request('/cloud/status', peer).json
                self.assertEqual((status['checkIntervalMinutes'], status['checkIntervalMaxMinutes']),
                                 (lower, upper))
        rows = self.conn.execute('SELECT next_check_at FROM cf3_registrations').fetchall()
        self.assertTrue(all(row[0] for row in rows))

    def test_shared_settings_include_legacy_bot_group_topics_and_chat_map(self):
        first = self.admin_device()
        self.conn.execute('''UPDATE cf3_registrations SET telegram_enabled = TRUE,
            telegram_bot_token = '123:TEST', telegram_user_id = '55',
            telegram_group_enabled = TRUE, telegram_group_chat_id = '-123',
            telegram_topic_map = '{"math": 7}', chat_forward_map = '{"42": 9}'
            WHERE id = %s''', (first['registrationId'],))
        self.conn.commit()
        second = self.admin_device()
        for device in (first, second):
            status = self.admin_request('/cloud/status', device).json
            self.assertTrue(status['telegramEnabled'])
            self.assertTrue(status['telegramBotConfigured'])
            self.assertEqual(status['telegramUserId'], '55')
            self.assertNotIn('telegramBotToken', status)
            self.assertEqual(self.admin_request('/get-chat-forward', device).json['chatForwardMap'], {'42': 9})
        result = self.admin_request('/update-telegram-group', second,
            telegramGroupEnabled=True, telegramGroupChatId='-456',
            telegramGroupTitle='Class', telegramTopicMap={'math': 12})
        self.assertEqual(result.status_code, 200, result.json)
        self.assertEqual(self.admin_request('/get-telegram-status', first).json['telegramGroupChatId'], '-456')
        with patch('server_advanced.routes.cloud.start_telegram_bot') as start, \
                patch('server_advanced.routes.cloud.stop_telegram_bot'):
            result = self.admin_request('/cloud/telegram', second, telegramEnabled=True, telegramUserId='66')
            self.assertEqual(result.status_code, 200, result.json)
            self.assertEqual(start.call_args.args[0], first['registrationId'])
        self.assertEqual(self.admin_request('/cloud/status', first).json['telegramUserId'], '66')

    def test_monitoring_status_matches_telegram_across_devices(self):
        first, second = self.admin_device(), self.admin_device()
        other, user = self.admin_device(username='other-student'), self.join()
        for primary_invalid in (False, True):
            self.conn.execute('''UPDATE cf3_registrations SET session_invalid = %s,
                last_check_at = '2026-09-13 12:00:00' WHERE id = %s''',
                (primary_invalid, first['registrationId']))
            self.conn.execute('''UPDATE cf3_registrations SET session_invalid = %s,
                last_check_at = '2026-09-12 12:00:00' WHERE id = %s''',
                (not primary_invalid, second['registrationId']))
            self.conn.commit()
            for device in (first, second):
                status = self.admin_request('/cloud/status', device).json
                self.assertEqual(status['sessionInvalid'], primary_invalid)
                self.assertEqual(status['lastCheckAt'], '2026-09-13 12:00:00')
                legacy = self.admin_request('/get-account-status', device).json
                self.assertEqual(legacy['sessionInvalid'], primary_invalid)
            self.assertFalse(self.admin_request('/cloud/status', other).json['sessionInvalid'])
            self.assertFalse(self.client.post('/cloud/status',
                headers={'X-API-Token': user['apiToken']}, json={}).json['sessionInvalid'])

    def test_recovery_from_peer_restores_the_registration_used_by_telegram(self):
        first, second = self.admin_device(), self.admin_device()
        other, user = self.admin_device(username='other-student'), self.join()
        from server_advanced.routes import notifications
        for path, body in (('/retry-session', {}), ('/update-password', {'password': 'new-password'})):
            self.conn.execute('UPDATE cf3_registrations SET session_invalid = TRUE')
            self.conn.commit()
            with patch.object(notifications, 'login_and_get_data', return_value=([], [], [], 'Student', {'JSESSIONID': 'restored'}, 123)), \
                    patch.object(notifications, 'update_session') as update:
                response = self.admin_request(path, second, **body)
                self.assertEqual(response.status_code, 200, response.json)
                update.assert_called_once_with(first['registrationId'], {'JSESSIONID': 'restored'})
            self.assertFalse(self.admin_request('/cloud/status', second).json['sessionInvalid'])
            for device in (second, other, user):
                self.assertTrue(self.conn.execute('SELECT session_invalid FROM cf3_registrations WHERE id = %s',
                    (device['registrationId'],)).fetchone()[0])
        encrypted = self.conn.execute('SELECT password_encrypted FROM cf3_registrations WHERE id = %s',
            (first['registrationId'],)).fetchone()[0]
        self.assertEqual(self.encryption.decrypt_password(encrypted), 'new-password')

    def test_monitoring_recovery_still_requires_the_calling_device_secret(self):
        first, second = self.admin_device(), self.admin_device()
        invalid = {**second, 'registrationSecret': first['registrationSecret']}
        from server_advanced.routes import notifications
        with patch.object(notifications, 'login_and_get_data') as login:
            for path in ('/cloud/status', '/get-account-status', '/retry-session', '/update-password'):
                self.assertEqual(self.admin_request(path, invalid, password='new-password').status_code, 403)
            login.assert_not_called()

    def test_account_sync_does_not_cross_roles_accounts_or_device_credentials(self):
        first, second = self.admin_device(), self.admin_device()
        other = self.admin_device(username='other-student')
        user = self.join()
        self.conn.execute("UPDATE cf3_registrations SET password_encrypted = 'first-secret' WHERE id = %s",
                          (first['registrationId'],))
        self.conn.commit()
        self.assertEqual(self.admin_request('/update-interval', second, checkIntervalMinutes=37).status_code, 200)
        row = self.conn.execute('SELECT password_encrypted FROM cf3_registrations WHERE id = %s',
                                (second['registrationId'],)).fetchone()
        self.assertNotEqual(row[0], 'first-secret')
        for device in (other, user):
            self.assertEqual(self.conn.execute('SELECT check_interval_minutes FROM cf3_registrations WHERE id = %s',
                                              (device['registrationId'],)).fetchone()[0], 10)
        invalid = {**second, 'registrationSecret': first['registrationSecret']}
        self.assertEqual(self.admin_request('/update-interval', invalid, checkIntervalMinutes=50).status_code, 403)

    def test_concurrent_device_settings_updates_preserve_both_changes(self):
        first, second = self.admin_device(), self.admin_device()
        def save(index):
            with self.app.test_client() as client:
                device = (first, second)[index]
                path, values = (('/update-interval', {'checkIntervalMinutes': 47}),
                    ('/update-chat-forward', {'chatForwardMap': {'42': 8}}))[index]
                return client.post(path, headers=self.admin, json={
                    'registrationId': device['registrationId'],
                    'registrationSecret': device['registrationSecret'], **values}).status_code
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertEqual(list(pool.map(save, range(2))), [200, 200])
        rows = self.conn.execute('SELECT check_interval_minutes, chat_forward_map FROM cf3_registrations').fetchall()
        self.assertEqual(rows[0], rows[1])
        self.assertEqual(rows[0][0], 47)
        self.assertIn('42', rows[0][1])

    def test_shared_telegram_has_one_delivery_owner_and_survives_owner_removal(self):
        from server_advanced.notification_delivery import get_telegram_info, send_notification_with_telegram
        from server_advanced.routes.notifications import _chat_delivery
        first, second = self.admin_device(), self.admin_device()
        self.conn.execute("UPDATE cf3_registrations SET telegram_enabled = TRUE, telegram_bot_token = '123:TEST', telegram_user_id = '55' WHERE id = %s",
                          (first['registrationId'],))
        self.conn.commit()
        self.assertTrue(get_telegram_info(first['registrationId'])['telegram_delivery_primary'])
        info = get_telegram_info(second['registrationId'])
        self.assertTrue(info['telegram_enabled'])
        self.assertFalse(info['telegram_delivery_primary'])
        with patch('server_advanced.notification_delivery.save_notification_history', return_value=True) as push, \
                patch('server_advanced.telegram_bot.send_telegram_message') as send:
            send_notification_with_telegram('Title', 'Body', registration_id=second['registrationId'])
            push.assert_called_once()
            send.assert_not_called()
        with patch('server_advanced.routes.notifications.save_notification_history', return_value=True) as push, \
                patch('server_advanced.routes.notifications.send_telegram_message') as send:
            deliver = _chat_delivery({'id': second['registrationId']}, info)
            deliver({'title': 'Title', 'body': 'Body', 'data': {}, 'thread_id': 42}, set())
            push.assert_called_once()
            send.assert_not_called()
        self.conn.execute('DELETE FROM cf3_registrations WHERE id = %s', (first['registrationId'],))
        self.conn.commit()
        self.assertTrue(get_telegram_info(second['registrationId'])['telegram_delivery_primary'])

    def test_group_commands_from_second_device_reach_account_bot(self):
        from server_advanced import telegram_bot
        from server_advanced.routes.homework import _notify_group_about_custom_homework
        first, second = self.admin_device(), self.admin_device()
        code = telegram_bot.create_group_activation_code(second['registrationId'])
        self.assertTrue(telegram_bot._consume_group_activation_code(first['registrationId'], code)[0])
        telegram_bot.request_topic_detect(second['registrationId'])
        telegram_bot._pending_topic_detects[first['registrationId']]['topic_id'] = 12
        self.assertEqual(telegram_bot.get_and_clear_detected_topic(second['registrationId']), 12)
        self.conn.execute('''UPDATE cf3_registrations SET telegram_enabled = TRUE,
            telegram_bot_token = '123:TEST', telegram_user_id = '55', telegram_group_enabled = TRUE,
            telegram_group_chat_id = '-123' WHERE id = %s''', (first['registrationId'],))
        self.conn.commit()
        with patch('server_advanced.telegram_bot.send_telegram_message', return_value=True) as send:
            _notify_group_about_custom_homework('9А', 'Math', '2026-09-11', 'Task', 'Student', [], '')
            send.assert_called_once()

    @staticmethod
    def school_state(status=200, prs_id=123):
        response = Mock(status_code=status, cookies={})
        response.json.return_value = {'userId': 7, 'user': {'prsId': prs_id}}
        return response

    def test_existing_session_is_shared_only_after_validation_without_login(self):
        user = self.join()
        self.login.reset_mock()
        with patch('server_advanced.routes.cloud.get_session', return_value={'JSESSIONID': 'existing-session'}), \
                patch('server_advanced.routes.cloud.requests.get', return_value=self.school_state()) as get, \
                patch('server_advanced.routes.cloud.load_user_session') as load:
            response = self.session_request(user)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, dict(available=True, username='student', prsId=123,
                                            sessionCookie='existing-session'))
        self.assertEqual(response.headers['Cache-Control'], 'no-store, private')
        self.assertEqual(response.headers['Pragma'], 'no-cache')
        self.assertTrue(get.call_args.args[0].endswith('/state'))
        self.assertEqual(get.call_args.kwargs['cookies'], {'JSESSIONID': 'existing-session'})
        self.assertFalse(get.call_args.kwargs['allow_redirects'])
        get.assert_called_once()
        load.assert_not_called()
        self.login.assert_not_called()

    def test_session_survives_restart_and_accepts_cookie_rotation(self):
        user = self.join()
        self.db.save_user_session(user['registrationId'], {'JSESSIONID': 'persisted-session'})
        state = self.school_state()
        state.cookies = {'JSESSIONID': 'rotated-session'}
        self.login.reset_mock()
        with patch('server_advanced.routes.cloud.get_session', return_value=None), \
                patch('server_advanced.routes.cloud.requests.get', return_value=state) as get, \
                patch('server_advanced.routes.cloud.update_session') as update:
            response = self.session_request(user)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['sessionCookie'], 'rotated-session')
        self.assertEqual(get.call_args.kwargs['cookies'], {'JSESSIONID': 'persisted-session'})
        update.assert_called_once_with(user['registrationId'], {'JSESSIONID': 'rotated-session'})
        self.login.assert_not_called()

    def test_session_endpoint_requires_api_key_owner_secret_and_same_account(self):
        user, other, classmate = self.join(), self.join(), self.join('classmate')
        body = dict(registrationId=user['registrationId'], registrationSecret=user['registrationSecret'],
                    username='student', prsId=123)
        with patch('server_advanced.routes.cloud.requests.get') as get:
            self.assertEqual(self.client.post('/cloud/session', json=body).status_code, 401)
            self.assertEqual(self.session_request(user, registrationSecret='wrong').status_code, 403)
            self.assertEqual(self.session_request(user, registrationSecret=None).status_code, 401)
            self.assertEqual(self.session_request(user, registrationSecret=['wrong']).status_code, 400)
            self.assertEqual(self.session_request(user, registrationId=other['registrationId'],
                             registrationSecret=other['registrationSecret']).status_code, 403)
            self.assertEqual(self.session_request(user, username='different-student').status_code, 409)
            self.assertEqual(self.session_request(classmate, **body).status_code, 403)
            admin_body = {**body, 'registrationSecret': None}
            self.assertEqual(self.client.post('/cloud/session', headers=self.admin, json=admin_body).status_code, 401)
            get.assert_not_called()

    def test_session_from_different_person_is_not_exposed(self):
        user = self.join()
        with patch('server_advanced.routes.cloud.get_session', return_value={'JSESSIONID': 'foreign-session'}), \
                patch('server_advanced.routes.cloud.requests.get', return_value=self.school_state(prs_id=999)):
            response = self.session_request(user)
        self.assertEqual(response.status_code, 409)
        self.assertNotIn('sessionCookie', response.json)

    def test_missing_or_invalid_sessions_never_trigger_password_login(self):
        user = self.join()
        self.login.reset_mock()
        for cookies in (None, {}, {'JSESSIONID': 'bad; cookie'}, {'JSESSIONID': 'bad\r\nHeader: value'}):
            with self.subTest(cookies=cookies), \
                    patch('server_advanced.routes.cloud.get_session', return_value=cookies), \
                    patch('server_advanced.routes.cloud.load_user_session', return_value=None), \
                    patch('server_advanced.routes.cloud.requests.get') as get:
                response = self.session_request(user)
                self.assertEqual(response.json, {'available': False})
                get.assert_not_called()
        self.conn.execute('UPDATE cf3_registrations SET session_invalid = TRUE WHERE id = %s', (user['registrationId'],))
        self.conn.commit()
        with patch('server_advanced.routes.cloud.get_session') as get:
            self.assertEqual(self.session_request(user).json, {'available': False})
            get.assert_not_called()
        self.login.assert_not_called()

    def test_expired_or_unreachable_upstream_does_not_return_cookie_or_login(self):
        import requests
        user = self.join()
        self.login.reset_mock()
        for status in (401, 403, 302, 500):
            with self.subTest(status=status), \
                    patch('server_advanced.routes.cloud.get_session', return_value={'JSESSIONID': 'old-session'}), \
                    patch('server_advanced.routes.cloud.requests.get', return_value=self.school_state(status)):
                response = self.session_request(user)
                self.assertEqual(response.status_code, 200 if status in (401, 403) else 503)
                self.assertNotIn('sessionCookie', response.json)
        with patch('server_advanced.routes.cloud.get_session', return_value={'JSESSIONID': 'old-session'}), \
                patch('server_advanced.routes.cloud.requests.get', side_effect=requests.Timeout()):
            self.assertEqual(self.session_request(user).status_code, 503)
        self.login.assert_not_called()

    def test_invalid_state_is_not_treated_as_an_authenticated_session(self):
        user = self.join()
        for payload in (None, [], {}, {'userId': 7}, {'userId': None, 'user': {'prsId': 123}},
                        {'userId': 7, 'user': {'prsId': '123'}}):
            state = self.school_state()
            state.json.return_value = payload
            with self.subTest(payload=payload), \
                    patch('server_advanced.routes.cloud.get_session', return_value={'JSESSIONID': 'session'}), \
                    patch('server_advanced.routes.cloud.requests.get', return_value=state):
                response = self.session_request(user)
                self.assertEqual(response.json, {'available': False})

    def test_session_cookie_is_redacted_even_in_full_debug_logs(self):
        user = self.join()
        with patch('server_advanced.routes.cloud.get_session', return_value={'JSESSIONID': 'never-log-this-session'}), \
                patch('server_advanced.routes.cloud.requests.get', return_value=self.school_state()), \
                patch('server_advanced.app.REQUEST_LOG_FULL_DEBUG', True), \
                patch('server_advanced.app.log') as log:
            response = self.session_request(user)
        self.assertTrue(response.json['available'])
        logs = '\n'.join(str(call) for call in log.call_args_list)
        for secret in ('never-log-this-session', user['registrationSecret'], user['apiToken']):
            self.assertNotIn(secret, logs)
        self.assertIn('[REDACTED]', logs)

    def test_admin_account_can_enable_monitoring_and_retry_safely(self):
        body = dict(username='student', password='school-password', gradeClass='9А', requestId=uuid.uuid4().hex)
        first = self.client.post('/cloud/account', headers=self.admin, json=body)
        self.assertEqual(first.status_code, 200, first.json)
        self.assertEqual(first.json['role'], 'admin')
        self.assertIsNone(first.json['classmateId'])
        self.assertTrue(first.json['verificationToken'])
        second = self.client.post('/cloud/account', headers=self.admin, json=body)
        self.assertEqual(first.json, second.json)
        status = self.client.post('/cloud/status', headers=self.admin, json={
            'registrationId': first.json['registrationId'], 'registrationSecret': first.json['registrationSecret']})
        self.assertTrue(status.json['monitoring'])

    def test_member_cannot_call_admin_or_foreign_owner_routes(self):
        user, other = self.join(), self.join()
        headers = {'X-API-Token': user['apiToken']}
        for path in ('/server-domain', '/ip-blacklist', '/cloud/server-bot', '/cloud/account',
                     '/cloud/invites', '/update-telegram', '/update-telegram-group', '/generate-group-code',
                     '/textbook/upload', '/register', '/classmate-leave'):
            result = self.client.post(path, headers=headers, json={})
            self.assertEqual(result.status_code, 403, path)
        result = self.client.post('/update-interval', headers=headers, json={
            'registrationId': other['registrationId'], 'registrationSecret': other['registrationSecret'],
            'checkIntervalMinutes': 30})
        self.assertEqual(result.status_code, 403)
        result = self.client.post('/update-interval', headers=headers, json={
            'registrationId': user['registrationId'], 'registrationSecret': user['registrationSecret'],
            'checkIntervalMinutes': 30})
        self.assertEqual(result.status_code, 200, result.json)

    def test_admin_class_is_resolved_after_login_when_client_did_not_send_it(self):
        body = dict(username='student', password='school-password', gradeClass=None, requestId=uuid.uuid4().hex)
        with patch('server_advanced.routes.cloud.resolve_account_class', return_value='10А класс') as resolve:
            result = self.client.post('/cloud/account', headers=self.admin, json=body)
        self.assertEqual(result.status_code, 200, result.json)
        self.assertEqual(result.json['gradeClass'], '10А класс')
        resolve.assert_called_once_with({'session': 'test'}, 123)
        self.assertEqual(self.conn.execute('SELECT grade_class FROM cf3_registrations').fetchone()[0], '10А класс')

    def test_custom_and_random_intervals_round_trip(self):
        user = self.join()
        headers = {'X-API-Token': user['apiToken']}
        owner = dict(registrationId=user['registrationId'], registrationSecret=user['registrationSecret'])
        for lower, upper in ((17, None), (10, 20), (1440, None)):
            result = self.client.post('/update-interval', headers=headers, json={
                **owner, 'checkIntervalMinutes': lower, 'checkIntervalMaxMinutes': upper})
            self.assertEqual(result.status_code, 200, result.json)
            status = self.client.post('/cloud/status', headers=headers, json={}).json
            self.assertTrue(status['randomCheckIntervalSupported'])
            self.assertEqual(status['checkIntervalMinutes'], lower)
            self.assertEqual(status['checkIntervalMaxMinutes'], upper)
            delay = self.conn.execute('''SELECT EXTRACT(EPOCH FROM (next_check_at - clock_timestamp()))
                FROM cf3_registrations WHERE id = %s''', (user['registrationId'],)).fetchone()[0]
            self.assertGreaterEqual(delay, lower * 60 - 2)
            self.assertLessEqual(delay, (upper or lower) * 60)
        # старый клиент без верхней границы тоже может вернуть фиксированный режим
        result = self.client.post('/update-interval', headers=headers, json={**owner, 'checkIntervalMinutes': 25})
        self.assertEqual(result.status_code, 200)
        self.assertIsNone(result.json['checkIntervalMaxMinutes'])

    def test_invalid_intervals_leave_schedule_unchanged(self):
        user = self.join()
        headers = {'X-API-Token': user['apiToken']}
        owner = dict(registrationId=user['registrationId'], registrationSecret=user['registrationSecret'])
        query = 'SELECT check_interval_minutes, check_interval_max_minutes, next_check_at FROM cf3_registrations WHERE id = %s'
        before = self.conn.execute(query, (user['registrationId'],)).fetchone()
        for lower, upper in ((None, None), (True, None), ('17', None), (17.5, None),
                             (9, None), (1441, None), (20, 10), (10, 10),
                             (10, True), (10, '20'), (10, 20.5), (10, 1441)):
            result = self.client.post('/update-interval', headers=headers, json={
                **owner, 'checkIntervalMinutes': lower, 'checkIntervalMaxMinutes': upper})
            self.assertEqual(result.status_code, 400, result.json)
            self.assertEqual(self.conn.execute(query, (user['registrationId'],)).fetchone(), before)

    def test_monitor_keeps_deadline_and_reschedules_after_each_attempt(self):
        from server_advanced.routes.notifications import check_user_for_updates
        user = self.join()
        registration_id = user['registrationId']
        self.conn.execute('''UPDATE cf3_registrations SET check_interval_minutes = 10,
            check_interval_max_minutes = 20, next_check_at = clock_timestamp() + INTERVAL '15 minutes'
            WHERE id = %s''', (registration_id,))
        self.conn.commit()
        query = 'SELECT next_check_at FROM cf3_registrations WHERE id = %s'
        before = self.conn.execute(query, (registration_id,)).fetchone()[0]
        with patch('server_advanced.routes.notifications._check_user_for_updates') as check:
            check_user_for_updates({'id': registration_id})
            check.assert_not_called()
        self.assertEqual(self.conn.execute(query, (registration_id,)).fetchone()[0], before)

        # каждая завершённая попытка, в том числе неудачная, получает новый срок
        for failure in (None, RuntimeError('temporary upstream failure')):
            self.conn.execute("UPDATE cf3_registrations SET next_check_at = clock_timestamp() - INTERVAL '1 minute' WHERE id = %s", (registration_id,))
            self.conn.commit()
            with patch('server_advanced.routes.notifications._check_user_for_updates', side_effect=failure) as check:
                check_user_for_updates({'id': registration_id})
                check.assert_called_once()
            delay = self.conn.execute('''SELECT EXTRACT(EPOCH FROM (next_check_at - clock_timestamp()))
                FROM cf3_registrations WHERE id = %s''', (registration_id,)).fetchone()[0]
            self.assertGreaterEqual(delay, 598)
            self.assertLessEqual(delay, 1200)

    def test_monitor_uses_interval_changed_during_check(self):
        from server_advanced.routes.notifications import check_user_for_updates
        user = self.join()
        registration_id = user['registrationId']

        def change_interval(_):
            result = self.client.post('/update-interval', headers={'X-API-Token': user['apiToken']}, json={
                'registrationId': registration_id, 'registrationSecret': user['registrationSecret'],
                'checkIntervalMinutes': 40, 'checkIntervalMaxMinutes': 50})
            self.assertEqual(result.status_code, 200, result.json)

        with patch('server_advanced.routes.notifications._check_user_for_updates', side_effect=change_interval):
            check_user_for_updates({'id': registration_id})
        delay = self.conn.execute('''SELECT EXTRACT(EPOCH FROM (next_check_at - clock_timestamp()))
            FROM cf3_registrations WHERE id = %s''', (registration_id,)).fetchone()[0]
        self.assertGreaterEqual(delay, 2398)
        self.assertLessEqual(delay, 3000)

    def test_unresolved_admin_class_does_not_store_partial_registration(self):
        body = dict(username='student', password='school-password', requestId=uuid.uuid4().hex)
        with patch('server_advanced.routes.cloud.resolve_account_class', return_value=None):
            result = self.client.post('/cloud/account', headers=self.admin, json=body)
        self.assertEqual(result.status_code, 400)
        self.assertEqual(self.conn.execute('SELECT count(*) FROM cf3_registrations').fetchone()[0], 0)
        self.assertEqual(self.conn.execute('SELECT count(*) FROM verified_users').fetchone()[0], 0)

    def test_passwordless_mode_rejects_credentials_and_telegram(self):
        invite = self.invite()
        response = self.client.post('/cloud/join', json={
            'mode': 'admin', 'inviteToken': invite, 'username': 'student',
            'password': 'school-password', 'requestId': uuid.uuid4().hex})
        self.assertEqual(response.status_code, 400)
        for key in ('username', 'password', 'telegramUserId', 'telegramBotToken'):
            result = self.client.post('/cloud/join', json={'mode': 'classmate', 'inviteToken': invite, key: '123'})
            self.assertEqual(result.status_code, 400)
        simple = self.join('classmate', invite)
        self.login.assert_not_called()
        self.assertIsNone(simple['registrationId'])
        self.assertEqual(self.conn.execute('SELECT count(*) FROM cf3_registrations').fetchone()[0], 0)
        result = self.client.post('/cloud/telegram', headers={'X-API-Token': simple['apiToken']}, json={})
        self.assertEqual(result.status_code, 403)

    def test_invite_is_one_use_even_with_concurrent_joins(self):
        invite = self.invite()
        def join_once(_):
            with self.app.test_client() as client:
                return client.post('/cloud/join', json={'mode': 'classmate', 'inviteToken': invite, 'requestId': uuid.uuid4().hex}).status_code
        with ThreadPoolExecutor(max_workers=2) as pool:
            codes = list(pool.map(join_once, range(2)))
        self.assertEqual(codes.count(200), 1, codes)
        self.assertTrue(any(code in (401, 409) for code in codes))
        self.assertEqual(self.conn.execute('SELECT count(*) FROM classmate_registrations').fetchone()[0], 1)

    def test_retry_returns_same_connection_after_invite_consumption(self):
        body = dict(mode='user', inviteToken=self.invite(), username='student',
                    password='school-password', requestId=uuid.uuid4().hex)
        first = self.client.post('/cloud/join', json=body)
        second = self.client.post('/cloud/join', json=body)
        self.assertEqual(first.status_code, 200, first.json)
        self.assertEqual(second.json, first.json)
        self.assertEqual(self.login.call_count, 1)
        self.assertEqual(self.conn.execute('SELECT count(*) FROM cf3_registrations').fetchone()[0], 1)

    def test_failed_login_does_not_consume_invite(self):
        invite = self.invite()
        self.login.return_value = (None, None, None, None, None, None)
        result = self.client.post('/cloud/join', json={
            'mode': 'user', 'inviteToken': invite, 'username': 'student', 'password': 'wrong', 'requestId': uuid.uuid4().hex})
        self.assertEqual(result.status_code, 401)
        self.join('classmate', invite)

    def test_leave_deletes_password_and_revokes_member(self):
        user = self.join()
        headers = {'X-API-Token': user['apiToken']}
        response = self.client.post('/cloud/leave', headers=headers, json={
            'registrationId': user['registrationId'], 'registrationSecret': user['registrationSecret']})
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(self.conn.execute('SELECT count(*) FROM cf3_registrations').fetchone()[0], 0)
        self.assertEqual(self.conn.execute('SELECT count(*) FROM classmate_registrations').fetchone()[0], 0)
        self.assertEqual(self.client.post('/cloud/status', headers=headers, json={}).status_code, 401)

    def test_shared_bot_delivers_to_members_without_exposing_token(self):
        from server_advanced.notification_delivery import get_telegram_info
        secret = '123456:bot_secret'
        self.conn.execute('INSERT INTO cloud_server_bot (id, token_encrypted, username) VALUES (1, %s, %s)',
                          (self.encryption.encrypt_password(secret), 'school_bot'))
        self.conn.commit()
        users = [self.join(), self.join()]
        for number, user in enumerate(users, 1):
            headers = {'X-API-Token': user['apiToken']}
            body = {'registrationId': user['registrationId'], 'registrationSecret': user['registrationSecret'],
                    'telegramUserId': str(number), 'telegramEnabled': True}
            result = self.client.post('/cloud/telegram', headers=headers, json=body)
            self.assertEqual(result.status_code, 200, result.json)
            info = get_telegram_info(user['registrationId'])
            self.assertEqual(info['telegram_bot_token'], secret)
            self.assertEqual(info['telegram_user_id'], str(number))
            self.assertFalse(info['telegram_group_enabled'])
            status = self.client.post('/cloud/status', headers=headers, json={})
            self.assertNotIn(secret, status.get_data(as_text=True))
            with patch('server_advanced.routes.cloud.send_telegram_message', return_value=True) as send:
                result = self.client.post('/cloud/telegram/test', headers=headers, json=body)
                self.assertEqual(result.status_code, 200)
                self.assertEqual(send.call_args.args[:2], (secret, str(number)))
            result = self.client.post('/cloud/telegram', headers=headers, json={**body, 'telegramBotToken': secret})
            self.assertEqual(result.status_code, 400)
            result = self.client.post('/cloud/telegram', headers=headers, json={**body, 'telegramUserId': '-100123'})
            self.assertEqual(result.status_code, 400)

    def test_telegram_only_delivery_is_saved_in_history(self):
        from server_advanced.notification_delivery import send_notification_with_telegram
        self.conn.execute('INSERT INTO cloud_server_bot (id, token_encrypted, username) VALUES (1, %s, %s)',
                          (self.encryption.encrypt_password('123456:test'), 'school_bot'))
        self.conn.commit()
        member = self.join()
        self.conn.execute('UPDATE cf3_registrations SET telegram_enabled = TRUE, telegram_user_id = %s WHERE id = %s',
                          ('123', member['registrationId']))
        self.conn.commit()
        with patch('server_advanced.telegram_bot.send_telegram_message', return_value=True):
            self.assertTrue(send_notification_with_telegram('Оценка', 'Новая оценка',
                            registration_id=member['registrationId'], notification_type='grade'))
        rows = self.conn.execute('SELECT title FROM cf3_notification_history WHERE registration_id = %s',
                                 (member['registrationId'],)).fetchall()
        self.assertEqual(rows, [('Оценка',)])

    def test_homework_is_available_in_both_modes_and_scoped_to_class(self):
        for mode in ('user', 'classmate'):
            member = self.join(mode)
            headers = {'X-API-Token': member['apiToken']}
            created = self.client.post('/custom-homework/create', headers=headers, data={
                'subject': 'Алгебра', 'lesson_date': '2026-09-11', 'text': 'Решить номер 25'})
            self.assertEqual(created.status_code, 200, created.json)
            listed = self.client.post('/custom-homework/list', headers=headers, json={})
            self.assertEqual(listed.status_code, 200, listed.json)
            self.assertTrue(listed.json['homework'])
        other = self.join('classmate', self.invite('10Б'))
        listed = self.client.post('/custom-homework/list', headers={'X-API-Token': other['apiToken']}, json={})
        self.assertEqual(listed.status_code, 200, listed.json)
        self.assertEqual(listed.json['homework'], [])


if __name__ == '__main__':
    unittest.main()
