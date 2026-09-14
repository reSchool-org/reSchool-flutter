import json
import math
import time
from copy import deepcopy
from html.parser import HTMLParser

import requests

from .config import BASE_URL


PAGE_SIZE = 50
STATE_VERSION = 2


class ChatFetchError(Exception):
    pass


class ChatSessionExpired(ChatFetchError):
    pass


def positive_id(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int) and value > 0:
        return value
    if isinstance(value, str) and value.isascii() and value.isdecimal():
        parsed = int(value)
        return parsed if parsed > 0 else None
    return None


def timestamp(value):
    if isinstance(value, bool):
        return None
    try:
        parsed = float(value)
        return int(parsed) if math.isfinite(parsed) and parsed > 0 else None
    except (TypeError, ValueError, OverflowError):
        return None


def _response_list(response):
    if response.status_code == 401:
        raise ChatSessionExpired('Chat session expired')
    if response.status_code != 200:
        raise ChatFetchError(f'Chat returned HTTP {response.status_code}')
    try:
        data = response.json()
    except (ValueError, TypeError) as exc:
        raise ChatFetchError('Invalid chat response') from exc
    if not isinstance(data, list) or any(not isinstance(item, dict) for item in data):
        raise ChatFetchError('Expected a chat list')
    return data


def fetch_threads(cookies, headers):
    threads = {}
    cursor = None
    row = 1
    while True:
        params = {'newOnly': 'false', 'row': row, 'rowsCount': PAGE_SIZE}
        if cursor is not None:
            params['msgNum'] = cursor
        page = _response_list(requests.get(
            f'{BASE_URL}/chat/threads', params=params,
            headers=headers, cookies=cookies, timeout=30,
        ))
        added = 0
        for item in page:
            thread_id = positive_id(item.get('threadId'))
            if thread_id is None:
                raise ChatFetchError('Invalid thread ID')
            if thread_id not in threads:
                added += 1
                threads[thread_id] = {
                    'id': thread_id,
                    'subject': item.get('subject') or '',
                    'dlgType': item.get('dlgType'),
                    'date': item.get('sendDate'),
                    'msgNum': positive_id(item.get('msgNum')),
                    'displayDate': timestamp(item.get('showDate')) or timestamp(item.get('sendDate')),
                    'preview': item.get('msgPreview') or '',
                    # в личном диалоге это собеседник, в группе это создатель беседы
                    'contactName': item.get('senderFio') if str(item.get('dlgType')) == '1' else '',
                    'unreadCount': positive_id(item.get('newReplayCount')) or 0,
                    'attachmentCount': positive_id(item.get('attachCount')) or 0,
                }
        if len(page) < PAGE_SIZE:
            return list(threads.values())
        next_cursor = positive_id(page[-1].get('msgNum'))
        if not added or (cursor is not None and next_cursor == cursor):
            raise ChatFetchError('Thread pagination did not advance')
        cursor = next_cursor
        row = 1 if cursor is not None else row + len(page)


def _message_page(cookies, headers, thread_id, cursor=None, newer=False):
    params = {
        'threadId': thread_id, 'rowStart': 1, 'rowsCount': PAGE_SIZE,
        'getNew': str(newer).lower(), 'isSearch': 'false',
    }
    if cursor is not None:
        params['msgStart'] = cursor
    page = _response_list(requests.put(
        f'{BASE_URL}/chat/messages', params=params,
        headers={**headers, 'Content-Type': 'application/json;charset=UTF-8'},
        cookies=cookies, json={'msgNums': None, 'searchText': None}, timeout=30,
    ))
    messages = {}
    for item in page:
        message_id = positive_id(item.get('msgId'))
        number = positive_id(item.get('msgNum'))
        if message_id is None or number is None:
            raise ChatFetchError('Invalid message identity')
        if item.get('threadId') is not None and positive_id(item['threadId']) != thread_id:
            raise ChatFetchError('Message belongs to another thread')
        messages[message_id] = dict(item, msgId=message_id, msgNum=number)
    return sorted(messages.values(), key=lambda item: item['msgNum']), len(page)


def messages_since(cookies, headers, thread_id, checkpoint):
    cursor = positive_id(checkpoint.get('cursor'))
    if cursor is not None:
        while True:
            page, count = _message_page(cookies, headers, thread_id, cursor, newer=True)
            fresh = [message for message in page if message['msgNum'] > cursor]
            yield from fresh
            if count < PAGE_SIZE:
                return
            if not fresh:
                raise ChatFetchError('Message pagination did not advance')
            cursor = fresh[-1]['msgNum']
    else:
        # старое состояние знает только дату, поэтому сначала находим границу истории
        cutoff = timestamp(checkpoint.get('after_date')) or 0
        found = {}
        while True:
            page, count = _message_page(cookies, headers, thread_id, cursor)
            for message in page:
                sent = timestamp(message.get('sendDate'))
                if sent is None:
                    raise ChatFetchError('Message has no send date')
                found[message['msgId']] = message
            if not page or count < PAGE_SIZE or any(timestamp(m.get('sendDate')) <= cutoff for m in page):
                break
            next_cursor = page[0]['msgNum']
            if cursor is not None and next_cursor >= cursor:
                raise ChatFetchError('Message pagination did not advance')
            cursor = next_cursor
        yield from sorted(found.values(), key=lambda item: item['msgNum'])


