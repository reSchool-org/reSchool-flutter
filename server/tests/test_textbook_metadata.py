"""проверяем распознавание метаданных и загрузку без сети и живой базы"""

import io
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, Mock

from test_backend_hardening import PACKAGE, load_module


META = {'subject': 'Русский язык', 'title': 'Русский язык', 'grade': 8,
        'authors': 'С. Г. Бархударов', 'part': None, 'kind': 'textbook'}


def make_textbook():
    prompts = load_module('ai_prompts', {})
    return load_module('textbook', {
        f'{PACKAGE}.ai_prompts': vars(prompts),
        f'{PACKAGE}.gemini_client': {
            'generate': Mock(return_value=(dict(META), {'sec': 1})),
            'image_part': lambda data, mime: {'image': data},
        },
        f'{PACKAGE}.config': {'ANALYSIS_IMAGE_FOLDER': '/unused', 'TEXTBOOK_INDEX_CHUNK': 10},
        f'{PACKAGE}.database': {'get_db_connection': Mock()},
        f'{PACKAGE}.logging_utils': {'log': Mock()},
    })


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.book = make_textbook()
        self.doc = MagicMock(page_count=296, needs_pass=False)
        self.book.open_document = Mock(return_value=self.doc)
        def page(index):
            result = Mock()
            result.get_pixmap.return_value.tobytes.return_value = index
            return result
        self.doc.__getitem__.side_effect = page

    def test_only_first_three_last_two_pages_in_one_request_without_database(self):
        self.assertEqual(self.book.read_metadata('/book.pdf'), META)
        generate = self.book.gemini_client.generate
        generate.assert_called_once()
        parts = generate.call_args.args[0]
        self.assertEqual([p['image'] for p in parts if 'image' in p], [0, 1, 2, 294, 295])
        self.assertIn('Страница PDF 296 из 296', [p.get('text') for p in parts])
        self.book.get_db_connection.assert_not_called()
        self.doc.close.assert_called_once()

    def test_short_documents_have_no_duplicate_pages(self):
        for count in range(1, 7):
            with self.subTest(count=count):
                self.doc.page_count = count
                self.book.gemini_client.generate.reset_mock()
                self.book.read_metadata('/short.pdf')
                parts = self.book.gemini_client.generate.call_args.args[0]
                expected = list(range(count)) if count <= 5 else [0, 1, 2, 4, 5]
                self.assertEqual([p['image'] for p in parts if 'image' in p], expected)

    def test_empty_or_encrypted_pdf_never_calls_ai(self):
        for count, encrypted in ((0, False), (3, True)):
            self.doc.page_count, self.doc.needs_pass = count, encrypted
            with self.assertRaises(ValueError):
                self.book.read_metadata('/invalid.pdf')
        self.book.gemini_client.generate.assert_not_called()
        self.assertEqual(self.doc.close.call_count, 2)

    def test_ai_failure_closes_document(self):
        self.book.gemini_client.generate.side_effect = RuntimeError('unavailable')
        with self.assertRaisesRegex(RuntimeError, 'unavailable'):
            self.book.read_metadata('/book.pdf')
        self.doc.close.assert_called_once()

    def test_invalid_metadata_cannot_reach_database(self):
        for field, value in (('subject', ''), ('title', '  '), ('grade', True),
                             ('grade', '8'), ('grade', 99), ('authors', ['Name']),
                             ('part', 2), ('kind', 'unknown')):
            with self.subTest(field=field, value=value):
                self.book.gemini_client.generate.return_value = ({**META, field: value}, {'sec': 1})
                with self.assertRaises(ValueError):
                    self.book.read_metadata('/book.pdf')
        self.book.get_db_connection.assert_not_called()

    def test_optional_values_are_not_invented_and_strings_fit_database(self):
        value = self.book._validate_metadata({**META, 'subject': ' Язык ',
                                             'authors': None, 'grade': None,
                                             'title': 'x' * 600, 'part': ''})
        self.assertEqual(value['subject'], 'Язык')
        self.assertEqual(len(value['title']), 512)
        for key in ('authors', 'grade', 'part'):
            self.assertIsNone(value[key])


