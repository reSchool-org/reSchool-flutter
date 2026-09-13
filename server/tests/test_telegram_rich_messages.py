import ast
import io
import json
from datetime import datetime, timezone
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

from test_backend_hardening import PACKAGE, SERVER, load_module

from telebot import TeleBot, apihelper
from telebot import types as telegram_types
import requests


formatting = load_module('telegram_formatting', {})
delivery = load_module('telegram_delivery', {
    'telebot': {'apihelper': apihelper},
    'telebot.types': {'InputRichMessage': telegram_types.InputRichMessage},
    f'{PACKAGE}.telegram_formatting': vars(formatting),
})


def rejection(code=400, description="Bad Request: can't parse rich message"):
    return apihelper.ApiTelegramException('sendRichMessage', None, {
        'ok': False, 'error_code': code, 'description': description,
    })


def bot_module(bot, http_get=None):
    return load_module('telegram_bot', {
        'requests': {'get': http_get or Mock(side_effect=AssertionError('Unexpected request'))},
        'telebot': {'TeleBot': Mock(return_value=bot)},
        'telebot.types': {name: getattr(telegram_types, name) for name in (
            'Message', 'InlineKeyboardMarkup', 'InlineKeyboardButton', 'ReplyParameters', 'CopyTextButton')},
        f'{PACKAGE}.telegram_formatting': vars(formatting),
        f'{PACKAGE}.telegram_delivery': {'send_card': delivery.send_card, 'edit_card': delivery.edit_card},
        f'{PACKAGE}.config': {'API_TOKEN': '', 'USER_AGENT': 'Test', 'get_public_base_url': Mock(return_value='https://school.test')},
        f'{PACKAGE}.logging_utils': {'log': Mock()},
        f'{PACKAGE}.database': {'get_db_connection': Mock(), 'load_user_session': Mock(return_value=None)},
        f'{PACKAGE}.chat_notifications': {'fetch_threads': Mock(), 'ChatSessionExpired': type('ChatSessionExpired', (Exception,), {})},
        f'{PACKAGE}.notification_delivery': {},
        f'{PACKAGE}.encryption': {'decrypt_password': Mock(), 'init_encryption': Mock()},
    })