def initial_state(threads, now_ms=None):
    now_ms = timestamp(now_ms) or int(time.time() * 1000)
    return {
        'version': STATE_VERSION,
        'started_at': now_ms,
        'threads': {
            str(thread['id']): {'after_date': timestamp(thread.get('date')) or now_ms}
            for thread in threads if positive_id(thread.get('id')) is not None
        },
    }


def load_state(raw, threads, now_ms=None, previous_check_ms=None):
    now_ms = timestamp(now_ms) or int(time.time() * 1000)
    try:
        parsed = json.loads(raw) if isinstance(raw, str) else deepcopy(raw)
    except (ValueError, TypeError):
        parsed = None
    if not isinstance(parsed, dict):
        return initial_state(threads, now_ms)
    if parsed.get('version') == STATE_VERSION and isinstance(parsed.get('threads'), dict):
        parsed['started_at'] = timestamp(parsed.get('started_at')) or now_ms
        return parsed
    # подписи предыдущей версии нужны только для тихого перехода к номерам сообщений
    converted = {}
    for key, value in parsed.items():
        thread_id = positive_id(key)
        date = timestamp(value.split('_', 1)[0]) if isinstance(value, str) else None
        if thread_id and date:
            converted[str(thread_id)] = {'after_date': date}
    if not converted and timestamp(previous_check_ms) is None:
        return initial_state(threads, now_ms)
    return {
        'version': STATE_VERSION,
        'started_at': timestamp(previous_check_ms) or now_ms,
        'threads': converted,
    }


class _MessageText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []
        self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ('script', 'style'):
            self.hidden += 1
        elif not self.hidden:
            if tag in ('br', 'p', 'div', 'li', 'tr'):
                self.parts.append('\n')
            elif tag == 'img':
                self.parts.append(dict(attrs).get('alt') or '[Изображение]')

    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.hidden = max(0, self.hidden - 1)
        elif not self.hidden and tag in ('p', 'div', 'li', 'tr'):
            self.parts.append('\n')

    def handle_data(self, data):
        if not self.hidden:
            self.parts.append(data)


def message_text(message):
    parser = _MessageText()
    parser.feed(str(message.get('msg') or ''))
    text = '\n'.join(line.strip() for line in ''.join(parser.parts).splitlines() if line.strip())
    if text:
        return text
    files = message.get('attachInfo') or []
    names = [str(file['fileName']) for file in files if isinstance(file, dict) and file.get('fileName')]
    if names:
        return '📎 ' + ', '.join(names)
    if message.get('attachCount') or files:
        return '[Вложение]'
    return '[Сообщение без текста]'


def notification_event(thread, message, own_prs_id):
    state_id = message.get('stateId')
    if isinstance(state_id, int) and state_id <= 1:
        return None
    sender_id = positive_id(message.get('senderId'))
    if sender_id is None:
        # имя и аватар не подтверждают автора, ждём нормального ответа сервера
        raise ChatFetchError('Message has no sender ID')
    if sender_id == own_prs_id:
        return None
    sender = str(message.get('senderFio') or '').strip() or 'Участник беседы'
    subject = str(thread.get('subject') or '').strip()
    title = f'💬 {subject or "Групповая беседа"}: {sender}' if thread.get('dlgType') == 2 else f'💬 Новое сообщение от {sender}'
    return {
        'title': title,
        'body': message_text(message),
        'telegram': {
            'sender': sender, 'subject': subject if thread.get('dlgType') == 2 else '',
            'sent_at': message.get('sendDate'),
        },
        'data': {
            'type': 'message', 'id': str(thread['id']),
            'messageId': str(message['msgId']), 'senderId': str(sender_id),
            'msgNum': message.get('msgNum'), 'isGroup': thread.get('dlgType') == 2,
        },
    }


def poll_thread(cookies, headers, thread, own_prs_id, checkpoint, deliver, persist):
    if positive_id(own_prs_id) is None:
        raise ChatFetchError('Account has no person ID')
    own_prs_id = positive_id(own_prs_id)
    cutoff = timestamp(checkpoint.get('after_date'))
    delivered = checkpoint.setdefault('delivered_through', {})
    blocked = False
    for message in messages_since(cookies, headers, thread['id'], checkpoint):
        sent = timestamp(message.get('sendDate'))
        if sent is None:
            raise ChatFetchError('Message has no send date')
        # при переходе со старой версии прошлую переписку не рассылаем заново
        event = None if cutoff is not None and sent <= cutoff else notification_event(thread, message, own_prs_id)
        if event is not None:
            completed = {key for key, number in delivered.items() if number >= message['msgNum']}
            success, channels = deliver(event, completed)
            for key in channels:
                delivered[key] = max(delivered.get(key, 0), message['msgNum'])
            blocked = blocked or not success
        if not blocked:
            checkpoint.update(cursor=message['msgNum'], message_id=message['msgId'], date=sent)
        # исходящее тоже двигает курсор, чтобы снова не разбирать его на каждом проходе
        persist()
    if not blocked and checkpoint.get('cursor') is not None:
        checkpoint.pop('after_date', None)
        checkpoint.pop('delivered_through', None)
        persist()
