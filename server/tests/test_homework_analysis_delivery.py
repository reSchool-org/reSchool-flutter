"""проверяем дубли заданий из дневника и lpart вместе с вложениями word"""
import io
from http.cookiejar import CookieJar
import os
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import Mock, patch
import zipfile

from test_backend_hardening import PACKAGE, SERVER, load_module
from test_chat_notifications import make_chat, make_routes


TEXT = 'Оформить ответы на отдельных листочках.\nПри выполнении опираться на параграфы 2-4'


def make_analysis(sources):
    return load_module('analysis', {
        f'{PACKAGE}.ai_prompts': {'ASSESS_SCHEMA': {}, 'ASSESS_SYSTEM': ''},
        f'{PACKAGE}.analysis_sources': vars(sources),
        f'{PACKAGE}.gemini_client': {'generate': Mock(return_value=({'estimable': True, 'total_minutes': 25}, {'sec': 1}))},
        f'{PACKAGE}.textbook': {},
        f'{PACKAGE}.config': {'ANALYSIS_ENABLED': True, 'ANALYSIS_NOTIFICATION_TIMEOUT_SECONDS': 300},
        f'{PACKAGE}.database': {'get_db_connection': Mock(), 'json_value': lambda v: v},
        f'{PACKAGE}.logging_utils': {'log': Mock()},
    })


class HomeworkMergeTests(unittest.TestCase):
    def setUp(self):
        self.routes = make_routes(*make_chat())
        self.diary = {'id': 1, 'text': TEXT, 'date': 1800000000000, 'subject': 'Биология',
                      'attachments': [{'url': 'https://example.test/questions', 'name': 'questions.docx'}]}
        self.lpart = {'partId': 2, 'passDt': self.diary['date'], 'unitName': 'Биология',
                      'preview': TEXT.replace('\n', ' '), 'attachCnt': 1}

    def test_whitespace_differences_merge_and_keep_diary_id_and_attachments(self):
        items = self.routes._merge_lpart([self.diary], [self.lpart])
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]['id'], 1)
        self.assertEqual(items[0]['partId'], 2)
        self.assertTrue(items[0]['hasFiles'])
        self.assertEqual(items[0]['attachments'][0]['name'], 'questions.docx')

    def test_same_prefix_different_questions_are_not_merged(self):
        self.lpart['preview'] += ' и письменно ответить на вопрос 5'
        self.assertEqual(len(self.routes._merge_lpart([self.diary], [self.lpart])), 2)

    def test_other_day_is_not_merged(self):
        self.lpart['passDt'] += 86400000
        self.assertEqual(len(self.routes._merge_lpart([self.diary], [self.lpart])), 2)

    def test_empty_text_does_not_hide_different_attachments(self):
        self.diary['text'] = self.lpart['preview'] = ''
        self.assertEqual(len(self.routes._merge_lpart([self.diary], [self.lpart])), 2)


class DocumentAnalysisTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.sources = load_module('analysis_sources', {
            'requests': {'get': Mock()},
            f'{PACKAGE}.config': {'ANALYSIS_IMAGE_FOLDER': self.tmp.name},
            f'{PACKAGE}.logging_utils': {'log': Mock()},
        })
        self.gemini = types.ModuleType(f'{PACKAGE}.gemini_client')
        self.gemini.image_part = Mock(side_effect=lambda data, mime: {'inlineData': {'mimeType': mime}})
        self.modules = patch.dict('sys.modules', {f'{PACKAGE}.gemini_client': self.gemini})
        self.modules.start()
        self.addCleanup(self.modules.stop)

    def docx(self):
        data = io.BytesIO()
        with zipfile.ZipFile(data, 'w') as archive:
            archive.writestr('word/document.xml', '''<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
<w:p><w:r><w:t>Вопрос: </w:t></w:r><w:r><w:t>назови царство клетки.</w:t></w:r></w:p>
<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Систематика</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
</w:body></w:document>''')
        return data.getvalue()

    def test_downloaded_docx_questions_and_table_reach_model(self):
        response = Mock(status_code=200)
        response.raw.read.return_value = self.docx()
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        self.sources.requests.get.return_value = response
        materials = self.sources.fetch_teacher_attachments(10, [
            {'name': 'Домашняя работа.docx', 'url': 'https://app.eschool.center/file', 'isImage': False}])
        self.assertEqual(len(materials), 1)
        analysis = make_analysis(self.sources)
        assessment = analysis._assess('8-3', 'Биология', TEXT, [], [], None, materials, {}, None)
        self.assertTrue(assessment['estimable'])
        parts = analysis.gemini_client.generate.call_args.args[0]
        text = '\n'.join(p.get('text', '') for p in parts)
        self.assertIn('Вопрос: назови царство клетки.', text)
        self.assertIn('Систематика', text)

    def download_response(self, status=200, body=b'image'):
        response = Mock(status_code=status)
        response.raw.read.return_value = body
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        self.sources.requests.get.return_value = response
        return response

    def test_untrusted_and_ambiguous_urls_never_receive_a_request(self):
        urls = [
            'https://attacker.test/image.jpg', 'http://app.eschool.center/image.jpg',
            'https://app.eschool.center.attacker.test/image.jpg',
            'https://app.eschool.center@attacker.test/image.jpg',
            'https://user@app.eschool.center/image.jpg',
            'https://app.eschool.center:444/image.jpg',
            'https://app.eschool.center:bad/image.jpg',
            'https://app.eschool.center./image.jpg',
            'https://app%2eeschool.center/image.jpg',
            'https://app.eschool.center\\@attacker.test/image.jpg',
            'https://app.eschool.center\t/image.jpg',
            ' https://app.eschool.center/image.jpg',
            'https://[invalid/image.jpg', 'https://127.0.0.1/image.jpg',
            'http://169.254.169.254/latest/meta-data', 'https://[::1]/image.jpg',
            '//app.eschool.center/image.jpg', '/image.jpg', 'file:///etc/passwd',
            123, {'url': 'https://app.eschool.center/image.jpg'},
        ]
        self.download_response()
        for credentials in (None, {'JSESSIONID': 'secret'}):
            for url in urls:
                with self.subTest(url=url, credentials=bool(credentials)):
                    saved = self.sources.fetch_teacher_attachments(10, [
                        {'name': 'photo.jpg', 'url': url, 'isImage': True}],
                        headers={'Authorization': 'secret'} if credentials else None,
                        cookies=credentials)
                    self.assertEqual(saved, [])
        self.sources.requests.get.assert_not_called()

    def test_trusted_images_keep_credentials_and_disable_redirects(self):
        for url in ('https://app.eschool.center/image.jpg',
                    'https://APP.ESCHOOL.CENTER:443/image.jpg?version=2'):
            for cookies in ({'JSESSIONID': 'secret'}, CookieJar()):
                with self.subTest(url=url, cookies=type(cookies).__name__):
                    self.download_response()
                    headers = {'Accept': 'image/*'}
                    materials = self.sources.fetch_teacher_attachments(10, [
                        {'name': 'photo.jpg', 'url': url, 'isImage': True}],
                        headers=headers, cookies=cookies)
                    self.assertEqual(Path(materials[0]['path']).read_bytes(), b'image')
                    kwargs = self.sources.requests.get.call_args.kwargs
                    self.assertIs(kwargs['headers'], headers)
                    self.assertIs(kwargs['cookies'], cookies)
                    self.assertIs(kwargs['allow_redirects'], False)

    def test_redirects_are_not_followed_or_saved(self):
        for status in (301, 302, 303, 307, 308):
            with self.subTest(status=status):
                self.sources.requests.get.reset_mock()
                response = self.download_response(status)
                response.headers = {'Location': 'https://attacker.test/image.jpg'}
                self.assertEqual(self.sources.fetch_teacher_attachments(10, [
                    {'name': 'photo.jpg', 'url': 'https://app.eschool.center/redirect',
                     'isImage': True}], cookies={'JSESSIONID': 'secret'}), [])
                self.sources.requests.get.assert_called_once()
                self.assertIs(self.sources.requests.get.call_args.kwargs['allow_redirects'], False)
                response.raw.read.assert_not_called()

    def test_bad_attachment_does_not_prevent_trusted_download(self):
        self.download_response()
        materials = self.sources.fetch_teacher_attachments(10, [
            {'name': 'bad.jpg', 'url': 'https://[invalid', 'isImage': True},
            {'name': 'good.jpg', 'url': 'https://app.eschool.center/file', 'isImage': True}])
        self.assertEqual([item['name'] for item in materials], ['good.jpg'])
        self.sources.requests.get.assert_called_once()

    def test_size_and_count_limits_still_apply(self):
        attachments = [{'name': 'photo.jpg', 'url': 'https://app.eschool.center/file',
                        'isImage': True}] * (self.sources.MAX_ATTACHMENT_IMAGES + 1)
        self.download_response(body=b'x' * (self.sources.MAX_ATTACHMENT_BYTES + 1))
        self.assertEqual(self.sources.fetch_teacher_attachments(10, attachments[:1]), [])
        self.sources.requests.get.reset_mock()
        self.download_response()
        self.assertEqual(len(self.sources.fetch_teacher_attachments(11, attachments)),
                         self.sources.MAX_ATTACHMENT_IMAGES)
        self.assertEqual(self.sources.requests.get.call_count, self.sources.MAX_ATTACHMENT_IMAGES)

    def test_long_filename_keeps_document_extension(self):
        self.assertTrue(self.sources._safe('а' * 90 + '.docx').endswith('.docx'))

    def test_oversized_unpacked_docx_is_rejected(self):
        path = Path(self.tmp.name) / 'large.docx'
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('word/document.xml', 'x' * (self.sources.MAX_ATTACHMENT_BYTES + 1))
        with self.assertRaises(ValueError):
            self.sources.material_parts({'path': str(path)})

    def test_pdf_is_sent_with_document_mime(self):
        path = Path(self.tmp.name) / 'questions.pdf'
        path.write_bytes(b'%PDF-1.4')
        parts = self.sources.material_parts({'path': str(path)})
        self.assertEqual(parts[0]['inlineData']['mimeType'], 'application/pdf')


