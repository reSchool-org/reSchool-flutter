import json
import os
from pathlib import Path
import sys
import tempfile
import threading
import types
import unittest
import uuid
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock, patch

import requests
from cryptography.fernet import Fernet
from telebot import apihelper

from test_backend_hardening import PACKAGE, SERVER, load_module


def make_outbox(connect=Mock()):
    cipher = Fernet(Fernet.generate_key())
    return load_module('telegram_outbox', {
        f'{PACKAGE}.database': {'get_db_connection': connect, 'json_value': lambda v: v},
        f'{PACKAGE}.encryption': {
            'encrypt_password': lambda v: cipher.encrypt(v.encode()).decode(),
            'decrypt_password': lambda v: cipher.decrypt(v.encode()).decode(),
        },
        f'{PACKAGE}.logging_utils': {'log': Mock()},
    })


def rejection(code, description='Telegram failure', retry_after=None):
    result = {'error_code': code, 'description': description}
    if retry_after is not None:
        result['parameters'] = {'retry_after': retry_after}
    return apihelper.ApiTelegramException('sendMessage', None, result)


class RetryPolicyTests(unittest.TestCase):
    def setUp(self):
        self.module = make_outbox()

    def test_connect_timeout_retries_and_read_timeout_is_ambiguous(self):
        status, delay = self.module.retry_policy(requests.ConnectTimeout(), 1)
        self.assertEqual(status, 'retry')
        self.assertGreaterEqual(delay, 30)
        self.assertEqual(self.module.retry_policy(requests.ReadTimeout(), 1), ('unknown', 0))
        self.assertEqual(self.module.retry_policy(requests.ConnectionError(), 1), ('unknown', 0))
        self.assertEqual(self.module.retry_policy(self.module.CheckpointError(), 1), ('unknown', 0))
        from urllib3.exceptions import NewConnectionError
        self.assertEqual(self.module.retry_policy(requests.ConnectionError(NewConnectionError(None, 'DNS failed')), 1)[0], 'retry')

    def test_rate_limit_honours_retry_after_and_permanent_failures_stop(self):
        self.assertGreaterEqual(self.module.retry_policy(rejection(429, retry_after=240), 1)[1], 241)
        for code in (400, 401, 403, 404):
            self.assertEqual(self.module.retry_policy(rejection(code), 1), ('failed', 0))
        self.assertEqual(self.module.retry_policy(requests.ConnectTimeout(), 8), ('failed', 0))

    def test_payload_fingerprint_ignores_rotated_auth_but_not_content(self):
        first = {'title': 'ДЗ', 'body': 'Решить', 'attachment_cookies': {'session': 'one'},
                 'attachments': [{'url': 'https://school.test/file?id=8&token=one'}]}
        second = {**first, 'attachment_cookies': {'session': 'two'},
                  'attachments': [{'url': 'https://school.test/file?id=8&token=two'}]}
        self.assertEqual(self.module._fingerprint(first), self.module._fingerprint(second))
        self.assertNotEqual(self.module._fingerprint(first), self.module._fingerprint({**second, 'body': 'Другое'}))


class GradeCheckpointTests(unittest.TestCase):
    def routes(self):
        from test_chat_notifications import make_chat, make_routes
        routes = make_routes(*make_chat())
        cookies = Mock()
        cookies.get_dict.return_value = {}
        routes.get_session.return_value = cookies
        routes._load_item_hashes = Mock(return_value={})
        routes._save_item_hashes = Mock()
        routes._check_chat_updates = Mock()
        routes.fetch_data_with_session = Mock(return_value=([], [
            {'id': i, 'subject': 'Физика', 'value': '5', 'date': 1789419600000}
            for i in range(10, 17)], [], None, False, 70))
        return routes

    def test_all_new_grades_are_queued_without_truncation(self):
        routes = self.routes()
        routes.send_notification_with_telegram.return_value = True
        routes._check_user_for_updates({'id':'student','username':'student','password':'encrypted','grade_class':'8-3'})
        self.assertEqual(routes.send_notification_with_telegram.call_count, 7)

    def test_failed_enqueue_does_not_advance_grade_snapshot(self):
        routes = self.routes()
        routes.send_notification_with_telegram.return_value = False
        with self.assertRaisesRegex(RuntimeError, 'Grade notification not queued'):
            routes._check_user_for_updates({'id':'student','username':'student','password':'encrypted','grade_class':'8-3'})
        queries = [c.args[0] for c in routes.get_db_connection.return_value.cursor.return_value.execute.call_args_list]
        self.assertFalse(any('last_grade_ids =' in q for q in queries))
        routes._save_item_hashes.assert_not_called()