class IndexMetadataTests(unittest.TestCase):
    def setUp(self):
        self.book = make_textbook()
        self.conn = self.book.get_db_connection.return_value
        self.cursor = self.conn.cursor.return_value
        self.cursor.fetchone.return_value = ('/book.pdf', '')
        self.cursor.rowcount = 1
        self.book.read_metadata = Mock(return_value=dict(META))
        self.doc = Mock(page_count=1)
        self.book.open_document = Mock(return_value=self.doc)
        self.book._index_chunk = Mock(return_value=[])

    def test_metadata_committed_before_first_index_request(self):
        def index(doc, pages):
            writes = [call.args for call in self.cursor.execute.call_args_list
                      if 'SET subject = %s' in call.args[0]]
            self.assertEqual(len(writes), 1)
            self.assertEqual(writes[0][1], ('Русский язык', 8, 'Русский язык',
                                           'С. Г. Бархударов', None, 'textbook', 7))
            self.assertEqual(self.conn.commit.call_count, 3)
            return []
        self.book._index_chunk.side_effect = index
        self.book.index_textbook(7)
        self.book.read_metadata.assert_called_once_with('/book.pdf')
        self.book._index_chunk.assert_called_once()
        self.conn.close.assert_called_once()

    def test_saved_metadata_is_reused_on_retry_and_for_existing_books(self):
        self.cursor.fetchone.return_value = ('/book.pdf', 'Русский язык')
        self.book.index_textbook(7)
        self.book.read_metadata.assert_not_called()
        self.book._index_chunk.assert_called_once()

    def test_failed_metadata_prevents_paid_indexing(self):
        self.book.read_metadata.side_effect = ValueError('No subject')
        with self.assertRaisesRegex(ValueError, 'No subject'):
            self.book.index_textbook(7)
        self.book._index_chunk.assert_not_called()
        self.book.open_document.assert_not_called()
        self.cursor.close.assert_called_once()
        self.conn.close.assert_called_once()

    def test_deleted_book_is_not_indexed_after_metadata_request(self):
        self.cursor.rowcount = 0
        self.book.index_textbook(7)
        self.book._index_chunk.assert_not_called()


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.conn = Mock()
        self.conn.cursor.return_value.fetchone.return_value = (7,)
        self.doc = Mock(page_count=296, needs_pass=False)
        self.upload = io.BytesIO(b'%PDF fixture')
        self.upload.filename = 'Русский язык.pdf'
        self.upload.save = lambda path: Path(path).write_bytes(self.upload.getvalue())
        self.request = SimpleNamespace(files={'file': self.upload}, form={})
        self.enqueue = Mock(side_effect=lambda conn, *a, **kw: conn.commit())
        self.routes = load_module('routes.textbooks', {
            'flask': {'Blueprint': lambda *a: SimpleNamespace(route=lambda *a, **kw: lambda f: f),
                      'request': self.request, 'jsonify': lambda value: value, 'send_file': Mock()},
            'werkzeug.utils': {'secure_filename': lambda value: 'book.pdf'},
            f'{PACKAGE}.analysis': {}, f'{PACKAGE}.merge': {},
            f'{PACKAGE}.ai_worker': {'enqueue': self.enqueue},
            f'{PACKAGE}.gemini_client': {'is_configured': lambda: True},
            f'{PACKAGE}.textbook': {'open_document': Mock(return_value=self.doc)},
            f'{PACKAGE}.config': {'MAX_TEXTBOOK_SIZE': 1000, 'TEXTBOOK_FOLDER': self.temp.name},
            f'{PACKAGE}.database': {'get_db_connection': lambda: self.conn},
            f'{PACKAGE}.logging_utils': {'log': Mock()},
            f'{PACKAGE}.rate_limiter': {'rate_limit': lambda *a: lambda f: f},
            f'{PACKAGE}.routes.homework': {'_resolve_grade_class_for_request': lambda: ('8-А', None)},
        })

    def test_file_only_upload_queues_metadata_and_index_in_one_transaction(self):
        result = self.routes.upload_textbook()
        self.assertTrue(result['success'])
        self.assertEqual(result['textbook']['title'], 'Русский язык.pdf')
        params = self.conn.cursor.return_value.execute.call_args.args[1]
        self.assertEqual(params[:7], ('8-А', '', None, 'Русский язык.pdf', None, None, 'textbook'))
        self.enqueue.assert_called_once_with(self.conn, 'index_textbook', {'textbook_id': 7},
                                             dedup_key='textbook:7')
        self.conn.commit.assert_called_once()

    def test_old_client_fields_cannot_override_ai_metadata(self):
        self.request.form.update(subject='Wrong', grade='999', kind='invalid')
        self.assertTrue(self.routes.upload_textbook()['success'])
        params = self.conn.cursor.return_value.execute.call_args.args[1]
        self.assertEqual(params[1], '')
        self.assertIsNone(params[2])
        self.assertEqual(params[6], 'textbook')

    def test_queue_failure_rolls_back_book_and_removes_uploaded_file(self):
        self.enqueue.side_effect = RuntimeError('database unavailable')
        _, status = self.routes.upload_textbook()
        self.assertEqual(status, 500)
        self.conn.rollback.assert_called_once()
        self.conn.commit.assert_not_called()
        self.assertEqual(list(Path(self.temp.name).iterdir()), [])

    def test_unreadable_or_encrypted_pdf_never_enters_queue(self):
        for invalid in ('unreadable', 'encrypted', 'empty'):
            with self.subTest(invalid=invalid):
                self.routes.textbook.open_document.side_effect = (
                    ValueError('bad PDF') if invalid == 'unreadable' else None)
                self.doc.needs_pass = invalid == 'encrypted'
                self.doc.page_count = 0 if invalid == 'empty' else 296
                _, status = self.routes.upload_textbook()
                self.assertEqual(status, 400)
                self.assertEqual(list(Path(self.temp.name).iterdir()), [])
        self.enqueue.assert_not_called()
        self.conn.cursor.return_value.execute.assert_not_called()


if __name__ == '__main__':
    unittest.main()