class AnalysisCookieScopeTests(unittest.TestCase):
    def test_monitor_preserves_cookie_jar_for_analysis_and_serializable_delivery(self):
        routes = make_routes(*make_chat())
        cookies = Mock()
        cookies.get_dict.return_value = {'JSESSIONID': 'secret'}
        routes.get_session.return_value = cookies
        routes.fetch_data_with_session = Mock(return_value=([
            {'id': 1, 'text': TEXT, 'subject': 'Биология', 'date': 1789419600000,
             'attachments': [{'name': 'photo.jpg', 'url': 'https://app.eschool.center/file'}]},
        ], [], [], None, False, 70))
        routes._load_item_hashes = Mock(return_value={})
        routes._save_item_hashes = Mock()
        routes._check_chat_updates = Mock()
        routes.analysis.is_enabled = Mock(return_value=True)
        routes.analysis.enqueue = Mock(return_value=(10, True))
        routes.analysis.add_pending = Mock()
        routes.analysis.load = Mock(return_value=None)
        routes._check_user_for_updates({
            'id': 'student', 'username': 'student', 'password': 'encrypted',
            'grade_class': '8-3'})
        routes.analysis.enqueue.assert_called_once()
        self.assertEqual(routes.analysis.enqueue.call_args.args[3], '2026-09-15')
        for call in routes.analysis.add_pending.call_args_list:
            self.assertEqual(call.args[5]['date'], '2026-09-15')
        self.assertIs(routes.analysis.enqueue.call_args.kwargs['attachment_cookies'], cookies)
        payload = routes.analysis.add_pending.call_args_list[0].kwargs['payload']
        self.assertEqual(payload['telegram_attachment_cookies'], {'JSESSIONID': 'secret'})


