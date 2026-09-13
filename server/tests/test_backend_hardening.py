"""подменяем зависимости, чтобы тесты не запускали сервер и внешние обращения"""

import ast
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import MagicMock, Mock, patch
from urllib.parse import parse_qs, urlsplit

import test_verification_security as verification_security


SERVER = Path(__file__).resolve().parents[1]
PACKAGE = "_hardening_backend"


def load_module(name, dependencies):
    package = types.ModuleType(PACKAGE)
    package.__path__ = [str(SERVER / 'server_advanced')]
    modules = {PACKAGE: package}
    for dependency, attributes in dependencies.items():
        module = types.ModuleType(dependency)
        module.__dict__.update(attributes)
        modules[dependency] = module
    spec = importlib.util.spec_from_file_location(
        f"{PACKAGE}.{name}", SERVER / "server_advanced" / (name.replace(".", "/") + ".py")
    )
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, modules):
        spec.loader.exec_module(module)
    return module


class LoggingHardeningTests(unittest.TestCase):
    def setUp(self):
        self.logs = load_module("logging_utils", {
            f"{PACKAGE}.config": {"REQUEST_LOG_FULL_DEBUG": False},
        })

    def test_credential_variants_are_redacted_even_in_debug(self):
        keys = [
            "PASSWORD", "newPassword", "old-password", "password_encrypted",
            "passwordHash", "passwd", "pwd", "pass", "passphrase", "auth",
            "Authorization", "Proxy-Authorization", "Cookie", "Set-Cookie",
            "X-API-Token", "X-App-Secret", "apiKey", "API.KEY", "access_token",
            "refreshToken", "fcmToken", "telegramBotToken", "registration_id",
            "registrationSecret", "inviteToken", "classmate_token",
            "verificationToken", "deviceToken", "relayDeviceToken", "serverToken",
            "FIREBASE_PRIVATE_KEY", "CF3_ENCRYPTION_KEY", "clientSecret",
            "JSESSIONID", "sessionCookies", "credentials", "verificationCode", "code",
        ]
        for debug in (False, True):
            self.logs.REQUEST_LOG_FULL_DEBUG = debug
            for key in keys:
                with self.subTest(debug=debug, key=key):
                    data = {"items": [{key: "credential-value", "subject": "Math"}]}
                    self.assertEqual(self.logs.redact_data(data), {
                        "items": [{key: "[REDACTED]", "subject": "Math"}]
                    })
                    self.assertEqual(data["items"][0][key], "credential-value")
                    self.assertEqual(self.logs.redact_headers({key: "credential-value"}), {
                        key: "[REDACTED]"
                    })

    def test_url_redacts_query_userinfo_and_fragment(self):
        url = "https://login:password@app.eschool.center/file?serverToken=one&serverToken=two&page=2#token=three"
        for debug in (False, True):
            self.logs.REQUEST_LOG_FULL_DEBUG = debug
            parts = urlsplit(self.logs.redact_url(url))
            self.assertEqual(parts.netloc, "app.eschool.center")
            self.assertEqual(parts.fragment, "")
            self.assertEqual(parse_qs(parts.query), {
                "serverToken": ["[REDACTED]", "[REDACTED]"], "page": ["2"]
            })
        self.assertEqual(self.logs.redact_url("https://[invalid/?token=secret"), "[REDACTED]")

    def test_serialized_and_opaque_bodies_do_not_leak(self):
        for debug in (False, True):
            self.logs.REQUEST_LOG_FULL_DEBUG = debug
            for body in ({"password": "secret"}, '{"password": "secret"}', b'{"password": "secret"}'):
                self.assertEqual(json.loads(self.logs.serialise_log_body(body)), {"password": "[REDACTED]"})
            for body in ("password=secret", "plain-secret", b"\xffsecret", '"secret"'):
                self.assertEqual(self.logs.serialise_log_body(body), "[REDACTED]")

    def test_request_and_debug_response_logging(self):
        self.logs.REQUEST_LOG_FULL_DEBUG = True
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.logs.log_request("POST", "https://example.test/?token=secret-value",
                                  {"Cookie": "secret-value"}, '{"password": "secret-value"}')
            self.logs.log_response(types.SimpleNamespace(
                url="https://example.test/", status_code=200,
                headers={"Set-Cookie": "secret-value"}, text='{"accessToken": "secret-value"}',
            ))
        self.assertNotIn("secret-value", output.getvalue())
        self.assertIn("[REDACTED]", output.getvalue())


