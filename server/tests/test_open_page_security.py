"""обработчик /open проверяем с подменёнными зависимостями без сети"""

from html.parser import HTMLParser
import types
import unittest
from unittest.mock import Mock
from urllib.parse import parse_qs, quote, unquote, urlencode, urlsplit

from test_backend_hardening import PACKAGE, load_module


class PageParser(HTMLParser):
    def __init__(self, html):
        super().__init__(convert_charrefs=True)
        self.tags = []
        self.fields = {}
        self.field = None
        self.href = None
        self.refresh = None
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        self.tags.append((tag, tuple(sorted(attrs))))
        if tag == 'span':
            self.field = attrs.get('class')
            self.fields[self.field] = ''
        if tag == 'a' and attrs.get('class') == 'btn':
            self.href = attrs['href']
        if tag == 'meta' and attrs.get('http-equiv') == 'refresh':
            self.refresh = attrs['content']

    def handle_endtag(self, tag):
        if tag == 'span':
            self.field = None

    def handle_data(self, data):
        if self.field is not None:
            self.fields[self.field] += data


class OpenPageSecurityTests(unittest.TestCase):
    def setUp(self):
        self.request = types.SimpleNamespace(args={})
        self.module = load_module('routes.homework', {
            'flask': {
                'Blueprint': lambda *a: types.SimpleNamespace(route=lambda *a, **kw: lambda fn: fn),
                'request': self.request, 'g': types.SimpleNamespace(),
                'jsonify': Mock(), 'send_file': Mock(), 'render_template_string': Mock(),
            },
            'requests': {},
            'werkzeug': {},
            'werkzeug.utils': {'secure_filename': Mock()},
            f'{PACKAGE}.cache': {},
            f'{PACKAGE}.analysis': {},
            f'{PACKAGE}.database': {name: Mock() for name in (
                'cache_verified_user', 'get_cached_verified_user', 'get_db_connection',
                'homework_version', 'invalidate_homework', 'load_user_session')},
            f'{PACKAGE}.config': {
                'UPLOAD_FOLDER': '/unused', 'MAX_FILE_SIZE': 1024,
                'MAX_FILES_PER_HOMEWORK': 5, 'BASE_URL': 'https://example.test',
                'USER_AGENT': 'test', 'get_public_base_url': Mock(),
            },
            f'{PACKAGE}.rate_limiter': {'rate_limit': lambda *a: lambda fn: fn},
            f'{PACKAGE}.logging_utils': {'log': Mock()},
            f'{PACKAGE}.utils': {'allowed_file': Mock()},
            f'{PACKAGE}.eschool_api': {'server_state': {}},
            f'{PACKAGE}.keep_alive': {'get_session': Mock()},
            f'{PACKAGE}.routes.notifications': {'_notify_classmates': Mock()},
        })

    def render(self, **params):
        # моделируем декодирование параметров, маршрут дополнительно декодирует предмет
        self.request.args = {key: values[0] for key, values in
                             parse_qs(urlencode(params), keep_blank_values=True).items()}
        html, status, headers = self.module.open_in_app()
        self.assertEqual(status, 200)
        self.assertEqual(headers['Content-Type'], 'text/html; charset=utf-8')
        return html, PageParser(html)

    def assert_diary_link(self, html, page, subject, date):
        expected = f'reschool://diary?date={quote(date)}&subject={quote(subject)}'
        self.assertEqual(page.href, expected)
        self.assertIsNone(page.refresh)
        self.assertIn('window.location.href = openLink.href;', html)
        self.assertEqual(parse_qs(urlsplit(page.href).query, keep_blank_values=True),
                         {'date': [date], 'subject': [subject]})

    def test_markup_and_encoded_markup_remain_text(self):
        _, baseline = self.render(subject='Math', date='invalid')
        payloads = (
            '<img src=x onerror=alert(1)>',
            '</span><script>alert(1)</script><span>',
            '<svg onload=alert(1)>',
            '\"><iframe srcdoc="<script>alert(1)</script>"></iframe>',
            '&lt;img src=x onerror=alert(1)&gt;',
            '{{ 7 * 7 }} & "quotes" \'single\'',
        )
        for value in payloads:
            for payload in (value, quote(value, safe='')):
                for field in ('subject', 'date'):
                    with self.subTest(field=field, payload=payload):
                        params = {'subject': 'Math', 'date': 'invalid', field: payload}
                        html, page = self.render(**params)
                        self.assertEqual(page.tags, baseline.tags)
                        self.assertEqual(page.fields['info-subject'], unquote(params['subject']))
                        self.assertEqual(page.fields['info-date'], params['date'])
                        self.assert_diary_link(html, page, params['subject'], params['date'])

    def test_localized_date_and_subject_punctuation_are_preserved(self):
        subject = 'Русский & литература / "Чтение" <5> + 100%'
        html, page = self.render(subject=subject, date='2026-03-27')
        self.assertEqual(page.fields['info-subject'], subject)
        self.assertEqual(page.fields['info-date'], '27 марта 2026')
        self.assert_diary_link(html, page, subject, '2026-03-27')

    def test_empty_defaults_are_preserved(self):
        html, page = self.render()
        self.assertEqual(page.fields['info-subject'], 'Предмет')
        self.assertEqual(page.fields['info-date'], '')
        self.assert_diary_link(html, page, '', '')

    def test_invalid_date_and_extra_subject_decode_are_preserved(self):
        subject = quote('История & общество', safe='')
        html, page = self.render(subject=subject, date='2026-02-30')
        self.assertEqual(page.fields['info-subject'], 'История & общество')
        self.assertEqual(page.fields['info-date'], '2026-02-30')
        self.assert_diary_link(html, page, subject, '2026-02-30')

    def test_link_device_keeps_encoded_parameters_and_static_card(self):
        _, baseline = self.render(type='link-device')
        values = {'server': 'https://example.test/path?a=1&b=2',
                  'token': '\"</script><svg onload=alert(1)>&secret',
                  'interval': '10&subject=<img src=x onerror=alert(1)>'}
        html, page = self.render(type='link-device', **values)
        self.assertEqual(page.tags, baseline.tags)
        self.assertEqual(page.fields, baseline.fields)
        self.assertEqual(urlsplit(page.href).netloc, 'link-device')
        self.assertEqual(parse_qs(urlsplit(page.href).query),
                         {key: [value] for key, value in values.items()})
        self.assertIsNone(page.refresh)
        self.assertIn('window.location.href = openLink.href;', html)


if __name__ == '__main__':
    unittest.main()