class GroupConnectionNoticeTests(unittest.TestCase):
    def setUp(self):
        from flask import Flask, request, jsonify
        from test_chat_notifications import make_chat, make_routes
        self.routes = make_routes(*make_chat())
        self.routes._require_registration_owner = Mock(return_value=None)
        self.conn = self.routes.get_db_connection.return_value
        self.cursor = self.conn.cursor.return_value
        self.cursor.fetchone.return_value = {'id': 'primary', 'telegram_group_enabled': False,
                                            'telegram_group_chat_id': '-100'}
        self.routes.send_group_connected_notice.return_value = True
        self.app = Flask(__name__)
        self.routes.request, self.routes.jsonify = request, jsonify
        self.app.add_url_rule('/update-telegram-group', view_func=self.routes.cf3_update_telegram_group, methods=['POST'])
        self.client = self.app.test_client()

    def update(self, **kwargs):
        return self.client.post('/update-telegram-group', json={
            'registrationId': 'device', 'telegramGroupEnabled': True,
            'telegramGroupChatId': '-100', 'telegramGroupTitle': 'Класс', **kwargs})

    def test_enabling_queues_private_notice_in_settings_transaction(self):
        self.routes.send_group_connected_notice.side_effect = lambda *a, **kw: (
            self.conn.commit.assert_not_called() or True)
        result = self.update()
        self.assertEqual(result.status_code, 200)
        self.routes.send_group_connected_notice.assert_called_once_with('primary', '-100', 'Класс', connection=self.conn)
        self.conn.commit.assert_called_once()
        self.conn.close.assert_called_once()

    def test_changing_group_notifies_but_topic_edits_and_disabling_do_not(self):
        self.cursor.fetchone.return_value.update(telegram_group_enabled=True)
        self.assertEqual(self.update(telegramTopicMap={'1': 7}).status_code, 200)
        self.routes.send_group_connected_notice.assert_not_called()
        self.assertEqual(self.update(telegramGroupEnabled=False).status_code, 200)
        self.routes.send_group_connected_notice.assert_not_called()
        self.assertEqual(self.update(telegramGroupChatId='-200').status_code, 200)
        self.routes.send_group_connected_notice.assert_called_once_with('primary', '-200', 'Класс', connection=self.conn)

    def test_enqueue_failure_rolls_back_settings_and_reports_retryable_error(self):
        self.routes.send_group_connected_notice.return_value = False
        result = self.update()
        self.assertEqual(result.status_code, 503)
        self.conn.rollback.assert_called_once()
        self.conn.commit.assert_not_called()
        self.conn.close.assert_called_once()

    def test_commit_failure_does_not_report_success(self):
        self.conn.commit.side_effect = RuntimeError('database unavailable')
        self.assertEqual(self.update().status_code, 500)
        self.conn.rollback.assert_called_once()

    def test_cannot_enable_without_group(self):
        self.assertEqual(self.update(telegramGroupChatId='').status_code, 400)
        self.routes.send_group_connected_notice.assert_not_called()
        self.routes.get_db_connection.assert_not_called()


class RuntimeLoggingTests(unittest.TestCase):
    def test_persistent_error_has_stack_without_secret_and_preserves_time(self):
        logs = load_module('runtime_logging', {})
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, RESCHOOL_RUNTIME_DIR=directory):
            try:
                raise ValueError('download https://example.test/file?token=SECRET 123:PRIVATE_TOKEN')
            except ValueError:
                logs.write_log('failed at 15:28:32', sys.exc_info())
            logs._handler.flush()
            contents = (Path(directory) / 'logs/server.log').read_text()
            self.assertIn('Traceback', contents)
            self.assertIn('ValueError', contents)
            self.assertIn('15:28:32', contents)
            self.assertNotIn('token=SECRET', contents)
            self.assertNotIn('123:PRIVATE_TOKEN', contents)
            logs._handler.close()