class TelegramDownloadHardeningTests(unittest.TestCase):
    def setUp(self):
        self.bot = Mock()
        self.get = Mock(side_effect=AssertionError("Unexpected HTTP request"))
        self.log = Mock()
        from test_telegram_rich_messages import bot_module, apihelper
        self.module = bot_module(self.bot, self.get)
        self.module.log = self.log
        self.transport = patch.object(apihelper, '_make_request', side_effect=self.rich_upload)
        self.transport.start()
        self.addCleanup(self.transport.stop)
        self.module._MAX_ATTACHMENT_DOWNLOAD_BYTES = 8
        self.uploads = []

        def send_attachment(**kwargs):
            attachment = kwargs.get("document", kwargs.get("photo"))
            if isinstance(attachment, str):
                raise RuntimeError("secret-in-direct-error")
            self.uploads.append(attachment.read())

        self.bot.send_document.side_effect = send_attachment
        self.bot.send_photo.side_effect = send_attachment

    def rich_upload(self, token, method_name, **kwargs):
        self.uploads.extend(value[1].read() for value in (kwargs.get('files') or {}).values())
        return {'message_id': 1}

    def response(self, chunks=(b"abc",), status=200, headers=None):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status_code = status
        response.headers = headers or {}
        response.iter_content.return_value = iter(chunks)
        self.get.side_effect = None
        self.get.return_value = response
        return response

    def send(self, url="https://app.eschool.center/ec-server/file", image=False, credentials=True):
        return self.module.send_telegram_message(
            "bot-token", "user-id", "title", "body",
            attachments=[{"url": url, "name": "file.txt", "isImage": image}],
            attachment_headers={"User-Agent": "eSchoolMobile", "Cookie": "secret-cookie"} if credentials else None,
            attachment_cookies={"JSESSIONID": "secret-cookie"} if credentials else None,
        )

    def test_only_exact_https_origin_can_receive_credentials(self):
        urls = [
            "https://foreign.test/file", "http://app.eschool.center/file",
            "https://app.eschool.center.foreign.test/file", "https://sub.app.eschool.center/file",
            "https://app.eschool.center:444/file", "https://app.eschool.center./file",
            "https://app.eschool.center@foreign.test/file", "https://user@app.eschool.center/file",
            "https://app.eschool.center:bad/file", "https://app.eschool.center\\@foreign.test/file",
            "https://app.eschool.center\n.foreign.test/file", "//app.eschool.center/file",
            "file:///etc/passwd", "/ec-server/file", None,
        ]
        for url in urls:
            with self.subTest(url=url):
                self.assertTrue(self.send(url))
                self.get.assert_not_called()
        self.assertEqual(self.uploads, [])
        self.assertNotIn("secret-in-direct-error", str(self.log.call_args_list))

    def test_allowed_origin_streams_with_redirects_disabled(self):
        for url in ("https://app.eschool.center/file", "https://app.eschool.center:443/file"):
            for image in (False, True):
                with self.subTest(url=url, image=image):
                    response = self.response(chunks=(b"abcd", b"", b"efgh"))
                    self.assertTrue(self.send(url, image))
                    self.get.assert_called_with(
                        url, headers={"User-Agent": "eSchoolMobile", "Cookie": "secret-cookie"},
                        cookies={"JSESSIONID": "secret-cookie"}, timeout=30,
                        allow_redirects=False, stream=True,
                    )
                    self.assertEqual(self.uploads[-1], b"abcdefgh")
                    response.iter_content.assert_called_once_with(chunk_size=64 * 1024)
                    response.__exit__.assert_called_once()

    def test_redirect_responses_are_rejected_without_reading(self):
        for status in (301, 302, 303, 307, 308):
            for target in ("https://foreign.test/file", "https://app.eschool.center/other"):
                with self.subTest(status=status, target=target):
                    self.get.reset_mock()
                    response = self.response(status=status, headers={"Location": target})
                    self.send()
                    self.get.assert_called_once()
                    response.iter_content.assert_not_called()
                    response.__exit__.assert_called_once()
        self.assertEqual(self.uploads, [])

    def test_size_limit_checks_header_and_actual_decoded_stream(self):
        response = self.response(headers={"Content-Length": "9"})
        self.send()
        response.iter_content.assert_not_called()
        for headers in ({}, {"Content-Length": "1"}, {"Content-Encoding": "gzip"}):
            with self.subTest(headers=headers):
                consumed = []

                def chunks():
                    for chunk in (b"12345678", b"9", b"never-read"):
                        consumed.append(chunk)
                        yield chunk

                response = self.response(chunks=chunks(), headers=headers)
                self.send()
                self.assertEqual(consumed, [b"12345678", b"9"])
                response.__exit__.assert_called_once()
        self.assertEqual(self.uploads, [])

    def test_empty_error_and_interrupted_downloads_are_not_uploaded(self):
        for status, chunks in ((200, ()), (403, (b"error",))):
            response = self.response(status=status, chunks=chunks)
            self.send()
            response.__exit__.assert_called_once()
        response = self.response()
        response.iter_content.side_effect = RuntimeError("secret-in-download-error")
        self.send()
        response.__exit__.assert_called_once()
        self.assertEqual(self.uploads, [])
        self.assertNotIn("secret-in-download-error", str(self.log.call_args_list))

    def test_public_media_is_referenced_and_private_media_is_downloaded_once(self):
        self.send(credentials=False)
        self.get.assert_not_called()
        self.response(chunks=(b'file',))
        self.send()
        self.get.assert_called_once()
        self.assertEqual(self.uploads, [b'file'])

    def test_catchall_does_not_log_message_text(self):
        tree = ast.parse((SERVER / "server_advanced/telegram_bot.py").read_text())
        handler = next(node for node in ast.walk(tree) if isinstance(node, ast.FunctionDef) and node.name == "echo_handler")
        for call in ast.walk(handler):
            if isinstance(call, ast.Call) and isinstance(call.func, ast.Name) and call.func.id == "log":
                self.assertNotIn("message.text", ast.unparse(call))
                self.assertNotIn("new_pw", ast.unparse(call))


