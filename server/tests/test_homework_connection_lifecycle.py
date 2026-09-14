"""настоящую обёртку пула проверяем с ограниченным поддельным драйвером, который создаёт ошибки sql и транзакций"""
from datetime import date, datetime
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

from test_backend_hardening import PACKAGE, load_module
from test_chat_notifications import make_chat, make_routes


IDLE, ACTIVE = 0, 1


def pooled_connection_class():
    return load_module('database', {
        'psycopg': {'pq': types.SimpleNamespace(TransactionStatus=types.SimpleNamespace(IDLE=IDLE))},
        'psycopg.rows': {'dict_row': object(), 'tuple_row': object()},
        'psycopg.types.json': {'Jsonb': lambda value: value},
        'psycopg_pool': {'ConnectionPool': Mock()},
        'requests': {},
        f'{PACKAGE}.cache': {},
        f'{PACKAGE}.config': {key: 1 for key in (
            'CACHE_AUTH_TTL_SECONDS', 'CACHE_SESSION_TTL_SECONDS', 'DB_CONNECT_TIMEOUT',
            'DB_DSN', 'DB_POOL_MAX_SIZE', 'DB_POOL_MIN_SIZE', 'DB_POOL_TIMEOUT',
            'DB_STATEMENT_TIMEOUT_MS')},
        f'{PACKAGE}.logging_utils': {'log': Mock()},
    }).PooledConnection


class Pool:
    """пул выдаёт одно соединение, пропущенный возврат заблокирует следующий запрос"""
    def __init__(self):
        self.wrapper = pooled_connection_class()
        self.outstanding = set()
        self.returned = []
        self.raw = None
        self.fail = None
        self.owner = (0, '9А', 'classmate', 'Алгебра', date(2026, 9, 11))

    def connect(self):
        if self.outstanding:
            return None
        self.raw = RawConnection(self)
        self.outstanding.add(self.raw)
        return self.wrapper(self, self.raw)

    def putconn(self, raw):
        if raw.info.transaction_status != IDLE:
            raise AssertionError('Returned an unfinished transaction')
        self.outstanding.remove(raw)
        self.returned.append(raw)


class RawConnection:
    def __init__(self, pool):
        self.pool = pool
        self.info = types.SimpleNamespace(transaction_status=IDLE)
        self.rollbacks = 0
        self.commits = 0
        self.cursor_mock = Mock()
        self.cursor_mock.execute.side_effect = self.execute
        self.cursor_mock.fetchall.return_value = []
        if pool.fail == 'cursor_close':
            self.cursor_mock.close.side_effect = RuntimeError('cursor close failed')

    def cursor(self, **kwargs):
        if self.pool.fail == 'cursor':
            raise RuntimeError('cursor acquisition failed')
        return self.cursor_mock

    def execute(self, query, params=None):
        query = ' '.join(query.split())
        self.info.transaction_status = ACTIVE
        if self.pool.fail == 'execute':
            raise RuntimeError('SQL failed')
        if query.startswith('INSERT INTO custom_homework '):
            if len(params[3]) > 256:
                raise ValueError('value too long for type character varying(256)')
            self.cursor_mock.fetchone.return_value = (42,)
        elif query.startswith('SELECT author_prs_id'):
            if str(params[0]) in ('invalid', '9223372036854775808'):
                raise ValueError('invalid or out-of-range bigint')
            columns = query.split(' FROM ', 1)[0].removeprefix('SELECT ').split(',')
            self.cursor_mock.fetchone.return_value = self.pool.owner[:len(columns)] if self.pool.owner else None
        elif query.startswith('SELECT full_name FROM verified_users'):
            self.cursor_mock.fetchone.return_value = ('Ученик',)
        elif query.startswith('SELECT COUNT(*)'):
            self.cursor_mock.fetchone.return_value = (0,)
        elif query.startswith('SELECT id, subject'):
            row = (42, 'Алгебра', date(2026, 9, 11), 'Решить номер 25', 'Ученик')
            if 'author_prs_id' in query:
                row += (0, datetime(2026, 9, 11), None)
            else:
                row += (datetime(2026, 9, 11),)
            self.cursor_mock.fetchone.return_value = row
        elif query.startswith('SELECT storage_path'):
            self.cursor_mock.fetchone.return_value = ('attachment.txt',)

    def commit(self):
        if self.pool.fail == 'commit':
            raise RuntimeError('commit failed')
        self.commits += 1
        self.info.transaction_status = IDLE

    def rollback(self):
        self.rollbacks += 1
        self.info.transaction_status = IDLE


class HomeworkConnectionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.pool = Pool()
        self.request = types.SimpleNamespace(
            form={}, json={}, files=types.SimpleNamespace(getlist=lambda key: []),
            url_root='https://school.test/')
        self.g = types.SimpleNamespace(is_classmate=True, classmate_id='classmate',
            classmate_grade_class='9А', classmate_display_name='Ученик')
        self.module = load_module('routes.homework', {
            'flask': {
                'Blueprint': lambda *a: types.SimpleNamespace(route=lambda *a, **k: lambda fn: fn),
                'jsonify': lambda value: value, 'request': self.request, 'g': self.g,
                'send_file': Mock(), 'render_template_string': Mock(),
            },
            'requests': {}, 'werkzeug.utils': {'secure_filename': lambda value: value},
            f'{PACKAGE}.cache': {},
            f'{PACKAGE}.database': {
                **{key: Mock() for key in ('cache_verified_user', 'get_cached_verified_user',
                    'homework_version', 'invalidate_homework', 'load_user_session')},
                'get_db_connection': self.pool.connect,
            },
            f'{PACKAGE}.config': {
                'UPLOAD_FOLDER': self.tmp.name, 'MAX_FILE_SIZE': 1024,
                'MAX_FILES_PER_HOMEWORK': 3, 'BASE_URL': 'https://school.test',
                'USER_AGENT': 'test', 'get_public_base_url': lambda: 'https://school.test',
            },
            f'{PACKAGE}.rate_limiter': {'rate_limit': lambda *a: lambda fn: fn},
            f'{PACKAGE}.logging_utils': {'log': Mock()},
            f'{PACKAGE}.utils': {'allowed_file': lambda name: True},
            f'{PACKAGE}.eschool_api': {'server_state': Mock()},
            f'{PACKAGE}.keep_alive': {'get_session': Mock()},
            f'{PACKAGE}.analysis': {'is_enabled': lambda: False},
            f'{PACKAGE}.routes.notifications': {'_notify_classmates': Mock()},
        })
        self.module.get_user_by_token = Mock(return_value=(7, '9А'))
        self.module._get_registration_id_for_token = Mock(return_value=None)
        self.module._dispatch_custom_homework_original = self.module._dispatch_custom_homework
        self.module._dispatch_custom_homework = Mock(side_effect=self.assert_released)
        self.module._reanalyze_custom_homework_original = self.module._reanalyze_custom_homework
        self.module._reanalyze_custom_homework = Mock(side_effect=self.assert_released)
        self.module._notify_group_about_custom_homework_original = self.module._notify_group_about_custom_homework
        self.module._notify_group_about_custom_homework = Mock(side_effect=self.assert_released)
        self.module.get_homework_files = Mock(return_value=[])
        self.module._request_summary_rebuild = Mock()

    def assert_released(self, *args, **kwargs):
        self.assertEqual(self.pool.outstanding, set())

    def test_custom_notification_passes_analysis_separately_from_homework_text(self):
        estimate = {'estimable': True, 'total_minutes': 25}
        self.module._send_custom_homework_notifications(
            42, '9А', 'Русский язык', '2026-09-14', 'упр 6', 'Иван Иванов', [],
            'https://school.test', None, None, extra_lines=['⏱ примерно 25 мин'],
            analysis_id=7, analysis_data=estimate)
        sent = self.module._notify_group_about_custom_homework.call_args.kwargs
        self.assertEqual(sent['text'], 'упр 6')
        self.assertIs(sent['analysis_data'], estimate)

    def test_group_delivery_keeps_metadata_out_of_task_body(self):
        conn = Mock()
        conn.cursor.return_value.fetchall.return_value = [{
            'id': 'owner', 'telegram_bot_token': 'test', 'telegram_group_chat_id': '-100',
            'telegram_topic_map': {}, 'known_subjects': {}}]
        self.module.get_db_connection = Mock(return_value=conn)
        bot = types.ModuleType(f'{PACKAGE}.telegram_bot')
        bot.send_telegram_message = Mock(return_value=True)
        estimate = {'estimable': True, 'total_minutes': 25}
        with patch.dict('sys.modules', {f'{PACKAGE}.telegram_bot': bot}):
            self.module._notify_group_about_custom_homework_original(
                '9А', 'Русский язык', '2026-09-14', 'упр 6', 'Иван Иванов', [],
                'https://school.test', analysis_data=estimate)
        bot.send_telegram_message.assert_called_once()
        call = bot.send_telegram_message.call_args
        self.assertEqual(call.args[3], 'упр 6')
        self.assertEqual(call.kwargs['notification_data']['author'], 'Иван Иванов')
        self.assertIs(call.kwargs['analysis_data'], estimate)

    def test_pending_custom_homework_keeps_full_text_for_telegram(self):
        self.module.analysis.is_enabled = lambda: True
        self.module.analysis.enqueue = Mock(return_value=(7, True))
        self.module.analysis.add_pending = Mock()
        text = 'Подробное задание. ' * 20 + 'Последнее условие.'
        self.module._dispatch_custom_homework_original(
            42, '9А', 'Русский язык', '2026-09-14', text, 'Иван Иванов', [],
            'https://school.test', None, None)
        self.assertEqual(self.module.analysis.add_pending.call_args.args[4], text)

    def test_queued_attachment_recovers_local_path_before_releasing_connection_and_sending(self):
        stored = {'id': 1, 'fileName': 'photo.jpg', 'storagePath': '/uploads/photo.jpg'}
        self.module.get_homework_files.return_value = [stored]
        self.module._send_custom_homework_notifications(
            42, '9А', 'Физика', '2026-09-16', 'Переписать таблицу', 'Автор',
            [{'id': 1, 'fileName': 'photo.jpg'}], 'https://school.test', None, None)
        self.assertTrue(self.module.get_homework_files.call_args.kwargs['include_storage_path'])
        self.assertEqual(self.module.get_homework_files.call_args.args[1], 42)
        self.assertEqual(self.module._notify_group_about_custom_homework.call_args.kwargs['files'], [stored])
        self.assert_released()

    def test_group_failure_is_propagated_even_when_classmate_history_succeeds(self):
        self.module._notify_group_about_custom_homework = Mock(return_value=False)
        self.assertFalse(self.module._send_custom_homework_notifications(
            42, '9А', 'Физика', '2026-09-16', 'Текст', 'Автор', [],
            'https://school.test', None, None))
        self.module._notify_classmates.assert_called_once()

    def call(self, operation, **changes):
        body = {'subject': 'Алгебра', 'lesson_date': '2026-09-11',
                'text': 'Решить номер 25', 'homework_id': '42', 'token': 'owner'}
        body.update(changes)
        self.request.form = self.request.json = body
        return getattr(self.module, operation + '_custom_homework')()

    def test_repeated_sql_errors_leave_capacity_for_valid_request(self):
        for operation, bad in [('create', {'subject': 'я' * 257}),
                               ('update', {'homework_id': 'invalid'}),
                               ('delete', {'homework_id': '9223372036854775808'})]:
            for attempt in range(12):
                with self.subTest(operation=operation, attempt=attempt):
                    response = self.call(operation, **bad)
                    self.assertEqual(response, ({'error': 'Database error'}, 500))
                    self.assert_released()
                    self.assertEqual(self.pool.raw.rollbacks, 1)
            self.assertTrue(self.call(operation)['success'])
            self.assert_released()

    def test_cursor_sql_commit_and_cursor_close_failures_release(self):
        for operation in ('create', 'update', 'delete'):
            for failure in ('cursor', 'execute', 'commit', 'cursor_close'):
                with self.subTest(operation=operation, failure=failure):
                    self.pool.fail = failure
                    self.assertEqual(self.call(operation)[1], 500)
                    self.assert_released()
                    self.assertEqual(self.pool.returned.count(self.pool.raw), 1)
        self.pool.fail = None
        self.assertTrue(self.call('create')['success'])

    def test_filesystem_failure_releases(self):
        for operation in ('create', 'update'):
            with self.subTest(operation=operation), patch.object(self.module.os, 'makedirs', side_effect=OSError('disk full')):
                self.assertEqual(self.call(operation)[1], 500)
                self.assert_released()
        self.pool.raw = None
        # настоящий временный файл проверяет, что удаление доходит до os.remove
        attachment = Path(self.tmp.name) / 'attachment.txt'
        attachment.write_text('homework')
        connect = self.module.get_db_connection
        def with_attachment():
            conn = connect()
            self.pool.raw.cursor_mock.fetchall.return_value = [(str(attachment),)]
            return conn
        self.module.get_db_connection = with_attachment
        with patch.object(self.module.os, 'remove', side_effect=OSError('permission denied')):
            self.assertEqual(self.call('delete')[1], 500)
            self.assert_released()

    def test_not_found_and_ownership_checks_remain(self):
        for operation in ('update', 'delete'):
            for owner, status in [(None, 404), ((9, '9А', 'other'), 403)]:
                for classmate in (False, True):
                    with self.subTest(operation=operation, owner=owner, classmate=classmate):
                        self.pool.owner = owner
                        self.g.is_classmate = classmate
                        self.assertEqual(self.call(operation)[1], status)
                        self.assert_released()
                        self.assertEqual(self.pool.raw.commits, 0)

    def test_create_early_returns_release(self):
        self.g.classmate_grade_class = None
        self.assertEqual(self.call('create')[1], 400)
        self.assert_released()
        self.g.is_classmate = False
        self.assertEqual(self.call('create', token='')[1], 401)
        self.assert_released()
        self.module.get_user_by_token.return_value = (None, None)
        self.assertEqual(self.call('create')[1], 401)
        self.assert_released()

    def test_success_responses_for_both_auth_modes_and_delete_summary(self):
        for classmate in (True, False):
            self.g.is_classmate = classmate
            self.pool.owner = (7, '9А', 'classmate', 'Алгебра', date(2026, 9, 11))
            for operation in ('create', 'update', 'delete'):
                with self.subTest(operation=operation, classmate=classmate):
                    response = self.call(operation)
                    self.assertTrue(response['success'])
                    self.assert_released()
                    if operation != 'delete':
                        self.assertEqual(response['homework']['id'], 42)
                        self.assertEqual(response['homework']['files'], [])
                        self.assertTrue(response['homework']['isMine'])
                    else:
                        args = self.module._request_summary_rebuild.call_args.args
                        self.assertEqual(args[1:], ('9А', 'Алгебра', date(2026, 9, 11)))
                        self.assertEqual(self.pool.raw.commits, 2)

    def test_secondary_mutation_connections_release_on_error(self):
        self.module.analysis.is_enabled = lambda: True
        for failure in ('cursor', 'execute', 'cursor_close'):
            self.pool.fail = failure
            with self.subTest(helper='reanalyze', failure=failure):
                self.module._reanalyze_custom_homework_original(42, '9А', 'Алгебра', '2026-09-11', 'Текст')
                self.assert_released()
            with self.subTest(helper='group', failure=failure):
                self.module._notify_group_about_custom_homework_original(
                    '9А', 'Алгебра', '2026-09-11', 'Текст', 'Ученик', [], 'https://school.test')
                self.assert_released()

    def test_notification_history_connection_released_on_error(self):
        routes = make_routes(*make_chat())
        routes.get_db_connection = self.pool.connect
        for failure in ('cursor', 'execute', 'commit', 'cursor_close'):
            with self.subTest(failure=failure):
                self.pool.fail = failure
                routes._notify_classmates('9А', 'Домашнее задание', 'Текст')
                self.assert_released()


if __name__ == '__main__':
    unittest.main()