@unittest.skipUnless(os.getenv('RESCHOOL_TEST_DATABASE_URL'), 'нужна RESCHOOL_TEST_DATABASE_URL')
class OutboxDatabaseTests(unittest.TestCase):
    def setUp(self):
        import psycopg
        from psycopg import sql
        from psycopg.rows import dict_row, tuple_row
        from psycopg.types.json import Jsonb
        self.schema = 'outbox_test_' + uuid.uuid4().hex
        self.admin = psycopg.connect(os.environ['RESCHOOL_TEST_DATABASE_URL'], autocommit=True)
        self.admin.execute(sql.SQL('CREATE SCHEMA {}').format(sql.Identifier(self.schema)))
        self.addCleanup(self.cleanup_schema)
        self.admin.execute(sql.SQL('SET search_path TO {}').format(sql.Identifier(self.schema)))
        self.admin.execute('CREATE TABLE pending_notifications (id BIGINT)')
        self.admin.execute((SERVER / 'server_advanced/migrations/0011_telegram_outbox.sql').read_text())
        self.admin.execute("""CREATE TABLE cf3_notification_history (
            id BIGSERIAL PRIMARY KEY, registration_id TEXT, notification_type TEXT,
            title TEXT, body TEXT, data JSONB)""")
        schema = self.schema
        class Connection:
            def __init__(self):
                self.raw = psycopg.connect(os.environ['RESCHOOL_TEST_DATABASE_URL'])
                self.raw.execute(sql.SQL('SET search_path TO {}').format(sql.Identifier(schema)))
                self.raw.commit()
            def cursor(self, dictionary=False):
                return self.raw.cursor(row_factory=dict_row if dictionary else tuple_row)
            def commit(self): self.raw.commit()
            def rollback(self): self.raw.rollback()
            def close(self): self.raw.close()
        self.module = make_outbox(Connection)
        self.module.json_value = Jsonb
        self.connect = Connection
        self.send = Mock(return_value=True)
        bot = types.ModuleType(f'{PACKAGE}.telegram_bot')
        bot.send_telegram_message = self.send
        self.patcher = patch.dict(sys.modules, {bot.__name__: bot})
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def cleanup_schema(self):
        from psycopg import sql
        self.admin.execute(sql.SQL('DROP SCHEMA {} CASCADE').format(sql.Identifier(self.schema)))
        self.admin.close()

    def enqueue(self, target='55', value='5', source='123'):
        return self.module.enqueue_telegram_message('123:PRIVATE_TOKEN', target, 'Новая оценка', 'Физика',
            notification_type='grade', notification_data={'id': source, 'value': value})

    def rows(self):
        return self.admin.execute('SELECT id,status,attempts,last_error FROM telegram_outbox ORDER BY id').fetchall()

    def test_borrowed_connection_commits_or_rolls_back_with_settings(self):
        conn = self.connect()
        try:
            for commit in (False, True):
                conn.raw.execute('INSERT INTO pending_notifications (id) VALUES (17)')
                self.assertTrue(self.module.enqueue_telegram_message(
                    '123:PRIVATE_TOKEN', '55', 'Группа подключена', 'Класс',
                    notification_type='group_connected', connection=conn))
                self.assertEqual(self.rows(), [])
                self.assertEqual(self.admin.execute('SELECT count(*) FROM pending_notifications').fetchone()[0], 0)
                if commit:
                    conn.commit()
                else:
                    conn.rollback()
                    self.assertEqual(self.rows(), [])
            self.assertEqual(len(self.rows()), 1)
            self.assertEqual(self.admin.execute('SELECT count(*) FROM pending_notifications').fetchone()[0], 1)
        finally:
            conn.close()

    def test_concurrent_enqueue_is_idempotent_and_payload_is_encrypted(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            self.assertTrue(all(pool.map(lambda _: self.enqueue(), range(2))))
        self.assertEqual(len(self.rows()), 1)
        payload = self.admin.execute('SELECT payload_encrypted FROM telegram_outbox').fetchone()[0]
        self.assertNotIn('PRIVATE_TOKEN', payload)
        self.assertEqual(json.loads(self.module.decrypt_password(payload))['notification_data']['value'], '5')
        self.assertNotIn('PRIVATE_TOKEN', str(self.module.log.call_args_list))

    def test_changes_back_to_previous_value_create_new_event(self):
        for value in ('5', '4', '5'):
            self.enqueue(value=value)
        self.assertEqual(len(self.rows()), 3)

    def test_failure_of_one_target_does_not_resend_another(self):
        self.enqueue('55')
        self.enqueue('-100')
        self.send.side_effect = [requests.ConnectTimeout(), True, True]
        self.module.process_one()
        self.module.process_one()
        self.assertEqual([r[1] for r in self.rows()], ['retry', 'sent'])
        self.admin.execute("UPDATE telegram_outbox SET next_attempt_at=now()-interval '1 minute' WHERE status='retry'")
        self.module.process_one()
        self.assertEqual([r[1] for r in self.rows()], ['sent', 'sent'])
        self.assertEqual([c.kwargs['user_id'] for c in self.send.call_args_list], ['55', '-100', '55'])

    def test_concurrent_workers_do_not_send_same_target_twice(self):
        self.enqueue(source='one')
        self.enqueue(source='two')
        started, release = threading.Event(), threading.Event()
        def sending(**kwargs):
            started.set()
            release.wait(3)
            return True
        self.send.side_effect = sending
        with ThreadPoolExecutor(max_workers=2) as pool:
            first = pool.submit(self.module.process_one)
            self.assertTrue(started.wait(3))
            try:
                self.assertFalse(pool.submit(self.module.process_one).result(timeout=3))
            finally:
                release.set()
            self.assertTrue(first.result(timeout=3))
        self.send.assert_called_once()

    def test_checkpoint_is_reused_and_sent_event_is_not_repeated(self):
        self.enqueue()
        def interrupted(**kwargs):
            kwargs['progress']['confirmed'] = [17]
            kwargs['checkpoint'](kwargs['progress'])
            raise requests.ConnectTimeout()
        self.send.side_effect = interrupted
        self.module.process_one()
        self.admin.execute("UPDATE telegram_outbox SET next_attempt_at=now()-interval '1 minute'")
        self.send.side_effect = lambda **kwargs: kwargs['progress']['confirmed'] == [17]
        self.module.process_one()
        self.assertEqual(self.rows()[0][1], 'sent')
        self.assertFalse(self.module.process_one())
        self.enqueue()
        self.assertEqual(len(self.rows()), 1)

    def test_ambiguous_timeout_and_interrupted_worker_are_not_blindly_retried(self):
        self.enqueue()
        self.send.side_effect = requests.ReadTimeout('private token must not leak')
        self.module.process_one()
        self.assertEqual(self.rows()[0][1], 'unknown')
        self.assertFalse(self.module.process_one())
        self.assertNotIn('private token', str(self.rows()))
        self.enqueue(target='other')
        self.admin.execute("UPDATE telegram_outbox SET status='sending',locked_until=now()-interval '1 minute' WHERE status='pending'")
        self.assertFalse(self.module.process_one())
        self.assertEqual([r[1] for r in self.rows()], ['unknown', 'unknown'])

    def test_history_retry_is_idempotent_but_grade_revision_is_recorded(self):
        from psycopg.types.json import Jsonb
        history = load_module('notification_delivery', {
            f'{PACKAGE}.database': {'get_db_connection': self.connect, 'json_value': Jsonb},
            f'{PACKAGE}.logging_utils': {'log': Mock()},
        })
        for value in ('5','5','4','5'):
            self.assertTrue(history.save_notification_history('reg', 'grade', 'Оценка', 'Физика', {'id':'123','value':value}))
        self.assertEqual(self.admin.execute('SELECT count(*) FROM cf3_notification_history').fetchone()[0], 3)


if __name__ == '__main__':
    unittest.main()