class VerificationLoggingHardeningTests(unittest.TestCase):
    def setUp(self):
        self.log = Mock()
        self.connection = Mock()
        self.connection.cursor.return_value.fetchone.return_value = None
        self.globals = {}
        self.request = types.SimpleNamespace(json={"token": "secret-token"})
        self.module = load_module("routes.verification", {
            "flask": {
                "Blueprint": lambda *args: types.SimpleNamespace(route=lambda *a, **kw: lambda fn: fn),
                "jsonify": lambda value: value, "request": self.request, "g": self.globals,
            },
            "requests": {"get": Mock(side_effect=AssertionError("Unexpected HTTP request"))},
            f"{PACKAGE}.config": {"UPLOAD_FOLDER": "/unused"},
            f"{PACKAGE}.logging_utils": {"log": self.log},
            f"{PACKAGE}.database": {
                "get_db_connection": Mock(return_value=self.connection),
                "invalidate_verified_user": Mock(),
            },
            f"{PACKAGE}.rate_limiter": {"rate_limit": lambda *args: lambda fn: fn},
            f"{PACKAGE}.eschool_api": {
                "server_state": types.SimpleNamespace(prs_id=900, cookies={"JSESSIONID": "secret-cookie"}),
                "get_messages": Mock(return_value=[]),
                "get_thread_messages": Mock(return_value=[]),
            },
        })

    def test_verification_code_is_not_logged(self):
        for code in ("secret-code", "A" * 32):
            self.assertEqual(self.module.find_verified_sender(code, 42),
                             (None, "Invalid or expired verification code"))
            self.assertNotIn(code, str(self.log.call_args_list))
        self.module.get_messages.assert_not_called()
        self.module.get_thread_messages.assert_not_called()
        self.module.requests.get.assert_not_called()

    def test_tokens_and_database_errors_are_not_logged(self):
        self.connection.cursor.return_value.execute.side_effect = RuntimeError("secret-token")
        for name in ("revoke_token", "delete_all_data", "list_devices", "check_verified_users"):
            with self.subTest(route=name):
                self.request.json["ids"] = [123]
                getattr(self.module, name)()
        self.globals['_verification_proof'] = {
            'prs_id': 123, 'target_prs_id': 900, 'code_hash': 'secret-hash',
            'full_name': 'Name', 'grade_class': 'Class',
        }
        self.assertEqual(self.module.issue_verification_token(123, "phone", "Name", "Class"),
                         (None, "Database error"))
        self.assertNotIn("secret-token", str(self.log.call_args_list))
        self.assertNotIn("secret-hash", str(self.log.call_args_list))
        self.assertIn("RuntimeError", str(self.log.call_args_list))


