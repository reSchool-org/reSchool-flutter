import json
from copy import deepcopy
from datetime import datetime, timezone
import hashlib
import types
import unittest
from unittest.mock import Mock, patch

from test_backend_hardening import PACKAGE, load_module


BASE_TIME = 1_800_000_000_000
OWN_ID = 70


def message(number, sender=90, **changes):
    return dict({
        'msgId': number + 1000, 'msgNum': number, 'threadId': 1,
        'senderId': sender, 'senderFio': 'Настоящий автор',
        'sendDate': BASE_TIME + number, 'stateId': 5,
        'msg': f'<p>Сообщение {number}</p>',
    }, **changes)


def response(data, status=200):
    return types.SimpleNamespace(status_code=status, json=lambda: data)


def make_chat():
    http = types.SimpleNamespace(get=Mock(), put=Mock(), post=Mock(), RequestException=ConnectionError)
    module = load_module('chat_notifications', {
        'requests': vars(http),
        f'{PACKAGE}.config': {'BASE_URL': 'https://eschool.test/ec-server'},
    })
    module.PAGE_SIZE = 3
    return module, http


def make_routes(chat, http):
    request = types.SimpleNamespace(json={})
    module = load_module('routes.notifications', {
        f'{PACKAGE}.check_schedule': vars(load_module('check_schedule', {})),
        'flask': {
            'Blueprint': lambda *a: types.SimpleNamespace(route=lambda *a, **k: lambda fn: fn),
            'jsonify': lambda value: value, 'request': request,
        },
        'requests': vars(http),
        f'{PACKAGE}.database': {
            'get_db_connection': Mock(), 'invalidate_classmate': Mock(),
            'invalidate_registration': Mock(), 'json_value': lambda v: v,
            'remember_classmate_token': Mock(),
        },
        f'{PACKAGE}.config': {
            'BASE_URL': 'https://eschool.test/ec-server', 'USER_AGENT': 'eSchoolMobile',
            'MIN_CHECK_INTERVAL': 10, 'DEFAULT_CHECK_INTERVAL': 10,
        },
        f'{PACKAGE}.domain_manager': {name: Mock() for name in (
            'current_domain_status', 'get_domain_job', 'start_domain_job')},
        f'{PACKAGE}.ip_blacklist': {name: Mock() for name in ('get_ip_blacklist', 'set_ip_blacklist')},
        f'{PACKAGE}.tls_manager': {'tls_status': Mock()},
        f'{PACKAGE}.rate_limiter': {'rate_limit': lambda *a: lambda fn: fn},
        f'{PACKAGE}.logging_utils': {'log': Mock()},
        f'{PACKAGE}.utils': {
            'sha256_hash': lambda value: hashlib.sha256(value.encode()).hexdigest(),
            'generate_random_string': Mock(return_value='test-device'), 'get_random_device_model': Mock(return_value='test-phone'),
        },
        f'{PACKAGE}.routes.verification': {name: Mock() for name in (
            'find_verified_sender', 'get_verified_name', 'issue_verification_token', 'normalize_grade_class')},
        f'{PACKAGE}.notification_delivery': {name: Mock() for name in (
            'save_notification_history',
            'send_notification_with_telegram', 'send_telegram_relogin_notice', 'get_telegram_info')},
        f'{PACKAGE}.analysis': {},
        f'{PACKAGE}.chat_notifications': vars(chat),
        f'{PACKAGE}.eschool_api': {'get_eschool_version': Mock(return_value='3.0')},
        f'{PACKAGE}.telegram_bot': {name: Mock() for name in (
            'start_telegram_bot', 'stop_telegram_bot', 'restart_all_telegram_bots',
            'send_telegram_message', 'request_topic_detect', 'get_and_clear_detected_topic',
            'create_group_activation_code')},
        f'{PACKAGE}.encryption': {name: Mock() for name in (
            'init_encryption', 'encrypt_password', 'decrypt_password')},
        f'{PACKAGE}.keep_alive': {name: Mock() for name in (
            'update_session', 'get_session', 'mark_account_session_invalid')},
    })
    return module


