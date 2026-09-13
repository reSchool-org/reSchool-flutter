"""тестовые данные повторяют веб клиент eschool от 5 сентября 2026: владелец по senderId и prsId, возраст правки по sendDate в миллисекундах"""

from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
from pathlib import Path
import sys
import threading
import types
import unittest
from unittest.mock import Mock, patch


SERVER = Path(__file__).resolve().parents[1]
PACKAGE = '_verification_security_backend'


class RequestGlobals(threading.local):
    def pop(self, key, default=None):
        return self.__dict__.pop(key, default)


class Database:
    """моделируем блокировку update и завершение транзакции, полную базу postgres не эмулируем"""

    def __init__(self):
        self.now = datetime(2026, 9, 5, 12)
        self.challenges = {}
        self.tokens = []
        self.connections = []
        self.lock = threading.RLock()
        self.fail = None

    def connect(self):
        connection = Connection(self)
        self.connections.append(connection)
        return connection


class Connection:
    def __init__(self, db):
        self.db = db
        self.pending = None
        self.token = None
        self.locked = False
        self.closed = False
        self.cursor_closed = False
        self.rowcount = 0
        self.result = None
        self.queries = []

    def cursor(self):
        return self

    def fetchone(self):
        return self.result

    def execute(self, sql, params):
        sql = ' '.join(sql.split())
        self.queries.append((sql, params))
        if sql.startswith('SELECT issued_at'):
            operation = 'select'
        elif sql.startswith('UPDATE verification_challenges'):
            operation = 'consume'
        elif sql.startswith('INSERT INTO verification_challenges'):
            operation = 'challenge_insert'
        elif sql.startswith('INSERT INTO verified_users'):
            operation = 'token_insert'
        else:
            raise AssertionError(f'Unexpected SQL: {sql}')
        if self.db.fail == operation:
            raise RuntimeError('secret-in-database-error')
        if operation in ('select', 'consume'):
            assert 'code_hash = %s AND target_prs_id = %s' in sql
            assert 'consumed_at IS NULL AND expires_at > LOCALTIMESTAMP(3)' in sql
        if operation == 'select':
            with self.db.lock:
                row = self.db.challenges.get(params[0])
                if row and row['target'] == params[1] and not row['used'] and row['expires'] > self.db.now:
                    self.result = (row['issued'], self.db.now)
                else:
                    self.result = None
        elif operation in ('consume', 'challenge_insert'):
            self.db.lock.acquire()
            self.locked = True
            if operation == 'consume':
                row = self.db.challenges.get(params[0])
                if row and row['target'] == params[1] and not row['used'] and row['expires'] > self.db.now:
                    self.pending = (params[0], dict(row, used=True))
                    self.rowcount = 1
                else:
                    self.rowcount = 0
            else:
                assert "INTERVAL '10 minutes'" in sql
                assert params[0] not in self.db.challenges
                self.pending = (params[0], {
                    'target': params[1], 'issued': self.db.now,
                    'expires': self.db.now + timedelta(minutes=10), 'used': False,
                })
        else:
            assert self.locked and self.pending and self.pending[1]['used']
            self.token = params

    def commit(self):
        if self.db.fail == 'commit':
            raise RuntimeError('secret-in-commit-error')
        if self.pending:
            self.db.challenges[self.pending[0]] = self.pending[1]
        if self.token:
            self.db.tokens.append(self.token)
        self.rollback()

    def rollback(self):
        self.pending = self.token = None
        if self.locked:
            self.locked = False
            self.db.lock.release()

    def close(self):
        # боевой код закрывает и курсор, и соединение, тут это один и тот же объект
        if self.cursor_closed:
            self.closed = True
            self.rollback()
        else:
            self.cursor_closed = True