class FormattingTests(unittest.TestCase):
    def test_external_text_cannot_create_buttons_links_or_formatting(self):
        value = '**Автор** [ссылка](https://evil.test) <tg-button data="evil">жми</tg-button> $USD'
        card = formatting.Card(value).text(value)
        rich, plain = card.pages()[0]
        self.assertNotIn('<tg-button', rich)
        self.assertNotIn('**Автор**', rich)
        self.assertNotIn('[ссылка](https://evil.test)', rich)
        self.assertIn(value, plain)

    def test_homework_keeps_text_and_renders_math(self):
        text = '<p>Решите \\(x^2 + y^2 = 25\\).</p><p>Проверьте 2 &lt; 3.</p><script>secret()</script>'
        card = formatting.homework([{'subject': 'Алгебра', 'text': text, 'hasFiles': True}], datetime(2026, 9, 11))
        rich, plain = card.pages()[0]
        self.assertIn('11 сентября, пятница', plain)
        self.assertIn('<tg-math>x^2 + y^2 = 25</tg-math>', rich)
        self.assertIn('2 < 3', plain)
        self.assertNotIn('secret()', rich)
        self.assertIn('Вложения доступны', plain)

    def test_school_html_preserves_tables_and_emphasis_without_external_attributes(self):
        text = '<p><b>Сравните</b> значения</p><table onclick="evil()"><tr><th>x</th><th>y</th></tr><tr><td>2</td><td>4</td></tr></table>'
        rich, plain = formatting.homework([{'text': text}], datetime(2026, 9, 11)).pages()[0]
        self.assertIn('<table striped compact>', rich)
        self.assertIn('<b>Сравните</b>', rich)
        self.assertNotIn('onclick', rich)
        self.assertNotIn('evil()', rich)
        self.assertIn('2', plain)

    def test_very_long_homework_is_complete_and_each_page_is_bounded(self):
        text = ('🙂 Упражнение < & > * _ |\n' * 8000) + 'КОНЕЦ'
        pages = formatting.homework([{'subject': 'Литература', 'text': text}], datetime(2026, 9, 11)).pages()
        self.assertGreater(len(pages), 1)
        combined = ''.join(plain for rich, plain in pages)
        self.assertEqual(combined.count('🙂'), 8000)
        self.assertIn('КОНЕЦ', combined)
        for rich, plain in pages:
            self.assertLessEqual(len(rich.encode()), formatting.RICH_PAGE_BYTES + 100)
            self.assertEqual(rich.count('<details>'), rich.count('</details>'))

    def test_quotes_contain_real_author_and_no_injected_markup(self):
        card = formatting.notification('ignored', '<b>Текст</b>\nСледующая строка', 'message', {
            'sender': 'Мария * Иванова', 'subject': '8 А', 'sent_at': 1800000000000,
        })
        rich, plain = card.pages()[0]
        self.assertIn('Мария * Иванова', plain)
        self.assertIn('<blockquote expandable>', rich)
        self.assertIn('&lt;b&gt;Текст&lt;/b&gt;', rich)
        self.assertIn('<tg-time unix="1800000000"', rich)

    def test_conversation_preview_never_attributes_creator_as_author(self):
        card = formatting.messages([{'subject': 'Класс', 'sender': 'Администратор', 'preview': 'Добрый день'}])
        rich, plain = card.pages()[0]
        self.assertNotIn('Администратор', plain)
        self.assertIn('Добрый день', plain)

    def test_conversation_titles_remain_visible_for_blank_html_and_private_dialogs(self):
        items = [
            {'dlgType': 1, 'subject': ' ', 'contactName': '<b>Мария Ивановна</b>', 'preview': '<p>Добрый день</p>'},
            {'dlgType': 2, 'subject': '<span>&nbsp;\u200b</span>', 'contactName': 'Создатель', 'preview': '\n', 'attachmentCount': 2},
            {'subject': '\t\n', 'date': 1800000000000},
        ]
        rich, plain = formatting.messages(items).pages()[0]
        self.assertIn('1. Мария Ивановна\nДобрый день', plain)
        self.assertIn('2. Групповая беседа без названия\nВложения: 2', plain)
        self.assertIn('3. Личная беседа\nТекст сообщения недоступен.', plain)
        self.assertNotIn('Создатель', plain)
        self.assertNotIn('### ', rich)

    def test_conversation_time_uses_last_activity_and_readable_fallback(self):
        latest = int(datetime(2026, 9, 10, 18, 38, tzinfo=timezone.utc).timestamp() * 1000)
        card = formatting.messages([{'subject': 'Класс', 'preview': 'Добрый день',
                                    'date': latest - 86400000, 'displayDate': latest, 'unreadCount': 2}])
        rich, plain = card.pages()[0]
        self.assertIn('10.09.2026 21:38 МСК', plain)
        self.assertIn(f'unix="{latest // 1000}"', rich)
        self.assertIn('Непрочитанных: 2', plain)
        self.assertNotIn('UTC', plain)
        self.assertNotIn('09.09.2026', plain)

    def test_conversation_previews_are_bounded_and_external_markup_is_escaped(self):
        rich, plain = formatting.messages([{'subject': '[ссылка](https://evil.test)',
                                          'preview': '<p>' + 'Текст ' * 2000 + '</p><script>secret()</script>'}]).pages()[0]
        self.assertLess(len(rich), 1000)
        self.assertIn('…', plain)
        self.assertNotIn('secret()', rich)
        self.assertNotIn('[ссылка](https://evil.test)', rich)

    def test_conversation_pages_cover_the_whole_list_without_empty_tail(self):
        items = [{'subject': f'Беседа {i}', 'preview': 'Текст'} for i in range(1, 70)]
        for page in range(14):
            card = formatting.messages(items, offset=page * 5)
            self.assertEqual(len(card.pages()), 1)
            plain = card.pages()[0][1]
            for i in range(page * 5 + 1, min((page + 1) * 5, 69) + 1):
                self.assertIn(f'{i}. Беседа {i}\nТекст', plain)
        last = formatting.messages(items, offset=100000).pages()[0][1]
        self.assertIn('Беседы 66-69 из 69', last)
        self.assertNotIn('доступны в reSchool', last)

    def test_grade_table_preserves_zero_and_all_marks(self):
        card = formatting.grades([{'subject': 'Физика <1>', 'grades': ['5+', '4', 'н'], 'average': 0,
                                  'final': '5', 'rating': 0}], 'I четверть')
        rich, plain = card.pages()[0]
        self.assertIn('<table striped compact>', rich)
        self.assertIn('0.00', rich)
        self.assertIn('Физика &lt;1&gt;', rich)
        self.assertIn('<details>', rich)
        self.assertIn('5+ · 4 · н', plain)
        self.assertIn('Рейтинг: 0', plain)

    def test_analysis_has_estimate_and_mobile_task_blocks_without_duplicate_summary(self):
        card = formatting.notification('📚 ДЗ: Физика', 'Дата: 11.09.2026\nРешить № 5\n⏱ примерно 20 мин', 'homework',
            {'date': '2026-09-11'}, {'estimable': True, 'total_minutes': 20, 'range_min': 15, 'range_max': 25,
             'items': [{'label': '№ 5', 'minutes': 20, 'difficulty': 3}]})
        rich, plain = card.pages()[0]
        self.assertIn(r'**Примерное время** · 20 мин · диапазон 15\-25 мин', rich)
        self.assertNotIn('==', rich)
        self.assertIn('**1\\. № 5**<br>⏱ 20 мин · Сложность: 3/5', rich)
        self.assertNotIn('<table', rich)
        self.assertNotIn('⏱ примерно', plain)
        self.assertIn('Решить № 5', plain)

    def test_custom_homework_separates_author_task_and_estimate(self):
        rich, plain = formatting.notification('Новое кастомное ДЗ: Русский язык',
            'упр 6\nВыписать ключевые слова', 'homework',
            {'date': '2026-09-14', 'author': 'Иван Иванов', 'attachmentCount': 1},
            {'estimable': True, 'total_minutes': 25, 'range_min': 18, 'range_max': 35,
             'items': [{'label': 'Упражнение 6', 'minutes': 25, 'difficulty': 4}]}).pages()[0]
        self.assertIn('**Автор** · Иван Иванов\n\n', rich)
        self.assertIn('**📎 Вложений** · 1\n\n', rich)
        self.assertIn('### 📝 Задание\n\nупр 6<br>Выписать ключевые слова', rich)
        self.assertIn('### ⏱ План работы', rich)
        self.assertIn('**1\\. Упражнение 6**<br>⏱ 25 мин · Сложность: 4/5', rich)
        self.assertEqual(plain.count('14 сентября 2026'), 1)
        self.assertNotIn('Дата урока:', plain)
        self.assertNotIn('сложнее всего', plain)
        self.assertIn('упр 6\nВыписать ключевые слова', plain)

    def test_preserved_homework_lines_do_not_change_multiline_math_or_allow_html_injection(self):
        rich, plain = formatting.Card('ДЗ').text(
            'Первая строка\nВторая строка\n\\[x +\ny\\]\n<tg-button>кнопка</tg-button>',
            formulas=True, keep_lines=True).pages()[0]
        self.assertIn('Первая строка<br>Вторая строка<br>', rich)
        self.assertIn('<tg-math>x +\ny</tg-math>', rich)
        self.assertNotIn('<tg-button>', rich)

    def test_branded_footer_links_to_official_channel_and_escapes_external_text(self):
        rich, plain = formatting.Card('ДЗ').footer('reSchool · <b>Дневник</b>').pages()[0]
        self.assertIn('<footer><a href="https://t.me/reSchool_off">reSchool</a> · &lt;b&gt;Дневник&lt;/b&gt;</footer>', rich)
        self.assertIn('https://t.me/reSchool_off', plain)

    def test_unknown_estimate_is_not_invented(self):
        rich, plain = formatting.notification('ДЗ', 'Выучить стих', 'homework', analysis={
            'estimable': False, 'unestimable_reason': 'Нет текста стихотворения'}).pages()[0]
        self.assertIn('Нет текста стихотворения', plain)
        self.assertNotIn('Примерное время', rich)

    def test_large_tables_stay_under_block_limit(self):
        pages = formatting.Card('Предметы').table(('А', 'Б'), [('1', '2')] * 1500).pages()
        self.assertGreater(len(pages), 1)
        self.assertEqual(sum(r.count('<td>1</td>') for r, p in pages), 1500)
        self.assertTrue(all(r.count('<tr>') < 300 for r, p in pages))

    def test_long_plain_notice_is_not_truncated_as_title(self):
        text = 'А' * 5000 + 'КОНЕЦ'
        self.assertIn('КОНЕЦ', formatting.notice(text).pages()[0][1])

    def test_help_has_collapsible_settings_and_commands(self):
        rich, plain = formatting.welcome(True).pages()[0]
        self.assertGreaterEqual(rich.count('<details>'), 3)
        for command in ('/dz', '/grades', '/messages', '/period', '/passwd', '/activate'):
            self.assertIn(command, plain)
        self.assertNotIn('Powered by', rich)


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.bot = TeleBot('123:TEST', threaded=False)
        self.calls = []
        self.patch = patch.object(apihelper, '_make_request', side_effect=self.record)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def record(self, token, method_name, **kwargs):
        params = kwargs.get('params', {})
        request = {'method': method_name, 'params': dict(params)}
        if 'rich_message' in params:
            request['rich'] = json.loads(params['rich_message'])
        request['files'] = {key: (value[0], value[1].read()) if isinstance(value, tuple) else (
            getattr(value, 'name', key), value.read()) for key, value in (kwargs.get('files') or {}).items()}
        self.calls.append(request)
        return {'message_id': 17, 'date': 1800000000, 'chat': {'id': 55, 'type': 'private'}}

    def test_real_sdk_serializes_rich_markdown_and_topic(self):
        markup = telegram_types.InlineKeyboardMarkup().add(
            telegram_types.InlineKeyboardButton('Открыть', url='https://school.test', style='primary'))
        result = delivery.send_card(self.bot, -100, formatting.Card('Заголовок').text('Текст'),
                                    message_thread_id=7, reply_markup=markup)
        self.assertTrue(result.rich)
        self.assertEqual(self.calls[0]['method'], 'sendRichMessage')
        self.assertEqual(self.calls[0]['params']['message_thread_id'], 7)
        self.assertEqual(self.calls[0]['rich']['markdown'], '## Заголовок\n\nТекст')
        self.assertEqual(json.loads(self.calls[0]['params']['reply_markup'])['inline_keyboard'][0][0]['style'], 'primary')

    def test_homework_general_chat_payload_has_plain_time_and_linked_footer(self):
        card = formatting.notification('📚 ДЗ: Геометрия', 'Решить задачи с фото 📎', 'homework',
            {'date': '2026-09-10'}, {'total_minutes': 30, 'range_min': 20, 'range_max': 45})
        delivery.send_card(self.bot, -100, card)
        sent = self.calls[0]
        self.assertNotIn('message_thread_id', sent['params'])
        self.assertIn(r'30 мин · диапазон 20\-45 мин', sent['rich']['markdown'])
        self.assertNotIn('==', sent['rich']['markdown'])
        self.assertIn('<footer><a href="https://t.me/reSchool_off">reSchool</a></footer>', sent['rich']['markdown'])

    def test_footer_link_survives_html_fallback_for_send_and_edit(self):
        original = self.record
        def reject_rich(token, method_name, **kwargs):
            if 'rich_message' in kwargs.get('params', {}):
                raise rejection()
            return original(token, method_name, **kwargs)
        apihelper._make_request.side_effect = reject_rich
        card = formatting.Card('ДЗ').text('<a href="https://evil.test">Текст</a>').footer()
        delivery.send_card(self.bot, -100, card)
        delivery.edit_card(self.bot, -100, 17, card)
        self.assertEqual([call['method'] for call in self.calls], ['sendMessage', 'editMessageText'])
        for call in self.calls:
            html = call['params']['text']
            self.assertIn('<a href="https://t.me/reSchool_off">reSchool</a>', html)
            self.assertNotIn('<a href="https://evil.test">', html)

    def test_explicit_rejection_falls_back_safely_without_losing_emoji_or_text(self):
        original = self.record
        def reject_rich(token, method_name, **kwargs):
            if method_name == 'sendRichMessage':
                raise rejection()
            return original(token, method_name, **kwargs)
        apihelper._make_request.side_effect = reject_rich
        text = '🙂 < & >\n' * 1500 + 'КОНЕЦ'
        delivery.send_card(self.bot, 55, formatting.Card('ДЗ').text(text), message_thread_id=9)
        self.assertTrue(self.calls)
        self.assertTrue(all(c['method'] == 'sendMessage' for c in self.calls))
        self.assertTrue(all(c['params']['message_thread_id'] == 9 for c in self.calls))
        from html import unescape
        decoded = ''.join(unescape(c['params']['text']) for c in self.calls)
        self.assertEqual(decoded.count('🙂'), 1500)
        self.assertIn('КОНЕЦ', decoded)
        for call in self.calls:
            text = call['params']['text'].replace('<b>', '').replace('</b>', '')
            self.assertLessEqual(len(unescape(text).encode('utf-16-le')) // 2, 4096)

    def test_ambiguous_network_error_and_rate_limit_never_trigger_fallback(self):
        for error in (requests.ReadTimeout('token must not leak'), rejection(429, 'Too Many Requests'), rejection(403, 'Forbidden')):
            with self.subTest(error=type(error).__name__):
                apihelper._make_request.reset_mock()
                apihelper._make_request.side_effect = error
                with self.assertRaises(type(error)):
                    delivery.send_card(self.bot, 55, formatting.Card('Текст'))
                self.assertEqual(apihelper._make_request.call_count, 1)

    def test_navigation_edits_rich_message_in_place(self):
        delivery.edit_card(self.bot, 55, 17, formatting.homework([], datetime(2026, 9, 11)))
        self.assertEqual([c['method'] for c in self.calls], ['editMessageText'])
        self.assertIn('rich_message', self.calls[0]['params'])
        self.assertNotIn('parse_mode', self.calls[0]['params'])

    def test_unchanged_navigation_is_a_noop(self):
        apihelper._make_request.side_effect = rejection(400, 'Bad Request: message is not modified')
        self.assertIsNone(delivery.edit_card(self.bot, 55, 17, formatting.Card('ДЗ')))
        self.assertEqual(apihelper._make_request.call_count, 1)

    def test_images_and_documents_are_embedded_in_one_multipart_request(self):
        module = bot_module(self.bot)
        with tempfile.TemporaryDirectory() as directory:
            photo = Path(directory) / 'photo.jpg'
            document = Path(directory) / 'task.pdf'
            photo.write_bytes(b'photo-data')
            document.write_bytes(b'pdf-data')
            ok = module.send_telegram_message('123:TEST', '-100', 'Физика', 'Текст задания',
                attachments=[{'path': str(photo), 'name': '№ 4', 'isImage': True},
                             {'path': str(document), 'name': 'Задание.pdf', 'isImage': False}],
                notification_type='homework', message_thread_id=7)
        self.assertTrue(ok)
        self.assertEqual(len(self.calls), 1)
        request = self.calls[0]
        self.assertEqual(request['method'], 'sendRichMessage')
        self.assertEqual(request['params']['message_thread_id'], 7)
        self.assertIn('tg://photo?id=media0', request['rich']['markdown'])
        self.assertIn('tg://document?id=media1', request['rich']['markdown'])
        self.assertEqual(request['files']['media0'][1], b'photo-data')
        self.assertEqual(request['files']['media1'][1], b'pdf-data')
        self.assertEqual(request['rich']['media'][1]['media'], {'type': 'document', 'media': 'attach://media1'})

    def test_two_photos_form_collage_and_buffers_are_closed(self):
        response = Mock()
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock()
        response.status_code = 200
        response.headers = {}
        response.iter_content.side_effect = lambda **k: iter([b'photo'])
        get = Mock(return_value=response)
        module = bot_module(self.bot, get)
        streams = []
        original = self.record
        def record(token, method_name, **kwargs):
            streams.extend(v[1] for v in (kwargs.get('files') or {}).values())
            return original(token, method_name, **kwargs)
        apihelper._make_request.side_effect = record
        ok = module.send_telegram_message('123:TEST', '55', 'ДЗ', 'Текст', attachments=[
            {'url': 'https://app.eschool.center/file/1', 'name': '1', 'isImage': True},
            {'url': 'https://app.eschool.center/file/2', 'name': '2', 'isImage': True},
        ], attachment_cookies={'JSESSIONID': 'secret'})
        self.assertTrue(ok)
        self.assertIn('<tg-collage>', self.calls[0]['rich']['markdown'])
        self.assertEqual(len(streams), 2)
        self.assertTrue(all(s.closed for s in streams))
        self.assertNotIn('secret', str(self.calls))
        self.assertTrue(all(call.kwargs['allow_redirects'] is False for call in get.call_args_list))

    def test_attachment_credentials_never_go_to_other_origin(self):
        get = Mock(side_effect=AssertionError('Must not download'))
        module = bot_module(self.bot, get)
        self.assertTrue(module.send_telegram_message('123:TEST', '55', 'ДЗ', 'Текст',
            attachments=[{'url': 'https://evil.test/file', 'name': 'Файл', 'isImage': True}],
            attachment_cookies={'JSESSIONID': 'secret'}))
        get.assert_not_called()
        self.assertIn('Не удалось загрузить', self.calls[0]['rich']['markdown'])
        self.assertNotIn('evil.test', str(self.calls))
        self.assertNotIn('secret', str(self.calls))

    def test_media_failure_does_not_repeat_text_on_network_timeout(self):
        module = bot_module(self.bot)
        apihelper._make_request.side_effect = requests.ReadTimeout('private-token')
        self.assertFalse(module.send_telegram_message('123:TEST', '55', 'ДЗ', 'Текст',
            attachments=[{'url': 'https://school.test/photo.jpg', 'isImage': True}]))
        self.assertEqual(apihelper._make_request.call_count, 1)
        self.assertNotIn('private-token', str(module.log.call_args_list))

    def test_rejected_rich_media_uses_text_and_attachment_in_same_topic(self):
        module = bot_module(self.bot)
        original = self.record
        def reject_rich(token, method_name, **kwargs):
            if method_name == 'sendRichMessage':
                raise rejection()
            return original(token, method_name, **kwargs)
        apihelper._make_request.side_effect = reject_rich
        with tempfile.TemporaryDirectory() as directory:
            photo = Path(directory) / 'photo.jpg'
            photo.write_bytes(b'photo')
            self.assertTrue(module.send_telegram_message('123:TEST', '-100', 'ДЗ', 'Текст',
                attachments=[{'path': str(photo), 'isImage': True}], message_thread_id=7))
        self.assertEqual([c['method'] for c in self.calls], ['sendMessage', 'sendPhoto'])
        self.assertTrue(all(c['params']['message_thread_id'] == 7 for c in self.calls))
        self.assertEqual(self.calls[1]['files']['photo'][1], b'photo')

    def test_long_notification_binds_media_to_the_page_containing_it(self):
        module = bot_module(self.bot)
        self.assertTrue(module.send_telegram_message('123:TEST', '-100', 'ДЗ', 'Задание\n' * 9000,
            attachments=[{'url': 'https://school.test/photo.jpg', 'isImage': True}], message_thread_id=7))
        self.assertGreater(len(self.calls), 1)
        with_media = [c for c in self.calls if 'media' in c.get('rich', {})]
        self.assertEqual(len(with_media), 1)
        self.assertIn('tg://photo?id=media0', with_media[0]['rich']['markdown'])

    def test_long_homework_navigation_sends_one_page_with_working_page_controls(self):
        module = bot_module(self.bot)
        day = datetime(2026, 9, 11)
        homework = [{'subject': 'История', 'text': 'Задание\n' * 9000, 'date': day.timestamp() * 1000}]
        card, markup = module._homework_page(homework, day)
        self.assertEqual(len(card.pages()), 1)
        callbacks = [b['callback_data'] for row in markup.to_dict()['inline_keyboard'] for b in row]
        self.assertIn('hw_page:2026-09-11:1', callbacks)
        delivery.edit_card(self.bot, 55, 17, card, reply_markup=markup)
        self.assertEqual(len(self.calls), 1)

    def test_owner_callback_requires_private_chat_and_actual_owner(self):
        module = bot_module(self.bot)
        call = types.SimpleNamespace(message=types.SimpleNamespace(chat=types.SimpleNamespace(id=55, type='private')),
                                     from_user=types.SimpleNamespace(id=55))
        self.assertTrue(module._owner_callback(call, '55'))
        call.from_user.id = 90
        self.assertFalse(module._owner_callback(call, '55'))

    def test_conversation_navigation_edits_existing_card_and_rejects_other_users(self):
        module = bot_module(self.bot)
        module._get_messages_for_telegram = Mock(return_value=(
            [{'subject': f'Беседа {i}', 'preview': 'Текст'} for i in range(1, 13)], None))
        module._bot_polling_loop('registration', '123:TEST', '55')
        call = types.SimpleNamespace(id='callback', data='messages_page:1', message=types.SimpleNamespace(
            chat=types.SimpleNamespace(id=55, type='private'), message_id=17), from_user=types.SimpleNamespace(id=55))
        handler = next(item['function'] for item in self.bot.callback_query_handlers if item['filters']['func'](call))
        handler(call)
        edits = [c for c in self.calls if c['method'] == 'editMessageText']
        self.assertEqual(len(edits), 1)
        self.assertEqual(edits[0]['params']['message_id'], 17)
        self.assertIn(r'Беседы 6\-10 из 12', edits[0]['rich']['markdown'])
        buttons = json.loads(edits[0]['params']['reply_markup'])['inline_keyboard']
        callbacks = [button['callback_data'] for row in buttons for button in row]
        self.assertIn('messages_page:0', callbacks)
        self.assertIn('messages_page:2', callbacks)
        self.assertFalse(any(c['method'] == 'sendRichMessage' for c in self.calls))
        call.from_user.id = 99
        handler(call)
        self.assertEqual(module._get_messages_for_telegram.call_count, 1)
        call.from_user.id = 55
        call.data = 'messages_page:-1'
        handler(call)
        self.assertEqual(module._get_messages_for_telegram.call_count, 1)

    def test_unavailable_conversations_are_reported_as_error_instead_of_empty_list(self):
        module = bot_module(self.bot)
        module._get_user_data_for_telegram = Mock(return_value=([], [], None, 'Имя', None))
        messages, error = module._get_messages_for_telegram('registration')
        self.assertIsNone(messages)
        self.assertIn('Не удалось загрузить список бесед', error)
        module._get_user_data_for_telegram.return_value = ([], [], [], 'Имя', None)
        self.assertEqual(module._get_messages_for_telegram('registration'), ([], None))

    def test_conversations_use_existing_session_without_relogin_or_diary_requests(self):
        module = bot_module(self.bot)
        module.load_user_session.return_value = {'session': 'test'}
        expected = [{'subject': 'Класс', 'preview': 'Добрый день'}]
        module.fetch_threads.return_value = expected
        module._get_user_data_for_telegram = Mock(side_effect=AssertionError('Unexpected login'))
        self.assertEqual(module._get_messages_for_telegram('registration'), (expected, None))
        self.assertEqual(module.fetch_threads.call_args.args[0], {'session': 'test'})
        module._get_user_data_for_telegram.assert_not_called()

    def test_every_menu_button_has_a_handler_and_dispatches_for_owner_only(self):
        module = bot_module(self.bot)
        module._bot_polling_loop('registration', '123:TEST', '55')
        call = types.SimpleNamespace(id='callback', message=types.SimpleNamespace(
            chat=types.SimpleNamespace(id=55, type='private'), message_id=17), from_user=types.SimpleNamespace(id=55))
        for row in module._menu_keyboard().to_dict()['inline_keyboard']:
            for button in row:
                call.data = button['callback_data']
                handler = next(item['function'] for item in self.bot.callback_query_handlers if item['filters']['func'](call))
                action = call.data.split(':')[1]
                with patch.object(module, f'_handle_{action}_command') as target:
                    handler(call)
                    target.assert_called_once()
                    call.from_user.id = 99
                    handler(call)
                    self.assertEqual(target.call_count, 1)
                    call.from_user.id = 55

    def test_period_button_validates_period_and_persists_selection(self):
        module = bot_module(self.bot)
        module._get_bot_token_for_registration = Mock(return_value='123:TEST')
        module._get_periods_for_telegram = Mock(return_value=([
            {'id': 3, 'name': 'I четверть', 'schoolYear': '2026/2027'}], None, None))
        module._save_selected_period = Mock(return_value=True)
        module._bot_polling_loop('registration', '123:TEST', '55')
        call = types.SimpleNamespace(id='callback', data='period:3', message=types.SimpleNamespace(
            chat=types.SimpleNamespace(id=55, type='private'), message_id=17), from_user=types.SimpleNamespace(id=55))
        handler = next(item['function'] for item in self.bot.callback_query_handlers if item['filters']['func'](call))
        handler(call)
        module._save_selected_period.assert_called_once_with('registration', 3, 'I четверть (2026/2027)')
        self.assertTrue(any(c['method'] == 'sendRichMessage' for c in self.calls))
        call.from_user.id = 55
        call.message.chat.type = 'supergroup'
        self.assertFalse(module._owner_callback(call, '55'))

    def test_command_messages_all_use_shared_renderer(self):
        tree = ast.parse((SERVER / 'server_advanced/telegram_bot.py').read_text())
        calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)]
        self.assertFalse(any(c.func.attr in ('send_message', 'reply_to', 'edit_message_text') for c in calls))


class NotificationIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.module = load_module('notification_delivery', {
            f'{PACKAGE}.config': {'get_public_base_url': lambda: 'https://school.test'},
            f'{PACKAGE}.database': {'get_db_connection': Mock(), 'json_value': lambda value: value},
            f'{PACKAGE}.logging_utils': {'log': Mock()},
        })
        self.send = Mock(return_value=True)
        self.module.save_notification_history = Mock(return_value=True)
        self.module.get_telegram_info = Mock(return_value={
            'telegram_enabled': True, 'telegram_bot_token': '123:TEST', 'telegram_user_id': '55',
            'telegram_group_enabled': True, 'telegram_group_chat_id': '-100',
            'telegram_topic_map': '{"10":7}',
        })

    def notify(self, kind, title, body, data, **kwargs):
        import sys
        bot = types.ModuleType(f'{PACKAGE}.telegram_bot')
        bot.send_telegram_message = self.send
        with patch.dict(sys.modules, {f'{PACKAGE}.telegram_bot': bot}):
            return self.module.send_notification_with_telegram(title, body, data,
                registration_id='registration', notification_type=kind, **kwargs)

    def test_grade_value_is_visible_only_in_personal_card(self):
        self.assertTrue(self.notify('grade', '📝 Оценка: 2', 'Физика\nЗа что: Контрольная',
                                   {'type': 'grade', 'value': '2', 'subjectId': '10'}))
        private, group = self.send.call_args_list
        self.assertEqual(private.kwargs['notification_data']['value'], '2')
        self.assertIsNone(group.kwargs['notification_data'])
        self.assertNotIn('2', group.args[2])
        self.assertEqual(group.kwargs['message_thread_id'], 7)

    def test_homework_analysis_and_open_link_reach_both_destinations(self):
        analysis = {'estimable': True, 'total_minutes': 25, 'items': []}
        self.notify('homework', 'ДЗ', 'Текст', {'type': 'homework', 'subjectId': '10',
                    'date': '2026-09-11', 'subject': 'Физика'}, telegram_analysis=analysis)
        self.assertEqual(self.send.call_count, 2)
        for call in self.send.call_args_list:
            self.assertEqual(call.kwargs['analysis_data'], analysis)
            self.assertTrue(call.kwargs['deep_link_url'].startswith('https://reschool.app/open?date=2026-09-11'))

    def test_unmapped_subjects_are_sent_to_general_chat_with_analysis_and_attachments(self):
        analysis = {'estimable': True, 'total_minutes': 30, 'range_min': 20, 'range_max': 45}
        attachments = [{'name': 'дз8-3.png', 'path': '/mock/homework.png'}]
        for mapping in (None, '{}', '{"10":7}', '{"3517":0}', '{"3517":-1}',
                        '{"3517":true}', '{"3517":"bad"}', 'broken-json'):
            with self.subTest(mapping=mapping):
                self.send.reset_mock()
                self.module.get_telegram_info.return_value['telegram_topic_map'] = mapping
                self.assertTrue(self.notify('homework', '📚 ДЗ: Геометрия', 'Решить задачи с фото',
                    {'subjectId': '3517', 'subject': 'Геометрия', 'date': '2026-09-10'},
                    telegram_analysis=analysis, telegram_attachments=attachments))
                self.assertEqual(self.send.call_count, 2)
                group = self.send.call_args_list[1]
                self.assertEqual(group.args[1], '-100')
                self.assertIsNone(group.kwargs['message_thread_id'])
                self.assertEqual(group.kwargs['analysis_data'], analysis)
                self.assertEqual(group.kwargs['attachments'], attachments)

    def test_missing_subject_id_also_goes_to_general_chat(self):
        self.notify('homework', 'ДЗ', 'Текст', {})
        self.assertEqual(self.send.call_count, 2)
        self.assertIsNone(self.send.call_args_list[1].kwargs['message_thread_id'])

    def test_general_chat_grade_notice_does_not_include_the_private_grade(self):
        self.module.get_telegram_info.return_value['telegram_topic_map'] = None
        self.notify('grade', '📝 Оценка: 2', 'Геометрия', {'value': '2', 'subjectId': '3517'})
        group = self.send.call_args_list[1]
        self.assertEqual(group.args[2], '📝 Новая оценка')
        self.assertIsNone(group.kwargs['notification_data'])
        self.assertIsNone(group.kwargs['message_thread_id'])

    def test_disabled_group_and_secondary_device_do_not_send_group_notifications(self):
        for settings in ({'telegram_group_enabled': False}, {'telegram_delivery_primary': False}):
            with self.subTest(settings=settings):
                info = {**self.module.get_telegram_info.return_value, **settings}
                with patch.object(self.module, 'get_telegram_info', return_value=info):
                    self.send.reset_mock()
                    self.notify('homework', 'ДЗ', 'Текст', {'subjectId': '3517'})
                    self.assertFalse(any(call.args[1] == '-100' for call in self.send.call_args_list))


if __name__ == '__main__':
    unittest.main()