class _PollingFixture(unittest.TestCase):
    def setUp(self):
        self.chat, self.http = make_chat()
        self.messages = []
        self.thread = {'id': 1, 'subject': 'Беседа класса', 'dlgType': 2, 'sender': 'Администратор'}
        self.checkpoint = {'cursor': 10, 'date': BASE_TIME + 10}
        self.events = []
        self.saved = []
        self.http.put.side_effect = self.page

    def page(self, url, *, params, **kwargs):
        self.assertTrue(url.endswith('/chat/messages'))
        self.assertEqual(params['rowStart'], 1)
        self.assertEqual(kwargs['json'], {'msgNums': None, 'searchText': None})
        self.assertEqual(kwargs['cookies'], {'session': 'test'})
        rows = self.messages
        cursor = params.get('msgStart')
        newer = params['getNew'] == 'true'
        if cursor is not None:
            rows = [m for m in rows if m['msgNum'] >= cursor] if newer else [m for m in rows if m['msgNum'] <= cursor]
        rows = sorted(rows, key=lambda m: m['msgNum'], reverse=not newer)
        return response(rows[:params['rowsCount']])

    def deliver(self, event, done):
        self.events.append(event)
        return True, {'push'}

    def persist(self):
        self.saved.append(deepcopy(self.checkpoint))

    def poll(self, deliver=None):
        self.chat.poll_thread({'session': 'test'}, {}, self.thread, OWN_ID, self.checkpoint,
                              deliver or self.deliver, self.persist)