class GroundedAssessmentTests(unittest.TestCase):
    def setUp(self):
        self.analysis = make_analysis(types.SimpleNamespace(material_parts=Mock(return_value=[])))

    def assess(self, text, targets=None, images=None, materials=None, parsed=None):
        return self.analysis._assess('8-3', 'Английский язык', text, targets or [],
                                     images or [], None, materials or [], parsed or {}, None)

    def test_textbook_numbers_never_invoke_estimator_without_content(self):
        for text in ('Учебник, страница 9 - упражнение 2 (б), 3,4,5,6. Рабочая тетрадь, страница 4',
                     'читать параграфы 1,2', 'параграф 4-6 прочитать',
                     'Starlight St.B. p. 6 ex. 6, 8, p. 8 (read and translate)'):
            with self.subTest(text=text):
                result = self.assess(text, parsed={'needs_material': False})
                self.assertFalse(result['estimable'])
                self.assertEqual(result['items'], [])
        self.analysis.gemini_client.generate.assert_not_called()

    def test_number_only_targets_and_missing_files_are_not_evidence(self):
        result = self.assess('220 и 100 письменно',
                            targets=[{'type': 'exercise', 'label': '220'}],
                            images=[{'target_type': 'exercise', 'label': '220', 'subitem': '',
                                     'path': '/nonexistent/reschool-page.png'}],
                            materials=[{'path': '/nonexistent/reschool-file.pdf'}])
        self.assertFalse(result['estimable'])
        self.analysis.gemini_client.generate.assert_not_called()

    def test_empty_document_does_not_enable_guessed_estimate(self):
        with tempfile.NamedTemporaryFile() as material:
            result = self.assess('упр. 10', materials=[{'path': material.name}])
        self.assertFalse(result['estimable'])
        self.analysis.gemini_client.generate.assert_not_called()

    def test_partial_crops_do_not_become_total_homework_estimate(self):
        with tempfile.NamedTemporaryFile() as crop:
            self.analysis.gemini_client.image_part = Mock(return_value={'inlineData': {}})
            result = self.assess('упр. 10 и 11', targets=[
                {'type': 'exercise', 'label': '10'}, {'type': 'exercise', 'label': '11'}],
                images=[{'target_type': 'exercise', 'label': '10', 'subitem': '', 'path': crop.name}])
        self.assertFalse(result['estimable'])
        self.analysis.gemini_client.generate.assert_not_called()

    def test_one_subitem_cannot_stand_in_for_the_whole_exercise(self):
        with tempfile.NamedTemporaryFile() as crop:
            self.analysis.gemini_client.image_part = Mock(return_value={'inlineData': {}})
            result = self.assess('упр. 10 а, б', targets=[
                {'type': 'exercise', 'label': '10', 'subitems': ['а', 'б']}],
                images=[{'target_type': 'exercise', 'label': '10', 'subitem': 'а', 'path': crop.name}])
        self.assertFalse(result['estimable'])
        self.analysis.gemini_client.generate.assert_not_called()

    def test_self_contained_assignment_can_be_estimated(self):
        self.assertTrue(self.assess('Напиши пять предложений о своих каникулах.',
                                   targets=[{'type': 'other', 'label': 'Пять предложений'}])['estimable'])
        self.analysis.gemini_client.generate.assert_called_once()


class SummaryEstimateTests(unittest.TestCase):
    def test_partial_estimate_is_not_presented_as_total(self):
        merge = load_module('merge', {
            f'{PACKAGE}.analysis': {}, f'{PACKAGE}.ai_prompts': {},
            f'{PACKAGE}.gemini_client': {},
            f'{PACKAGE}.database': {'get_db_connection': Mock(), 'json_value': lambda v: v},
            f'{PACKAGE}.logging_utils': {'log': Mock()},
        })
        merge._part_images = Mock(return_value=[])
        for second, expected in (((None, False), None), ((20, True), 30)):
            cursor = Mock()
            cursor.fetchone.side_effect = [(1, 'ready', 'Задания', [], [], 2), (10, True), second]
            cursor.fetchall.return_value = [(1, 'teacher', 'Учитель'), (2, 'custom', 'Ученик')]
            self.assertEqual(merge.load(cursor, '8-3', 'Русский язык', '2026-09-15')['totalMinutes'], expected)


class SchoolDateRegressionTests(unittest.TestCase):
    def test_moscow_midnight_is_same_school_day_regardless_of_process_timezone(self):
        from datetime import datetime, timezone
        stamp = datetime(2026, 9, 14, 21, tzinfo=timezone.utc).timestamp() * 1000
        routes = make_routes(*make_chat())
        self.assertEqual(routes._format_notify_date(stamp), '15.09.2026')
        self.assertEqual(routes.school_date(stamp), '2026-09-15')
        # московская полночь и дата без времени в utc описывают один школьный день
        items = routes._merge_lpart([
            {'id': 1, 'date': stamp, 'text': 'упр. 2', 'subject': 'Английский язык'}], [
            {'partId': 2, 'passDt': stamp + 3 * 3600000,
             'preview': 'упр. 2', 'unitName': 'Английский язык'}])
        self.assertEqual(len(items), 1)


