"""проверяем cors прокси и поиск версии без настоящих аккаунтов и сети"""
import base64
import unittest
from unittest.mock import Mock
from flask import Flask, request, jsonify
from test_backend_hardening import PACKAGE, load_module


class WebProxyTests(unittest.TestCase):
    def setUp(self):
        import flask
        self.version = Mock(return_value='7.9.0')
        self.upstream = Mock()
        self.module = load_module('routes.proxy', {
            'flask': vars(flask),
            'requests': {'request': self.upstream, 'RequestException': ConnectionError},
            f'{PACKAGE}.config': {
                'BASE_URL': 'https://school.test/ec-server',
                'ALLOWED_CORS_ORIGINS': {'http://localhost:8085', 'http://127.0.0.1:8085'},
            },
            f'{PACKAGE}.logging_utils': {'log': Mock()},
            f'{PACKAGE}.eschool_api': {'get_eschool_version': self.version},
        })
        app = Flask(__name__)
        app.register_blueprint(self.module.bp)

        @app.before_request
        def auth():
            if request.method != 'OPTIONS' and request.headers.get('X-Api-Token') != 'test-token':
                return jsonify({'error': 'Unauthorized'}), 401

        self.client = app.test_client()

    def test_version_uses_server_resolver(self):
        response = self.client.get('/proxy/version', headers={'X-Api-Token': 'test-token'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json, {'version': '7.9.0'})
        self.version.assert_called_once_with()
        self.upstream.assert_not_called()

    def test_version_requires_authentication(self):
        response = self.client.get('/proxy/version')
        self.assertEqual(response.status_code, 401)
        self.version.assert_not_called()

    def test_both_preflights_allow_only_configured_origins(self):
        for route in ('/proxy', '/proxy/version'):
            for origin in ('http://localhost:8085', 'http://127.0.0.1:8085'):
                with self.subTest(route=route, origin=origin):
                    response = self.client.options(route, headers={'Origin': origin})
                    self.assertEqual(response.status_code, 204)
                    self.assertEqual(response.headers['Access-Control-Allow-Origin'], origin)
                    self.assertIn('GET', response.headers['Access-Control-Allow-Methods'])
                    self.assertIn('X-Api-Token', response.headers['Access-Control-Allow-Headers'])

    def test_unapproved_origins_do_not_get_cors_access(self):
        for origin in ('http://localhost:45073', 'https://evil.test', 'null'):
            response = self.client.options('/proxy/version', headers={'Origin': origin})
            self.assertEqual(response.status_code, 403)
            self.assertNotIn('Access-Control-Allow-Origin', response.headers)

    def test_auth_errors_have_cors_for_the_allowed_origin(self):
        for route in ('/proxy', '/proxy/version'):
            response = self.client.open(route, method='POST' if route == '/proxy' else 'GET',
                                        headers={'Origin': 'http://localhost:8085'})
            self.assertEqual(response.status_code, 401)
            self.assertEqual(response.headers['Access-Control-Allow-Origin'], 'http://localhost:8085')
            self.assertIn('Origin', response.headers['Vary'])

    def test_target_restriction_is_preserved(self):
        response = self.client.post('/proxy', json={'url': 'https://evil.test/'},
                                    headers={'X-Api-Token': 'test-token', 'Origin': 'http://localhost:8085'})
        self.assertEqual(response.status_code, 403)
        self.upstream.assert_not_called()

    def test_binary_response_preserves_bytes_and_session_cookie(self):
        content = b'\x89PNG\r\n\x00\xff\xfe'
        self.upstream.return_value = Mock(
            status_code=200, content=content,
            headers={'Content-Type': 'image/png', 'Set-Cookie': 'JSESSIONID=new; Path=/'},
        )
        response = self.client.post('/proxy', json={
            'url': 'https://school.test/ec-server/files/test',
            'headers': {'Cookie': 'JSESSIONID=old'},
            'responseEncoding': 'base64',
        }, headers={'X-Api-Token': 'test-token'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['bodyEncoding'], 'base64')
        self.assertEqual(base64.b64decode(response.json['body']), content)
        self.assertIn('JSESSIONID=new', response.json['headers']['Set-Cookie'])
        self.assertEqual(self.upstream.call_args.kwargs['headers']['Cookie'], 'JSESSIONID=old')
        self.assertFalse(self.upstream.call_args.kwargs['allow_redirects'])

    def test_binary_upload_is_forwarded_without_text_conversion(self):
        content = b'--boundary\r\n\x00\xff\xfe\r\n--boundary--'
        self.upstream.return_value = Mock(status_code=200, headers={}, text='1')
        response = self.client.post('/proxy', json={
            'url': 'https://school.test/ec-server/chat/sendNew', 'method': 'POST',
            'bodyBase64': base64.b64encode(content).decode(),
            'headers': {'Content-Type': 'multipart/form-data; boundary=boundary'},
        }, headers={'X-Api-Token': 'test-token'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.upstream.call_args.kwargs['data'], content)
        self.assertEqual(response.json['body'], '1')
        self.assertNotIn('bodyEncoding', response.json)

    def test_invalid_binary_upload_is_rejected_before_forwarding(self):
        for value in ('not base64!', 1, None):
            response = self.client.post('/proxy', json={
                'url': 'https://school.test/ec-server/chat/sendNew', 'bodyBase64': value,
            }, headers={'X-Api-Token': 'test-token'})
            self.assertEqual(response.status_code, 400)
        self.upstream.assert_not_called()


if __name__ == '__main__':
    unittest.main()