class ChatPollingTests(_PollingFixture):
    def test_own_messages_advance_checkpoint_without_notification(self):
        self.messages = [message(11, OWN_ID, isOwner=False)]
        self.poll()
        self.poll()
        self.assertEqual(self.events, [])
        self.assertEqual(self.checkpoint['cursor'], 11)

    def test_group_uses_message_author_and_matching_names_do_not_hide_other_people(self):
        self.messages = [message(11, senderFio='Моё имя', isOwner=True, senderPrsId=OWN_ID)]
        self.poll()
        self.assertEqual(self.events[0]['title'], '💬 Беседа класса: Моё имя')
        self.assertEqual(self.events[0]['data'], {
            'type': 'message', 'id': '1', 'messageId': '1011', 'senderId': '90',
        })
        self.assertNotIn('Администратор', str(self.events))

    def test_incoming_before_own_reply_is_not_lost(self):
        self.messages = [message(11), message(12, 91), message(13, OWN_ID)]
        self.poll()
        self.assertEqual([e['data']['messageId'] for e in self.events], ['1011', '1012'])
        self.assertEqual(self.checkpoint['cursor'], 13)

    def test_identical_messages_and_timestamps_are_distinct(self):
        self.messages = [message(n, msg='Да', sendDate=BASE_TIME) for n in (11, 12)]
        self.poll()
        self.assertEqual(len(self.events), 2)

    def test_read_edit_delete_and_thread_rename_do_not_repeat_notifications(self):
        self.messages = [message(11)]
        self.poll()
        for changes in ({'stateId': 6}, {'msg': 'Правка'}, {'stateId': 1}):
            self.messages = [message(11, **changes)]
            self.thread['subject'] = 'Новое название'
            self.poll()
        self.assertEqual(len(self.events), 1)

    def test_full_history_pages_are_chronological_and_deduplicated(self):
        self.messages = [message(n) for n in range(10, 28)]
        self.poll()
        self.assertEqual([e['data']['messageId'] for e in self.events], [str(n + 1000) for n in range(11, 28)])
        self.assertGreater(self.http.put.call_count, 3)
        self.poll()
        self.assertEqual(len(self.events), 17)

    def test_attachment_only_and_html_messages_have_readable_bodies(self):
        self.messages = [message(11, msg='', attachInfo=[{'fileName': 'Задание.pdf'}]),
                         message(12, msg='<p>А &amp; Б</p><p>2 &lt; 3<br>Строка</p><script>secret()</script>')]
        self.poll()
        self.assertEqual(self.events[0]['body'], '📎 Задание.pdf')
        self.assertEqual(self.events[1]['body'], 'А & Б\n2 < 3\nСтрока')

    def test_drafts_and_deleted_messages_do_not_notify(self):
        self.messages = [message(11, stateId=1, senderId=None), message(12, stateId=0), message(13)]
        self.poll()
        self.assertEqual(len(self.events), 1)
        self.assertEqual(self.checkpoint['cursor'], 13)

    def test_missing_author_does_not_fall_back_to_thread_owner(self):
        self.messages = [message(11, senderId=None)]
        with self.assertRaises(self.chat.ChatFetchError):
            self.poll()
        self.assertEqual(self.checkpoint['cursor'], 10)
        self.assertEqual(self.events, [])

    def test_expired_or_invalid_response_preserves_checkpoint(self):
        for data, status in (([], 401), ({}, 200), ([], 500), ([{'msgId': -2}], 200)):
            with self.subTest(data=data, status=status):
                self.http.put.side_effect = None
                self.http.put.return_value = response(data, status)
                with self.assertRaises(self.chat.ChatFetchError):
                    self.poll()
                self.assertEqual(self.checkpoint['cursor'], 10)
                self.assertEqual(self.events, [])

    def test_bad_thread_identity_is_rejected(self):
        self.messages = [message(11, threadId=2)]
        with self.assertRaises(self.chat.ChatFetchError):
            self.poll()
        self.assertEqual(self.events, [])

    def test_retry_resumes_after_last_successful_page(self):
        self.messages = [message(n) for n in range(10, 17)]
        calls = 0
        def fetch(*args, **kwargs):
            nonlocal calls
            calls += 1
            return response([], 503) if calls == 2 else self.page(*args, **kwargs)
        self.http.put.side_effect = fetch
        with self.assertRaises(self.chat.ChatFetchError):
            self.poll()
        self.assertEqual(self.checkpoint['cursor'], 12)
        self.http.put.side_effect = self.page
        self.poll()
        self.assertEqual([e['data']['messageId'] for e in self.events], [str(n + 1000) for n in range(11, 17)])

    def test_partial_delivery_keeps_successful_channel_progress(self):
        self.messages = [message(11), message(12)]
        attempt = Mock(return_value=(False, {'push'}))
        self.poll(attempt)
        self.assertEqual(attempt.call_count, 2)
        self.assertEqual(self.checkpoint['cursor'], 10)
        self.assertEqual(self.checkpoint['delivered_through'], {'push': 12})
        def retry(event, done):
            self.assertEqual(done, {'push'})
            return True, {'push', 'telegram'}
        self.poll(retry)
        self.assertEqual(self.checkpoint['cursor'], 12)
        self.assertNotIn('delivered_through', self.checkpoint)

    def test_legacy_state_migrates_without_replaying_old_history(self):
        state = self.chat.load_state(json.dumps({'1': f'{BASE_TIME + 10}.0_Старый текст'}), [], BASE_TIME + 20)
        self.checkpoint = state['threads']['1']
        self.messages = [message(n) for n in range(8, 16)]
        self.poll()
        self.assertEqual([e['data']['messageId'] for e in self.events], [str(n + 1000) for n in range(11, 16)])
        self.assertNotIn('after_date', self.checkpoint)

    def test_registration_baseline_preserves_messages_arriving_after_registration(self):
        state = self.chat.initial_state([dict(self.thread, date=BASE_TIME + 10)], BASE_TIME + 10)
        self.checkpoint = state['threads']['1']
        self.messages = [message(9), message(10), message(11)]
        self.poll()
        self.assertEqual([e['data']['messageId'] for e in self.events], ['1011'])

    def test_thread_pagination_includes_more_than_twenty_chats(self):
        threads = [{'threadId': n, 'msgNum': n, 'sendDate': BASE_TIME + n} for n in range(1, 29)]
        def fetch(url, *, params, **kwargs):
            self.assertTrue(url.endswith('/chat/threads'))
            self.assertEqual(params['row'], 1)
            cursor = params.get('msgNum', 29)
            return response([t for t in reversed(threads) if t['msgNum'] <= cursor][:params['rowsCount']])
        self.http.get.side_effect = fetch
        found = self.chat.fetch_threads({}, {})
        self.assertEqual({t['id'] for t in found}, set(range(1, 29)))
        self.assertNotIn('sender', found[0])

    def test_stuck_thread_page_does_not_loop_or_look_like_empty_success(self):
        self.http.get.return_value = response([{'threadId': n, 'msgNum': n} for n in range(1, 4)])
        with self.assertRaises(self.chat.ChatFetchError):
            self.chat.fetch_threads({}, {})
        self.assertEqual(self.http.get.call_count, 2)

    def test_thread_list_retains_display_data_without_treating_group_creator_as_sender(self):
        self.http.get.return_value = response([
            {'threadId': 1, 'msgNum': 10, 'dlgType': 1, 'subject': ' ',
             'senderFio': 'Мария Ивановна', 'msgPreview': '<p>Добрый день</p>',
             'sendDate': BASE_TIME, 'showDate': BASE_TIME + 5000,
             'newReplayCount': 3, 'attachCount': 2},
            {'threadId': 2, 'msgNum': 11, 'dlgType': 2, 'subject': 'Класс',
             'senderFio': 'Создатель группы', 'msgPreview': 'Последнее сообщение',
             'sendDate': BASE_TIME, 'newReplayCount': 0},
        ])
        private, group = self.chat.fetch_threads({}, {})
        self.assertEqual(private['contactName'], 'Мария Ивановна')
        self.assertEqual(private['preview'], '<p>Добрый день</p>')
        self.assertEqual(private['unreadCount'], 3)
        self.assertEqual(private['attachmentCount'], 2)
        self.assertEqual(private['displayDate'], BASE_TIME + 5000)
        self.assertEqual(private['date'], BASE_TIME)
        self.assertEqual(group['contactName'], '')
        self.assertNotIn('sender', group)
        self.assertEqual(group['preview'], 'Последнее сообщение')

    def test_invalid_identifiers_are_not_owners_or_cursors(self):
        for value in (True, False, -1, 0, 3.5, {}, 'bad'):
            self.assertIsNone(self.chat.positive_id(value))
        for value in ('nan', 'inf', True, {}):
            self.assertIsNone(self.chat.timestamp(value))