@unittest.skipUnless(os.getenv('RESCHOOL_TEST_DATABASE_URL'), 'нужна RESCHOOL_TEST_DATABASE_URL')
class PendingDeliveryConcurrencyTests(unittest.TestCase):
    def setUp(self):
        import psycopg
        from psycopg import sql
        from psycopg.types.json import Jsonb
        self.schema = 'homework_test_' + uuid.uuid4().hex
        self.admin = psycopg.connect(os.environ['RESCHOOL_TEST_DATABASE_URL'], autocommit=True)
        self.admin.execute(sql.SQL('CREATE SCHEMA {}').format(sql.Identifier(self.schema)))
        self.addCleanup(self.cleanup_schema)
        self.admin.execute(sql.SQL('CREATE TABLE {}.pending_notifications ('
            'id BIGSERIAL PRIMARY KEY, analysis_id BIGINT, audience TEXT, registration_id TEXT, '
            'grade_class TEXT, title TEXT, body TEXT, data JSONB, payload JSONB, '
            'exclude_classmate_id TEXT, exclude_registration_id TEXT, '
            "status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'dropped')), sent_at TIMESTAMP)"
        ).format(sql.Identifier(self.schema)))
        self.admin.execute(sql.SQL('SET search_path TO {}').format(sql.Identifier(self.schema)))
        self.admin.execute((SERVER / 'server_advanced/migrations/0010_notification_delivery_status.sql').read_text())
        self.admin.execute((SERVER / 'server_advanced/migrations/0011_telegram_outbox.sql').read_text())
        def connect():
            conn = psycopg.connect(os.environ['RESCHOOL_TEST_DATABASE_URL'])
            conn.execute(sql.SQL('SET search_path TO {}').format(sql.Identifier(self.schema)))
            conn.commit()
            return conn
        self.connect = connect
        self.analysis = make_analysis(types.SimpleNamespace())
        self.analysis.get_db_connection = connect
        self.analysis.json_value = Jsonb
        self.analysis.load = Mock(return_value={'status': 'done', 'estimable': True})
        self.analysis.analysis_images = Mock(return_value=[])

    def cleanup_schema(self):
        from psycopg import sql
        self.admin.execute(sql.SQL('DROP SCHEMA {} CASCADE').format(sql.Identifier(self.schema)))
        self.admin.close()

    def enqueue(self, source_id):
        with self.connect() as conn:
            self.analysis.add_pending(conn, 10, 'registration', 'ДЗ: Биология', TEXT,
                                      data={'id': str(source_id)}, registration_id='student')

    def test_two_sources_and_repeated_check_create_one_notification(self):
        with ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(self.enqueue, [6130662, 12252529]))
        with self.connect() as conn:
            self.assertEqual(conn.execute('SELECT count(*) FROM pending_notifications').fetchone()[0], 1)
            conn.execute("UPDATE pending_notifications SET status = 'sent'")
        self.enqueue(12252529)
        with self.connect() as conn:
            self.assertEqual(conn.execute('SELECT count(*) FROM pending_notifications').fetchone()[0], 1)

    def test_concurrent_flush_sends_each_row_once(self):
        self.enqueue(6130662)
        delivery = types.ModuleType(f'{PACKAGE}.notification_delivery')
        delivery.send_notification_with_telegram = Mock()
        routes = types.ModuleType(f'{PACKAGE}.routes.notifications')
        routes._notify_classmates = Mock()
        with patch.dict('sys.modules', {
            delivery.__name__: delivery, routes.__name__: routes,
        }):
            with ThreadPoolExecutor(max_workers=2) as pool:
                list(pool.map(self.analysis.flush, [10, 10]))
        delivery.send_notification_with_telegram.assert_called_once()

    def test_status_is_sending_during_delivery_and_failed_result_is_not_marked_sent(self):
        self.enqueue(6130662)
        delivery = types.ModuleType(f'{PACKAGE}.notification_delivery')
        def fail(*args, **kwargs):
            with self.connect() as conn:
                self.assertEqual(conn.execute('SELECT status, sent_at FROM pending_notifications').fetchone(),
                                 ('sending', None))
            return False
        delivery.send_notification_with_telegram = Mock(side_effect=fail)
        routes = types.ModuleType(f'{PACKAGE}.routes.notifications')
        routes._notify_classmates = Mock()
        with patch.dict('sys.modules', {delivery.__name__: delivery, routes.__name__: routes}):
            self.analysis.flush(10)
            self.analysis.flush(10)
        delivery.send_notification_with_telegram.assert_called_once()
        with self.connect() as conn:
            row = conn.execute('SELECT status, sent_at, last_error FROM pending_notifications').fetchone()
            self.assertEqual(row[:2], ('failed', None))
            self.assertIn('delivery_failed', row[2])

    def test_success_is_marked_sent_after_delivery(self):
        self.enqueue(6130662)
        delivery = types.ModuleType(f'{PACKAGE}.notification_delivery')
        delivery.send_notification_with_telegram = Mock(return_value=True)
        routes = types.ModuleType(f'{PACKAGE}.routes.notifications')
        routes._notify_classmates = Mock()
        with patch.dict('sys.modules', {delivery.__name__: delivery, routes.__name__: routes}):
            self.analysis.flush(10)
        with self.connect() as conn:
            status, sent_at, error = conn.execute('SELECT status, sent_at, last_error FROM pending_notifications').fetchone()
            self.assertEqual(status, 'sent')
            self.assertIsNotNone(sent_at)
            self.assertIsNone(error)


if __name__ == '__main__':
    unittest.main()
