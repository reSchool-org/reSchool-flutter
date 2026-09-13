"""проверяем доступ, хранение и браузерные формы сервиса звонков"""
import copy
import os
import re
import tempfile
import unittest
from unittest.mock import patch

from server_advanced.app import app
from server_advanced.routes import bell_time


class BellTimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.env = patch.dict(os.environ, {'RESCHOOL_RUNTIME_DIR': self.temp.name})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.key = patch.object(bell_time, 'API_TOKEN', 'test-only-bell-key')
        self.key.start()
        self.addCleanup(self.key.stop)
        self.limit = patch('server_advanced.rate_limiter.rate_limiter.is_allowed', return_value=True)
        self.limit.start()
        self.addCleanup(self.limit.stop)
        app.config['TESTING'] = True
        self.client = app.test_client()

    def login(self):
        return self.client.post('/time/login', json={'apiToken': 'test-only-bell-key'},
                                headers={'X-Bell-Login': '1', 'X-Forwarded-For': '203.0.113.20'},
                                base_url='https://localhost')

    def payload(self):
        return copy.deepcopy(bell_time.DEFAULTS)

    def test_public_json_is_independent_of_api_auth_and_no_store(self):
        response = self.client.get('/time', headers={'Accept': 'application/json'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json['timezone'], 'Europe/Moscow')
        self.assertIsInstance(response.json['serverTimeMs'], int)
        self.assertEqual(response.headers['Cache-Control'], 'no-store')
        self.assertEqual(response.headers['Access-Control-Allow-Origin'], '*')
        self.assertEqual(set(response.json['presets']), set(bell_time.CAMPUSES))
        self.assertNotIn('csrf', response.json)

    def test_browser_requires_login_and_cookie_is_scoped(self):
        response = self.client.get('/time', headers={'Accept': 'text/html'})
        self.assertIn('id="login"', response.text)
        self.assertNotIn('id="editor"', response.text)
        response = self.login()
        self.assertEqual(response.status_code, 200)
        cookie = response.headers['Set-Cookie']
        for flag in ('Secure', 'HttpOnly', 'SameSite=Strict', 'Path=/time', 'Max-Age=2592000'):
            self.assertIn(flag, cookie)
        self.assertNotIn('test-only-bell-key', cookie)
        page = self.client.get('/time', headers={'Accept': 'text/html'}, base_url='https://localhost')
        self.assertIn('id="editor"', page.text)
        self.assertIn('frame-ancestors', page.headers['Content-Security-Policy'])
        # вход в редактор звонков не даёт прав администратора общего api
        self.assertIn(self.client.get('/auth-check').status_code, (401, 503))

    def test_rejects_wrong_unicode_key_and_cross_site_form(self):
        self.assertEqual(self.client.post('/time/login', json={'apiToken': 'не ключ'},
                         headers={'X-Bell-Login': '1'}).status_code, 401)
        self.assertEqual(self.client.post('/time/login', data={'apiToken': 'test-only-bell-key'}).status_code, 403)
        self.assertEqual(self.client.put('/time', json=self.payload()).status_code, 401)

    def test_cookie_write_requires_csrf_then_persists_and_logout_revokes_cookie(self):
        self.login()
        page = self.client.get('/time', headers={'Accept': 'text/html'}, base_url='https://localhost')
        csrf = re.search(r'const csrf = "([^"]+)"', page.text).group(1)
        payload = self.payload()
        payload['presets'][bell_time.CAMPUSES[0]]['offsetSeconds'] = -15
        self.assertEqual(self.client.put('/time', json=payload).status_code, 401)
        saved = self.client.put('/time', json=payload, headers={'X-CSRF-Token': csrf})
        self.assertEqual(saved.status_code, 200)
        self.assertEqual(saved.json['revision'], 2)
        self.assertTrue(bell_time._path().is_file())
        self.assertEqual(self.client.get('/time').json['presets'][bell_time.CAMPUSES[0]]['offsetSeconds'], -15)
        self.assertEqual(self.client.post('/time/logout', headers={'X-CSRF-Token': csrf}).status_code, 200)
        self.assertEqual(self.client.put('/time', json=payload, headers={'X-CSRF-Token': csrf}).status_code, 401)

    def test_stale_edit_is_rejected(self):
        headers = {'X-API-Token': 'test-only-bell-key'}
        self.assertEqual(self.client.put('/time', json=self.payload(), headers=headers).status_code, 200)
        self.assertEqual(self.client.put('/time', json=self.payload(), headers=headers).status_code, 409)

    def test_invalid_edits_leave_data_unchanged(self):
        for value in ('25:00', '08:50<script>', '12:70', None):
            payload = self.payload()
            payload['presets'][bell_time.CAMPUSES[0]]['lessons']['1']['start'] = value
            self.assertEqual(self.client.put('/time', json=payload,
                             headers={'X-API-Token': 'test-only-bell-key'}).status_code, 400)
        payload = self.payload()
        payload['presets'][bell_time.CAMPUSES[0]]['offsetSeconds'] = True
        self.assertEqual(self.client.put('/time', json=payload,
                         headers={'X-API-Token': 'test-only-bell-key'}).status_code, 400)
        self.assertEqual(self.client.get('/time').json['revision'], 1)

    def test_login_is_rate_limited(self):
        with patch('server_advanced.rate_limiter.rate_limiter.is_allowed', return_value=False), \
             patch('server_advanced.rate_limiter.rate_limiter.get_retry_after', return_value=60):
            self.assertEqual(self.login().status_code, 429)


if __name__ == '__main__':
    unittest.main()