class ChatIntegrationTests(_PollingFixture):
    def setUp(self):
        super().setUp()
        self.routes = make_routes(self.chat, self.http)
        self.registration = {'id': 'device', 'username': 'account',
                             'chat_forward_map': '{"1": 7}', 'last_check_at': None}
        self.telegram = {
            'telegram_enabled': True, 'telegram_bot_token': 'test-bot', 'telegram_user_id': '123',
            'telegram_group_enabled': True, 'telegram_group_chat_id': '-1001',
        }
        self.routes.get_telegram_info.return_value = self.telegram
        self.routes.save_notification_history.return_value = True
        self.routes.send_telegram_message.return_value = True
        self.connection = Mock()
        self.routes.get_db_connection.return_value = self.connection

    def test_same_actual_author_reaches_history_personal_and_group_telegram(self):
        self.registration['last_notification_ids'] = json.dumps({
            'version': 2, 'started_at': BASE_TIME, 'threads': {'1': self.checkpoint}})
        self.messages = [message(11), message(12, OWN_ID)]
        self.routes._check_chat_updates(self.registration, [self.thread], {'session': 'test'}, OWN_ID)
        push = self.routes.save_notification_history
        push.assert_called_once()
        self.assertEqual(push.call_args.args[2], '💬 Беседа класса: Настоящий автор')
        self.assertEqual(push.call_args.args[4]['messageId'], '1011')
        self.assertEqual(self.routes.send_telegram_message.call_count, 2)
        for call in self.routes.send_telegram_message.call_args_list:
            self.assertEqual(call.args[2], push.call_args.args[2])
        kwargs = self.routes.send_telegram_message.call_args.kwargs
        self.assertEqual(kwargs['message_thread_id'], 7)
        self.assertEqual(kwargs['notification_type'], 'message')
        self.assertEqual(kwargs['notification_data']['sender'], 'Настоящий автор')
        self.assertEqual(kwargs['notification_data']['subject'], 'Беседа класса')
        saved = json.loads(self.connection.cursor.return_value.execute.call_args.args[1][0])
        self.assertEqual(saved['threads']['1']['cursor'], 12)

    def test_telegram_failure_does_not_repeat_successful_history_or_personal_telegram(self):
        deliver = self.routes._chat_delivery(self.registration, self.telegram)
        event = self.chat.notification_event(self.thread, message(11), OWN_ID)
        self.routes.send_telegram_message.side_effect = [True, False, True]
        success, channels = deliver(event, set())
        self.assertFalse(success)
        self.assertEqual(channels, {'history', 'telegram:123'})
        deliver = self.routes._chat_delivery(self.registration, self.telegram)
        success, channels = deliver(event, channels)
        self.assertTrue(success)
        self.routes.save_notification_history.assert_called_once()
        self.assertEqual(self.routes.send_telegram_message.call_count, 3)

    def test_disabled_group_and_unmapped_threads_are_not_forwarded(self):
        for info, reg in ((dict(self.telegram, telegram_group_enabled=False), self.registration),
                          (self.telegram, dict(self.registration, chat_forward_map='{}'))):
            with self.subTest(info=info, reg=reg):
                self.routes.send_telegram_message.reset_mock()
                deliver = self.routes._chat_delivery(reg, info)
                deliver(self.chat.notification_event(self.thread, message(11), OWN_ID), set())
                self.routes.send_telegram_message.assert_called_once()
                self.assertEqual(self.routes.send_telegram_message.call_args.args[1], '123')

    def test_list_failure_preserves_saved_state_and_sends_nothing(self):
        state = {'version': 2, 'started_at': BASE_TIME, 'threads': {'1': self.checkpoint}}
        self.registration['last_notification_ids'] = json.dumps(state)
        self.routes._check_chat_updates(self.registration, None, {}, OWN_ID)
        saved = json.loads(self.connection.cursor.return_value.execute.call_args.args[1][0])
        self.assertEqual(saved, state)
        self.routes.save_notification_history.assert_not_called()
        self.routes.send_telegram_message.assert_not_called()

    def test_upgrade_during_chat_outage_keeps_original_boundary(self):
        self.registration['last_notification_ids'] = '{}'
        self.registration['last_check_at'] = datetime.fromtimestamp((BASE_TIME + 10) / 1000, tz=timezone.utc)
        self.routes._check_chat_updates(self.registration, None, {}, OWN_ID)
        self.registration['last_notification_ids'] = self.connection.cursor.return_value.execute.call_args.args[1][0]
        self.registration['last_check_at'] = datetime.fromtimestamp((BASE_TIME + 20) / 1000, tz=timezone.utc)
        self.messages = [message(11)]
        self.routes._check_chat_updates(self.registration, [self.thread], {'session': 'test'}, OWN_ID)
        self.routes.save_notification_history.assert_called_once()

    def test_history_expiration_pauses_account_without_notifying_from_preview(self):
        self.registration['last_notification_ids'] = json.dumps({'version': 2, 'started_at': BASE_TIME,
                                                               'threads': {'1': self.checkpoint}})
        self.http.put.side_effect = None
        self.http.put.return_value = response([], 401)
        self.routes._check_chat_updates(self.registration, [self.thread], {}, OWN_ID)
        self.routes.mark_account_session_invalid.assert_called_once_with('device', 'account', 'session_expired', notify=True)
        self.routes.save_notification_history.assert_not_called()

    def test_two_workers_cannot_check_the_same_registration(self):
        cursor = self.connection.cursor.return_value
        cursor.fetchone.return_value = {'locked': False}
        self.routes._check_user_for_updates = Mock()
        self.routes.check_user_for_updates(self.registration)
        self.routes._check_user_for_updates.assert_not_called()
        self.assertIn('pg_try_advisory_xact_lock', cursor.execute.call_args.args[0])
        self.connection.rollback.assert_called_once()
        self.connection.close.assert_called_once()

    def test_lock_refreshes_stale_checkpoint_and_releases_after_error(self):
        cursor = self.connection.cursor.return_value
        fresh = dict(self.registration, last_notification_ids='fresh')
        cursor.fetchone.side_effect = [{'locked': True}, fresh]
        self.routes._check_user_for_updates = Mock(side_effect=RuntimeError('private-body'))
        self.routes.check_user_for_updates(self.registration)
        self.routes._check_user_for_updates.assert_called_once_with(fresh)
        self.connection.rollback.assert_called_once()
        self.connection.close.assert_called_once()
        self.assertNotIn('private-body', str(self.routes.log.call_args_list))
        queries = [call.args[0] for call in cursor.execute.call_args_list]
        self.assertTrue(any('COALESCE(next_check_at' in query for query in queries))
        self.connection.commit.assert_called_once()

    def test_new_thread_after_previous_check_is_not_silently_baselined(self):
        self.registration['last_check_at'] = datetime.fromtimestamp((BASE_TIME + 10) / 1000, tz=timezone.utc)
        self.registration['last_notification_ids'] = json.dumps({'2': f'{BASE_TIME}_Старый чат'})
        self.messages = [message(11)]
        self.routes._check_chat_updates(self.registration, [self.thread], {'session': 'test'}, OWN_ID)
        self.routes.save_notification_history.assert_called_once()

    def test_telegram_outage_does_not_delay_following_history_entries(self):
        self.registration['last_notification_ids'] = json.dumps({
            'version': 2, 'started_at': BASE_TIME, 'threads': {'1': self.checkpoint}})
        self.messages = [message(11), message(12), message(13, OWN_ID)]
        self.routes.send_telegram_message.return_value = False
        self.routes._check_chat_updates(self.registration, [self.thread], {'session': 'test'}, OWN_ID)
        self.assertEqual(self.routes.save_notification_history.call_count, 2)
        self.assertEqual(self.routes.send_telegram_message.call_count, 2)
        saved = self.connection.cursor.return_value.execute.call_args.args[1][0]
        self.registration['last_notification_ids'] = saved
        self.routes.send_telegram_message.return_value = True
        self.routes.send_telegram_message.reset_mock()
        self.routes._check_chat_updates(self.registration, [self.thread], {'session': 'test'}, OWN_ID)
        self.assertEqual(self.routes.save_notification_history.call_count, 2)
        self.assertEqual(self.routes.send_telegram_message.call_count, 4)
        saved = json.loads(self.connection.cursor.return_value.execute.call_args.args[1][0])
        self.assertEqual(saved['threads']['1']['cursor'], 13)

    def test_database_failure_stops_delivery_before_losing_checkpoint(self):
        self.connection.cursor.return_value.execute.side_effect = RuntimeError('database unavailable')
        self.messages = [message(11)]
        with self.assertRaises(RuntimeError):
            self.routes._check_chat_updates(self.registration, [self.thread], {}, OWN_ID)
        self.routes.save_notification_history.assert_not_called()
        self.routes.send_telegram_message.assert_not_called()
        self.connection.close.assert_called_once()

    def test_unchanged_message_number_does_not_fetch_history(self):
        self.registration['last_notification_ids'] = json.dumps({
            'version': 2, 'started_at': BASE_TIME, 'threads': {'1': self.checkpoint}})
        self.routes._check_chat_updates(self.registration, [dict(self.thread, msgNum=10)], {}, OWN_ID)
        self.http.put.assert_not_called()
        self.routes.save_notification_history.assert_not_called()

    def test_first_chat_of_legacy_empty_account_is_not_lost(self):
        self.registration['last_check_at'] = datetime.fromtimestamp((BASE_TIME + 10) / 1000, tz=timezone.utc)
        self.registration['last_notification_ids'] = '{}'
        self.messages = [message(11)]
        self.routes._check_chat_updates(self.registration, [dict(self.thread, date=BASE_TIME + 11)], {'session': 'test'}, OWN_ID)
        self.routes.save_notification_history.assert_called_once()

    def test_both_login_paths_share_thread_fetching_and_report_chat_failures(self):
        self.routes._get_year_id = Mock(return_value=None)
        login_response = response({})
        login_response.cookies = {'session': 'test'}
        self.http.post.return_value = login_response
        status = 200
        def fetch(url, **kwargs):
            if url.endswith('/state'):
                return response({'user': {'prsId': OWN_ID}})
            if '/student/getPrsDiary?' in url:
                return response({})
            if url.endswith('/chat/threads'):
                self.assertEqual(kwargs['params']['row'], 1)
                return response([{'threadId': 1, 'senderFio': 'Админ', 'msgNum': 11}], status)
            self.fail(f'Unexpected URL: {url}')
        self.http.get.side_effect = fetch
        for call in (lambda: self.routes.fetch_data_with_session({'session': 'test'}, 'account'),
                     lambda: self.routes.login_and_get_data('account', 'test-password')):
            status = 200
            data = call()
            self.assertEqual(data[0], [])
            self.assertEqual(data[2][0]['id'], 1)
            self.assertNotIn('sender', data[2][0])
            status = 503
            data = call()
            self.assertEqual(data[0], [])
            self.assertIsNone(data[2])
        status = 401
        data = self.routes.fetch_data_with_session({'session': 'test'}, 'account')
        self.assertTrue(data[4])
        self.assertIsNone(data[0])

    def test_one_broken_chat_does_not_skip_other_chats(self):
        self.registration['last_notification_ids'] = json.dumps({
            'version': 2, 'started_at': BASE_TIME,
            'threads': {'1': self.checkpoint, '2': self.checkpoint}})
        def fetch(url, **kwargs):
            if kwargs['params']['threadId'] == 1:
                return response([], 503)
            return response([message(11, threadId=2)])
        self.http.put.side_effect = fetch
        self.routes._check_chat_updates(self.registration, [self.thread, dict(self.thread, id=2)], {}, OWN_ID)
        self.routes.save_notification_history.assert_called_once()
        self.assertEqual(self.routes.save_notification_history.call_args.args[4]['id'], '2')
        saved = json.loads(self.connection.cursor.return_value.execute.call_args.args[1][0])
        self.assertEqual(saved['threads']['1']['cursor'], 10)
        self.assertEqual(saved['threads']['2']['cursor'], 11)

    def test_history_and_telegram_preserve_full_message(self):
        event = self.chat.notification_event(dict(self.thread, subject='🧮' * 1000), message(11, msg='🙂' * 5000), OWN_ID)
        self.routes._chat_delivery(self.registration, self.telegram)(event, set())
        args = self.routes.save_notification_history.call_args.args
        self.assertEqual(args[2], event['title'])
        self.assertEqual(args[3], event['body'])
        self.assertEqual(args[4], event['data'])
        tg = self.routes.send_telegram_message.call_args.args
        self.assertEqual(tg[2], event['title'])
        self.assertEqual(tg[3], event['body'])


if __name__ == '__main__':
    unittest.main()