class RegistrationVerificationIntegrationTests(unittest.TestCase):
    def setUp(self):
        # берём настоящую базу challenge и настоящие хелперы проверки, а не заглушку с успехом
        self.verification = verification_security.VerificationSecurityTests()
        self.verification.setUp()
        self.verification.issue()
        self.verification.messages.return_value = [self.verification.valid_message()]
        self.user_cookies = {'JSESSIONID': 'secret-user-cookie'}
        self.profile = {
            'profile': {'prsBasic': {
                'prsId': 123, 'lastName': 'Authenticated', 'firstName': 'Student',
            }},
        }
        self.response = self.verification.allow_profile(self.profile)
        self.connection = Mock()
        self.connection.cursor.return_value.fetchone.return_value = (123, 'LegacyForgedClass')
        self.login = Mock(return_value=([], [], [], 'FirstNameOnly', self.user_cookies, 123))
        self.request = types.SimpleNamespace(json={
            'token': 'secret-verification-token', 'username': 'account', 'password': 'secret-password',
            'fullName': 'Forged Name', 'gradeClass': ' 9А ', 'deviceName': 'Phone',
        })
        self.issue_token = Mock(wraps=self.verification.module.issue_verification_token)
        self.module = load_module('routes.notifications', {
            f'{PACKAGE}.check_schedule': vars(load_module('check_schedule', {})),
            'flask': {
                'Blueprint': lambda *a: types.SimpleNamespace(route=lambda *a, **kw: lambda fn: fn),
                'jsonify': lambda value: value, 'request': self.request,
            },
            'requests': {'get': Mock(side_effect=AssertionError('Unexpected HTTP request'))},
            f'{PACKAGE}.database': {
                'get_db_connection': Mock(return_value=self.connection),
                'invalidate_classmate': Mock(),
                'invalidate_registration': Mock(),
                'json_value': lambda value: value,
                'remember_classmate_token': Mock(),
            },
            f'{PACKAGE}.config': {
                'BASE_URL': 'https://app.eschool.center/ec-server', 'USER_AGENT': 'eSchoolMobile',
                'MIN_CHECK_INTERVAL': 10, 'DEFAULT_CHECK_INTERVAL': 10,
            },
            f'{PACKAGE}.domain_manager': {name: Mock() for name in (
                'current_domain_status', 'get_domain_job', 'start_domain_job')},
            f'{PACKAGE}.ip_blacklist': {name: Mock() for name in ('get_ip_blacklist', 'set_ip_blacklist')},
            f'{PACKAGE}.tls_manager': {'tls_status': Mock()},
            f'{PACKAGE}.analysis': {},
            f'{PACKAGE}.rate_limiter': {'rate_limit': lambda *a: lambda fn: fn},
            f'{PACKAGE}.logging_utils': {'log': self.verification.log},
            f'{PACKAGE}.utils': {name: Mock() for name in (
                'sha256_hash', 'generate_random_string', 'get_random_device_model')},
            f'{PACKAGE}.routes.verification': {
                'find_verified_sender': self.verification.module.find_verified_sender,
                'get_verified_name': self.verification.module.get_verified_name,
                'normalize_grade_class': self.verification.module.normalize_grade_class,
                'issue_verification_token': self.issue_token,
            },
            f'{PACKAGE}.notification_delivery': {name: Mock() for name in (
                'save_notification_history',
                'send_notification_with_telegram', 'send_telegram_relogin_notice', 'get_telegram_info')},
            f'{PACKAGE}.telegram_bot': {name: Mock() for name in (
                'start_telegram_bot', 'stop_telegram_bot', 'restart_all_telegram_bots',
                'send_telegram_message', 'request_topic_detect', 'get_and_clear_detected_topic',
                'create_group_activation_code')},
            f'{PACKAGE}.encryption': {
                'init_encryption': Mock(return_value=True),
                'encrypt_password': Mock(return_value='encrypted-password'), 'decrypt_password': Mock(),
            },
            f'{PACKAGE}.keep_alive': {name: Mock() for name in (
                'update_session', 'get_session', 'mark_account_session_invalid')},
        })
        self.module.login_and_get_data = self.login

    def inline(self):
        self.request.json.pop('token', None)
        self.request.json.update(verificationCode=self.verification.code, verificationThreadId=42)

    def assert_scope(self):
        calls = self.connection.cursor.return_value.execute.call_args_list
        inserts = [params for (sql, params), _ in calls if 'INSERT INTO cf3_registrations' in sql]
        self.assertEqual(len(inserts), 1)
        self.assertEqual(inserts[0][2:4], ('Authenticated Student', '9А'))
        updates = [(sql, params) for (sql, params), _ in calls if 'UPDATE verified_users' in sql]
        self.assertEqual(len(updates), 1)
        self.assertIn('WHERE token = %s AND prs_id = %s', updates[0][0])
        self.assertEqual(updates[0][1], ('Authenticated Student', '9А', inserts[0][6], 123))

    def assert_no_registration(self):
        for call in self.connection.cursor.return_value.execute.call_args_list:
            self.assertNotIn('INSERT INTO cf3_registrations', call.args[0])
        self.assertEqual(self.verification.db.tokens, [])
        self.assertFalse(self.verification.db.challenges[self.verification.code_hash]['used'])

    def test_existing_token_verifies_name_and_normalizes_client_class(self):
        result = self.module.cf3_register()
        self.assertEqual(set(result), {'success', 'registrationId', 'registrationSecret'})
        self.assertTrue(result['success'])
        self.assert_scope()
        self.issue_token.assert_not_called()
        self.verification.http.assert_called_once_with(
            'https://app.eschool.center/ec-server/profile/getShortProfile',
            params={'prsId': 123}, cookies=self.user_cookies,
            headers={'Accept': 'application/json', 'User-Agent': 'eSchoolMobile'},
            timeout=15, allow_redirects=False,
        )

    def test_inline_proof_survives_login_and_authenticated_profile_then_consumes_once(self):
        self.inline()
        observed_proofs = []
        sender_profile = {'profile': {'prsBasic': {
            'prsId': 123, 'lastName': 'Sender', 'firstName': 'CachedName',
        }}}
        self.response.json.side_effect = [sender_profile, self.profile]

        def profile_lookup(*args, **kwargs):
            if kwargs['cookies'] == self.user_cookies:
                proof = self.verification.globals._verification_proof
                observed_proofs.append(proof)
                self.assertEqual(proof['prs_id'], 123)
                self.assertEqual(proof['full_name'], 'Sender CachedName')
                self.assertFalse(self.verification.db.challenges[self.verification.code_hash]['used'])
                self.issue_token.assert_not_called()
            return self.response

        self.verification.http.side_effect = profile_lookup
        self.assertTrue(self.module.cf3_register()['success'])
        self.assertEqual(len(observed_proofs), 1)
        self.issue_token.assert_called_once_with(123, 'Phone', None, '9А')
        self.assertFalse(hasattr(self.verification.globals, '_verification_proof'))
        self.assertEqual(len(self.verification.db.tokens), 1)
        self.assert_scope()
        logs = str(self.verification.log.call_args_list)
        for secret in (self.verification.code, self.verification.db.tokens[0][0], 'secret-password',
                       'secret-user-cookie', 'secret-verification-token'):
            self.assertNotIn(secret, logs)
        self.assertEqual(self.module.cf3_register()[1], 401)
        self.assertEqual(len(self.verification.db.tokens), 1)

    def test_inline_login_failure_or_account_mismatch_does_not_consume_challenge(self):
        self.inline()
        for login_result, status in (
            ((None,) * 6, 401), (([], [], [], 'Other', self.user_cookies, 456), 403),
        ):
            with self.subTest(status=status):
                self.login.return_value = login_result
                self.assertEqual(self.module.cf3_register()[1], status)
                self.issue_token.assert_not_called()
                self.assert_no_registration()

    def test_missing_malformed_or_mismatched_authenticated_profile_never_falls_back(self):
        for profile in ({}, {'profile': {}}, {'profile': {'prsBasic': []}},
                        {'profile': {'prsBasic': {'prsId': 123, 'firstName': 'Student'}}},
                        {'profile': {'prsBasic': {
                            **self.profile['profile']['prsBasic'], 'prsId': 456}}}):
            with self.subTest(profile=profile):
                self.response.json.return_value = profile
                self.assertEqual(self.module.cf3_register()[1], 503)
                self.assert_no_registration()

    def test_inline_authenticated_profile_failure_preserves_unused_challenge(self):
        self.inline()
        self.response.json.side_effect = [self.profile, {}]
        self.assertEqual(self.module.cf3_register()[1], 503)
        self.issue_token.assert_not_called()
        self.assert_no_registration()

    def test_inline_expiry_during_profile_lookup_prevents_registration(self):
        self.inline()

        def profile_lookup(*args, **kwargs):
            if kwargs['cookies'] == self.user_cookies:
                self.verification.db.now = self.verification.db.challenges[self.verification.code_hash]['expires']
            return self.response

        self.verification.http.side_effect = profile_lookup
        self.assertEqual(self.module.cf3_register()[1], 500)
        self.assert_no_registration()

    def test_invalid_token_and_registration_database_errors_do_not_log_secrets(self):
        self.connection.cursor.return_value.fetchone.return_value = None
        self.assertEqual(self.module.cf3_register()[1], 401)
        self.assertNotIn('secret-verification-token', str(self.verification.log.call_args_list))
        self.assertNotIn('secret-verification-token'[:8], str(self.verification.log.call_args_list))
        self.connection.cursor.return_value.fetchone.return_value = (123,)

        def execute(sql, params):
            if 'INSERT INTO cf3_registrations' in sql:
                raise RuntimeError('secret-password secret-verification-token')

        self.connection.cursor.return_value.execute.side_effect = execute
        self.assertEqual(self.module.cf3_register()[1], 500)
        logs = str(self.verification.log.call_args_list)
        self.assertIn('RuntimeError', logs)
        self.assertNotIn('secret-password', logs)
        self.assertNotIn('secret-verification-token', logs)


if __name__ == "__main__":
    unittest.main()
