import unittest
from unittest.mock import Mock
from urllib.parse import urlsplit, parse_qs

from test_chat_notifications import make_routes, make_chat, response
from server_advanced.student_context import student_context


def parent_state():
    return {'userId': 10, 'user': {'prsId': 100, 'currentPosition': {
        'posTypeCode': 'P', 'myChildren': [
            {'prsId': 200},
            {'prsId': 300, 'isDefaultChild': 1, 'userData': [
                {'userId': 29, 'orgIsReady': 1, 'yearState': 'ARC'},
                {'userId': 30, 'orgIsReady': 1, 'yearState': 'CURR'},
                {'userId': 31, 'orgIsReady': 1, 'yearState': 'PLAN'},
            ]},
        ]}}}


class StudentContextTests(unittest.TestCase):
    def test_default_child_and_current_enrollment(self):
        self.assertEqual(student_context(parent_state()), {'prsId': 300, 'userId': 30})

    def test_no_default_uses_first_child_without_parent_user_id(self):
        state = parent_state()
        state['user']['currentPosition']['myChildren'][1]['isDefaultChild'] = 0
        self.assertEqual(student_context(state), {'prsId': 200, 'userId': None})

    def test_missing_children_do_not_fall_back_to_parent(self):
        state = parent_state()
        state['user']['currentPosition']['myChildren'] = []
        with self.assertRaises(ValueError):
            student_context(state)

    def test_student_unchanged(self):
        self.assertEqual(student_context({'userId': 10, 'user': {'prsId': 100}}),
                         {'prsId': 100, 'userId': 10})


class ParentRequestsTests(unittest.TestCase):
    def setUp(self):
        chat, self.http = make_chat()
        self.routes = make_routes(chat, self.http)
        self.routes._fetch_chat_threads = Mock(return_value=([], False))
        self.routes._get_year_id = Mock(return_value=2026)
        self.routes._fetch_lpart = Mock(return_value=[])
        self.http.get.side_effect = self.get

    def get(self, url, **kwargs):
        path = urlsplit(url).path
        query = parse_qs(urlsplit(url).query)
        if path.endswith('/state'):
            return response(parent_state())
        if path.endswith('/getPrsDiary'):
            self.assertEqual(query['prsId'], ['300'])
            return response({'lesson': [{'id': 1, 'date': 1800000000000,
                'unit': {'name': 'Математика'}, 'part': [{'cat': 'DZ',
                'variant': [{'id': 9, 'text': 'Задание'}]}]}],
                'user': [{'mark': [{'id': 8, 'value': 5, 'lessonID': 1}]}]})
        if path.endswith('/getClassByUser'):
            self.assertEqual(query['userId'], ['30'])
            return response([{'groupId': 50}])
        if '/dict/periods/' in path:
            return response({'items': []})
        if '/getDiaryUnits/' in path or '/getDiaryPeriod_/' in path:
            self.assertEqual(query['userId'], ['30'])
            return response({'result': []})
        raise AssertionError(path)

    def test_poll_reads_child_but_returns_owner_for_chats(self):
        hw, marks, _, _, expired, owner = self.routes.fetch_data_with_session({'saved': 'cookie'}, 'parent')
        self.assertFalse(expired)
        self.assertEqual(owner, 100)
        self.assertEqual(hw[0]['studentPrsId'], 300)
        self.assertEqual(marks[0]['value'], '5')
        self.assertEqual(self.routes._get_year_id.call_args.args[1], 300)
        self.assertEqual(self.routes._fetch_lpart.call_args.args[1], 300)
        self.http.post.assert_not_called()

    def test_explicit_login_returns_parent_identity_for_verification(self):
        self.http.post.return_value = Mock(status_code=200, cookies={'saved': 'cookie'})
        self.routes.get_eschool_version = Mock(return_value='3.0')
        hw, marks, _, _, cookies, owner = self.routes.login_and_get_data('parent', 'password')
        self.assertEqual(owner, 100)
        self.assertEqual(hw[0]['studentPrsId'], 300)
        self.assertEqual(marks[0]['value'], '5')

    def test_catalogue_and_grades_use_child(self):
        self.assertIsNone(self.routes.get_periods_for_user({'saved': 'cookie'})[2])
        self.assertIsNone(self.routes.get_subjects_for_user({'saved': 'cookie'})[1])
        self.assertIsNone(self.routes.get_grades_for_period({'saved': 'cookie'}, 5)[3])
        self.http.post.assert_not_called()

    def test_diary_failure_does_not_replace_monitor_snapshot_with_empty_lists(self):
        self.http.get.side_effect = [response(parent_state()), response({}, 503)]
        data = self.routes.fetch_data_with_session({'saved': 'cookie'}, 'parent')
        self.assertIsNone(data[0])
        self.assertFalse(data[4])
        self.http.post.assert_not_called()

    def test_monitor_detects_new_child_items_and_keeps_parent_chat_identity(self):
        self.routes.get_db_connection.return_value = None
        self.routes.get_session.return_value = {'saved': 'cookie'}
        self.routes._check_chat_updates = Mock()
        self.routes.analysis.is_enabled = Mock(return_value=False)
        self.routes._check_user_for_updates({
            'id': 'parent-registration', 'username': 'parent',
            'last_homework_ids': '[]', 'last_grade_ids': '[]',
        })
        delivered = self.routes.send_notification_with_telegram.call_args_list
        self.assertEqual({call.kwargs['notification_type'] for call in delivered}, {'homework', 'grade'})
        self.assertEqual(self.routes._check_chat_updates.call_args.args[3], 100)
        self.routes.send_notification_with_telegram.reset_mock()
        self.routes._check_user_for_updates({
            'id': 'parent-registration', 'username': 'parent',
            'last_homework_ids': '[9]', 'last_grade_ids': '[8]',
        })
        self.routes.send_notification_with_telegram.assert_not_called()
