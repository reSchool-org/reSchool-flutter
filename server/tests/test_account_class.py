"""проверяем форматы класса и привязку к сессии аккаунта"""

from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from server_advanced.account_class import pick_account_class, resolve_account_class


class AccountClassTests(unittest.TestCase):
    def test_group_name_and_numeric_dates_choose_latest_active_class(self):
        now = datetime.now(timezone.utc)
        self.assertEqual(pick_account_class([
            {'groupName': '10А класс', 'begDate': (now - timedelta(days=10)).timestamp() * 1000},
            {'groupName': '9А класс', 'begDate': (now - timedelta(days=400)).timestamp()},
            None,
        ]), '10А класс')

    def test_iso_and_profile_dates_work_with_timezones(self):
        now = datetime.now(timezone.utc)
        self.assertEqual(pick_account_class([
            {'className': '10А', 'bvt': (now - timedelta(days=1)).isoformat(),
             'evt': (now + timedelta(days=1)).isoformat()},
            {'name': '11А', 'dtFrom': (now + timedelta(days=365)).isoformat()},
        ]), '10А')

    def response(self, value, status=200):
        return Mock(status_code=status, json=Mock(return_value=value))

    def test_lookup_uses_only_logged_in_account(self):
        with patch('server_advanced.account_class.requests.get', side_effect=[
            self.response({'userId': 7, 'user': {'prsId': 123}}),
            self.response([{'groupName': '10А класс', 'begDate': 1700000000000}]),
        ]) as request:
            self.assertEqual(resolve_account_class({'session': 'own'}, 123), '10А класс')
        self.assertEqual(request.call_args.kwargs['params'], {'userId': 7})
        for call in request.call_args_list:
            self.assertEqual(call.kwargs['cookies'], {'session': 'own'})
            self.assertFalse(call.kwargs['allow_redirects'])

    def test_wrong_session_is_rejected_before_class_lookup(self):
        with patch('server_advanced.account_class.requests.get', return_value=self.response({'userId': 7, 'user': {'prsId': 999}})) as request:
            self.assertIsNone(resolve_account_class({'session': 'wrong'}, 123))
        self.assertEqual(request.call_count, 1)

    def test_own_profile_is_used_when_class_list_is_empty(self):
        with patch('server_advanced.account_class.requests.get', side_effect=[
            self.response({'userId': 7, 'user': {'prsId': 123}}),
            self.response([]),
            self.response({'data': {'prsId': 123}, 'pupil': [{'className': '10А'}]}),
        ]):
            self.assertEqual(resolve_account_class({'session': 'own'}, 123), '10А')

    def test_foreign_profile_is_not_used(self):
        with patch('server_advanced.account_class.requests.get', side_effect=[
            self.response({'user': {'prsId': 123}}),
            self.response({'data': {'prsId': 999}, 'pupil': [{'className': '10А'}]}),
        ]):
            self.assertIsNone(resolve_account_class({'session': 'own'}, 123))