class VerificationSecurityTests(unittest.TestCase):
    def setUp(self):
        self.db = Database()
        self.globals = RequestGlobals()
        self.request = Mock()
        self.state = types.SimpleNamespace(prs_id=900, cookies={'JSESSIONID': 'secret-cookie'})
        self.threads = Mock(return_value=[])
        self.messages = Mock(return_value=[])
        self.http = Mock(side_effect=AssertionError('Unexpected profile fetch'))
        self.log = Mock()
        self.connect = Mock(side_effect=self.db.connect)
        self.invalidate_tokens = Mock()
        package = types.ModuleType(PACKAGE)
        package.__path__ = []
        dependencies = {
            'flask': {
                'Blueprint': lambda *a: types.SimpleNamespace(route=lambda *a, **kw: lambda fn: fn),
                'jsonify': lambda value: value, 'request': self.request, 'g': self.globals,
            },
            'requests': {'get': self.http},
            f'{PACKAGE}.config': {
                'UPLOAD_FOLDER': '/unused', 'BASE_URL': 'https://app.eschool.center/ec-server',
                'USER_AGENT': 'eSchoolMobile',
            },
            f'{PACKAGE}.database': {
                'get_db_connection': self.connect,
                'invalidate_verified_user': self.invalidate_tokens,
            },
            f'{PACKAGE}.logging_utils': {'log': self.log},
            f'{PACKAGE}.rate_limiter': {'rate_limit': lambda *a: lambda fn: fn},
            f'{PACKAGE}.eschool_api': {
                'server_state': self.state, 'get_messages': self.threads,
                'get_thread_messages': self.messages,
            },
        }
        modules = {PACKAGE: package}
        for name, attributes in dependencies.items():
            modules[name] = types.ModuleType(name)
            modules[name].__dict__.update(attributes)
        spec = importlib.util.spec_from_file_location(
            f'{PACKAGE}.routes.verification', SERVER / 'server_advanced/routes/verification.py',
        )
        self.module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, modules):
            spec.loader.exec_module(self.module)

    def issue(self):
        result = self.module.request_verification()
        self.assertIsInstance(result, dict)
        self.assertEqual(set(result), {'code', 'targetPrsId'})
        self.code = result['code']
        self.code_hash = hashlib.sha256(self.code.encode('ascii')).hexdigest()
        self.db.now += timedelta(seconds=10)
        return result

    def valid_message(self, **changes):
        message = {
            'msgId': 12, 'msg': f'Verification code: {self.code}',
            'senderId': 123, 'senderFio': 'Message Display Name',
            'sendDate': (self.db.now.replace(tzinfo=timezone.utc).timestamp() - 1) * 1000,
            # метаданные аватарки намеренно расходятся с личностью отправителя
            'imgObjId': 777,
        }
        message.update(changes)
        return message

    def profile(self):
        return {'profile': {'prsBasic': {
            'prsId': 123, 'lastName': 'Trusted', 'firstName': 'Student'}}}

    def allow_profile(self, profile=None, status=200):
        response = Mock(status_code=status)
        response.json.return_value = self.profile() if profile is None else profile
        self.http.side_effect = None
        self.http.return_value = response
        return response

    def check(self, **changes):
        data = {'code': self.code, 'threadId': 42, 'deviceName': 'Phone',
                'fullName': 'Attacker Override', 'gradeClass': 'OtherClass'}
        data.update(changes)
        self.request.get_json.return_value = data
        return self.module.check_verification()

    def assert_no_upstream(self):
        self.threads.assert_not_called()
        self.messages.assert_not_called()
        self.http.assert_not_called()
        self.assertEqual(self.db.tokens, [])

    def test_challenge_is_random_hashed_persisted_and_expiring(self):
        with patch.object(self.module.secrets, 'token_hex', return_value='ab' * 16) as random:
            result = self.issue()
        random.assert_called_once_with(16)
        self.assertEqual(result, {'code': 'AB' * 16, 'targetPrsId': 900})
        row = self.db.challenges[self.code_hash]
        self.assertEqual(row['expires'] - row['issued'], timedelta(minutes=10))
        self.assertFalse(row['used'])
        self.assertNotIn(self.code, repr(self.db.challenges))
        self.assertTrue(all(c.closed and c.cursor_closed for c in self.db.connections))

    def test_unissued_and_malformed_codes_never_fetch_messages(self):
        for code in ('A' * 32, '', 'hello', 'secret-code', '%', ['A'], {'code': 'A'}, 1, True, 'a' * 32, 'A' * 32 + '\n'):
            with self.subTest(code=code):
                self.assertIsNone(self.module.find_verified_sender(code, 42)[0])
        self.assert_no_upstream()

    def test_expired_consumed_and_wrong_target_rejected_before_messages(self):
        self.issue()
        row = self.db.challenges[self.code_hash]
        for changes in ({'used': True}, {'expires': self.db.now}, {'target': 901}):
            with self.subTest(changes=changes):
                saved = dict(row)
                row.update(changes)
                self.assertEqual(self.check(), {'verified': False})
                row.update(saved)
        self.assert_no_upstream()

    def test_malformed_json_and_thread_id_fail_closed(self):
        self.issue()
        for body in (None, [], 'code', 1):
            self.request.get_json.return_value = body
            self.assertEqual(self.module.check_verification()[1], 400)
        for thread_id in ('42&prsId=123', True, -1, 0, [], {}, 42.0):
            self.assertEqual(self.check(threadId=thread_id), {'verified': False})
        self.assert_no_upstream()

    def test_requires_authenticated_server_for_both_routes(self):
        for attribute in ('cookies', 'prs_id'):
            with self.subTest(attribute=attribute):
                original = getattr(self.state, attribute)
                setattr(self.state, attribute, None)
                self.assertEqual(self.module.request_verification()[1], 503)
                self.assertEqual(self.module.find_verified_sender('A' * 32)[1], 'Server not authenticated')
                setattr(self.state, attribute, original)
        self.assert_no_upstream()

    def test_exact_message_only_not_substrings_html_quotes_or_previews(self):
        self.issue()
        text = f'Verification code: {self.code}'
        self.threads.return_value = [{'threadId': 42, 'preview': text, 'imgObjId': 123}]
        for body in (None, 1, [], text + '!', 'Quoted: ' + text, '<p>' + text + '</p>',
                     text + '\n', 'prefix' + self.code, self.code):
            with self.subTest(body=body):
                self.messages.return_value = [self.valid_message(msg=body)]
                self.assertEqual(self.check(), {'verified': False})
        self.messages.return_value = []
        self.assertEqual(self.check(), {'verified': False})
        self.http.assert_not_called()

    def test_only_incoming_authenticated_sender_not_avatar_or_owner(self):
        self.issue()
        for changes in ({'senderId': 900}, {'senderId': None}, {'senderId': True},
                        {'senderId': '123'}, {'senderId': -1}, {'isOwner': True},
                        {'isOwner': 'false'}, {'senderPrsId': 777}, {'msgId': None},
                        {'msgId': True}, {'msgId': 0}):
            with self.subTest(changes=changes):
                self.messages.return_value = [self.valid_message(**changes)]
                self.assertEqual(self.check(), {'verified': False})
        self.http.assert_not_called()

    def test_only_sent_after_issuance_no_display_date_or_create_date_fallback(self):
        self.issue()
        issued_ms = self.db.challenges[self.code_hash]['issued'].replace(tzinfo=timezone.utc).timestamp() * 1000
        for timestamp in (None, True, '2026-09-05', float('nan'), float('inf'),
                          issued_ms - 1, issued_ms, issued_ms + 11000, issued_ms / 1000):
            with self.subTest(timestamp=timestamp):
                self.messages.return_value = [self.valid_message(
                    sendDate=timestamp, createDate=issued_ms + 1000, showDate=issued_ms + 1000,
                )]
                self.assertEqual(self.check(), {'verified': False})
        self.http.assert_not_called()

    def test_success_uses_profile_identity_scope_and_preserves_response(self):
        self.issue()
        self.messages.return_value = [self.valid_message()]
        response = self.allow_profile()
        result = self.check()
        self.assertEqual(set(result), {'verified', 'token'})
        self.assertTrue(result['verified'])
        self.assertEqual(self.db.tokens,
                         [(result['token'], 123, 'Phone', 'Trusted Student', 'OtherClass')])
        self.assertTrue(self.db.challenges[self.code_hash]['used'])
        self.http.assert_called_once_with(
            'https://app.eschool.center/ec-server/profile/getShortProfile',
            params={'prsId': 123}, cookies=self.state.cookies,
            headers={'Accept': 'application/json', 'User-Agent': 'eSchoolMobile'},
            timeout=15, allow_redirects=False,
        )
        response.close.assert_called_once()
        self.assertTrue(all(c.closed and c.cursor_closed for c in self.db.connections))

    def test_thread_discovery_reads_messages_never_trusts_preview_identity(self):
        self.issue()
        self.threads.return_value = [{'threadId': 42, 'preview': 'unrelated', 'imgObjId': 456}]
        self.messages.return_value = [self.valid_message()]
        self.allow_profile()
        self.assertTrue(self.check(threadId=None)['verified'])
        self.messages.assert_called_once_with(self.state.cookies, 42)
        self.assertEqual(self.db.tokens[0][1], 123)

    def test_missing_mismatched_or_ambiguous_profile_fails_closed(self):
        self.issue()
        self.messages.return_value = [self.valid_message()]
        profile = self.profile()
        invalid_profiles = [None, [], {}, {'profile': None}, {'profile': {}},
                            {'profile': {'prsBasic': []}},
                            {'noAccess': 1},
                            {'profile': {'prsBasic': {'prsId': 123}},
                             'fio': 'Untrusted fallback'}]
        for field, value in (('prsId', 777), ('prsId', '123'), ('lastName', ''),
                             ('lastName', None), ('firstName', ['Student']),
                             ('middleName', 42)):
            candidate = deepcopy(profile)
            candidate['profile']['prsBasic'][field] = value
            invalid_profiles.append(candidate)
        for candidate in invalid_profiles:
            with self.subTest(profile=candidate):
                response = self.allow_profile()
                response.json.return_value = candidate
                self.assertEqual(self.check(), {'verified': False})
                response.close.assert_called_once()
        self.assertFalse(self.db.challenges[self.code_hash]['used'])
        self.assertEqual(self.db.tokens, [])

    def test_profile_http_errors_redirects_and_exception_do_not_issue_or_log_secrets(self):
        self.issue()
        self.messages.return_value = [self.valid_message()]
        for status in (301, 302, 401, 403, 500):
            response = self.allow_profile(status=status)
            self.assertEqual(self.check(), {'verified': False})
            response.json.assert_not_called()
            response.close.assert_called_once()
        self.http.side_effect = RuntimeError('secret-cookie')
        self.assertEqual(self.check(), {'verified': False})
        self.assertNotIn('secret-cookie', str(self.log.call_args_list))
        self.assertEqual(self.db.tokens, [])

    def test_expiry_during_upstream_call_is_rechecked_atomically(self):
        self.issue()
        self.messages.return_value = [self.valid_message()]
        response = self.allow_profile()

        def profile_after_expiry():
            self.db.now = self.db.challenges[self.code_hash]['expires']
            return self.profile()

        response.json.side_effect = profile_after_expiry
        self.assertEqual(self.check()[1], 500)
        self.assertEqual(self.db.tokens, [])
        self.assertFalse(self.db.challenges[self.code_hash]['used'])

    def test_replay_is_rejected_before_upstream(self):
        self.issue()
        self.messages.return_value = [self.valid_message()]
        self.allow_profile()
        self.assertTrue(self.check()['verified'])
        for mock in (self.messages, self.threads, self.http):
            mock.reset_mock()
        self.assertEqual(self.check(), {'verified': False})
        self.messages.assert_not_called()
        self.threads.assert_not_called()
        self.http.assert_not_called()
        self.assertEqual(len(self.db.tokens), 1)

    def test_concurrent_checks_only_one_token_commits(self):
        self.issue()
        self.messages.return_value = [self.valid_message()]
        self.allow_profile()
        barrier = threading.Barrier(2)

        def worker():
            prs_id, error = self.module.find_verified_sender(self.code, 42)
            self.assertEqual((prs_id, error), (123, None))
            barrier.wait(timeout=5)
            return self.module.issue_verification_token(prs_id, 'Phone', 'Override', 'OtherClass')

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(lambda _: worker(), range(2)))
        self.assertEqual(sum(token is not None for token, _ in results), 1)
        self.assertEqual(len(self.db.tokens), 1)
        self.assertTrue(self.db.challenges[self.code_hash]['used'])

    def test_legacy_helper_caller_cannot_bypass_challenge_or_override_name(self):
        self.assertEqual(self.module.issue_verification_token(123, 'Phone', 'Fake', 'Fake'),
                         (None, 'Verification required'))
        self.issue()
        self.messages.return_value = [self.valid_message()]
        self.allow_profile()
        self.assertEqual(self.module.find_verified_sender(self.code, 42), (123, None))
        self.assertIsNotNone(self.module.issue_verification_token(123, 'Phone', 'Fake', 'Fake')[0])
        self.assertEqual(self.db.tokens[0][3:], ('Trusted Student', 'Fake'))
        self.assertIsNone(self.module.issue_verification_token(123, 'Phone', 'Fake', 'Fake')[0])

    def test_invalid_second_check_clears_previous_request_proof(self):
        self.issue()
        self.messages.return_value = [self.valid_message()]
        self.allow_profile()
        self.assertEqual(self.module.find_verified_sender(self.code, 42), (123, None))
        self.module.find_verified_sender('bad', 42)
        self.assertIsNone(self.module.issue_verification_token(123, 'Phone', None, None)[0])
        self.assertEqual(self.db.tokens, [])

    def test_proof_cannot_be_rebound_to_another_sender_or_server(self):
        self.issue()
        self.messages.return_value = [self.valid_message()]
        self.allow_profile()
        self.assertEqual(self.module.find_verified_sender(self.code, 42), (123, None))
        self.assertIsNone(self.module.issue_verification_token(777, 'Phone', None, None)[0])
        self.assertEqual(self.module.find_verified_sender(self.code, 42), (123, None))
        self.state.prs_id = 901
        self.assertIsNone(self.module.issue_verification_token(123, 'Phone', None, None)[0])
        self.assertEqual(self.db.tokens, [])
        self.assertFalse(self.db.challenges[self.code_hash]['used'])

    def test_name_includes_middle_name_and_class_is_taken_from_client(self):
        self.issue()
        self.messages.return_value = [self.valid_message()]
        profile = self.profile()
        profile['profile']['prsBasic']['middleName'] = 'Middle'
        self.allow_profile(profile)
        self.assertTrue(self.check(gradeClass='  9B  ')['verified'])
        self.assertEqual(self.db.tokens[0][3:], ('Trusted Student Middle', '9B'))

    def test_client_class_is_validated_and_optional(self):
        for value, stored in (('11A', '11A'), ('', None), (None, None),
                              (['9B'], None), ('x' * 33, None)):
            with self.subTest(gradeClass=value):
                self.setUp()
                self.issue()
                self.messages.return_value = [self.valid_message()]
                self.allow_profile()
                self.assertTrue(self.check(gradeClass=value)['verified'])
                self.assertEqual(self.db.tokens[0][4], stored)

    def test_database_failure_never_returns_code_or_token_and_rolls_back(self):
        for failure in ('challenge_insert', 'commit'):
            self.db.fail = failure
            self.assertEqual(self.module.request_verification()[1], 503)
            self.assertEqual(self.db.challenges, {})
        self.db.fail = None
        self.issue()
        self.messages.return_value = [self.valid_message()]
        self.allow_profile()
        for failure in ('select', 'consume', 'token_insert', 'commit'):
            with self.subTest(failure=failure):
                self.db.fail = failure
                result = self.check()
                self.assertNotIn('token', result if isinstance(result, dict) else result[0])
                self.assertEqual(self.db.tokens, [])
                self.assertFalse(self.db.challenges[self.code_hash]['used'])
        self.assertTrue(all(c.closed and c.cursor_closed for c in self.db.connections))
        self.assertNotIn('secret-in-', str(self.log.call_args_list))

    def test_database_unavailable_does_not_fetch_messages(self):
        self.issue()
        self.connect.side_effect = None
        self.connect.return_value = None
        self.assertEqual(self.module.request_verification()[1], 503)
        self.assertEqual(self.check(), {'verified': False})
        self.assert_no_upstream()

    def test_success_does_not_log_challenge_cookie_or_token(self):
        self.issue()
        self.messages.return_value = [self.valid_message()]
        self.allow_profile()
        result = self.check()
        logs = str(self.log.call_args_list)
        for secret in (self.code, result['token'], 'secret-cookie'):
            self.assertNotIn(secret, logs)


if __name__ == '__main__':
    unittest.main()
