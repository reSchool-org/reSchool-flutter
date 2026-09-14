"""храним доставку в базе, чтобы продолжить с неподтверждённой части после сбоя"""
import hashlib
import json
import random
import threading
from datetime import date, datetime
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import requests
from urllib3.exceptions import NewConnectionError

from .database import get_db_connection, json_value
from .encryption import encrypt_password, decrypt_password
from .logging_utils import log
from .telegram_diagnostics import delivery_log, error_details

MAX_ATTEMPTS = 8
_stop = threading.Event()
_thread = None
_wake = threading.Event()


class CheckpointError(RuntimeError):
    """телеграм ответил, но подтверждение не удалось записать в базу"""


def _json_default(value):
    if isinstance(value, (date, datetime)):
        return value.isoformat()
    raise TypeError(f'Unsupported delivery payload: {type(value).__name__}')


def _encode(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, default=_json_default)


def _digest(value):
    return hashlib.sha256(_encode(value).encode()).hexdigest()


def _fingerprint(payload):
    content = {key: value for key, value in payload.items()
               if key not in ('attachment_headers', 'attachment_cookies')}
    attachments = []
    for item in content.get('attachments') or []:
        item = dict(item)
        if isinstance(item.get('url'), str):
            parts = urlsplit(item['url'])
            query = [(key, value) for key, value in parse_qsl(parts.query, keep_blank_values=True)
                     if not any(s in key.lower() for s in ('token', 'session', 'signature', 'expires', 'secret', 'auth'))]
            item['url'] = urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), ''))
        attachments.append(item)
    content['attachments'] = attachments
    return _digest(content)


def enqueue_telegram_message(bot_token, user_id, title, body, *, connection=None, **kwargs):
    """с переданным соединением вызывающий код сам фиксирует или откатывает транзакцию"""
    if not bot_token or not user_id:
        delivery_log(log, 'enqueue_failed', reason='missing_bot_or_chat')
        return False
    conn = connection
    try:
        payload = dict(bot_token=bot_token, user_id=str(user_id), title=title, body=body, **kwargs)
        data = payload.get('notification_data') or {}
        # сравниваем только с последней версией оценки, иначе потеряем возврат прежнего значения
        # смена пятёрки на четвёрку и обратно должна дать три события
        source_id = str(data.get('messageId') or data.get('id') or '')[:128]
        kind = str(payload.get('notification_type') or 'notice')[:32]
        target = _digest([bot_token, str(user_id), payload.get('message_thread_id')])
        scope = _digest([target, kind, data.get('id') or title, source_id])
        digest = _fingerprint(payload)
        encrypted = encrypt_password(_encode(payload))
        if not encrypted:
            raise RuntimeError('Outbox encryption unavailable')
        if conn is None:
            conn = get_db_connection()
        if not conn:
            raise RuntimeError('Outbox database unavailable')
        cursor = conn.cursor()
        cursor.execute('SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))', ('outbox:' + scope,))
        cursor.execute('SELECT id, payload_hash, status FROM telegram_outbox WHERE event_scope = %s ORDER BY id DESC LIMIT 1', (scope,))
        row = cursor.fetchone()
        if row and row[1] == digest:
            outbox_id = row[0]
            event = 'enqueue_existing'
        else:
            cursor.execute('''
                INSERT INTO telegram_outbox
                    (target_key, event_scope, payload_hash, payload_encrypted, notification_type, source_id)
                VALUES (%s, %s, %s, %s, %s, %s) RETURNING id
            ''', (target, scope, digest, encrypted, kind, source_id))
            outbox_id = cursor.fetchone()[0]
            event = 'enqueued'
        if connection is None:
            conn.commit()
        cursor.close()
        delivery_log(log, event if connection is None else 'enqueue_staged',
                     outbox_id=outbox_id, notification_type=kind, source_id=source_id,
                     target=target[:12], existing_status=row[2] if event == 'enqueue_existing' else None)
        _wake.set()
        return True
    except Exception as error:
        delivery_log(log, 'enqueue_failed', **error_details(error, (bot_token,)))
        return False
    finally:
        if conn and connection is None:
            conn.close()


def retry_policy(error, attempt):
    """неопределённый результат нужно проверить перед повтором, иначе возможен дубль"""
    code = getattr(error, 'error_code', None)
    if isinstance(error, CheckpointError):
        return 'unknown', 0
    pending, visited, connection_not_started = [error], set(), False
    while pending:
        cause = pending.pop()
        if id(cause) in visited:
            continue
        visited.add(id(cause))
        if isinstance(cause, (requests.ConnectTimeout, NewConnectionError)):
            connection_not_started = True
        if isinstance(cause, BaseException):
            pending.extend(cause.args)
            pending.extend([cause.__cause__, cause.__context__, getattr(cause, 'reason', None)])
    if isinstance(error, (requests.ReadTimeout, requests.ConnectionError)) and not connection_not_started:
        return 'unknown', 0
    if code in (400, 401, 403, 404):
        return 'failed', 0
    if code is not None and code not in (429, 500, 502, 503, 504):
        return 'failed', 0
    retryable = connection_not_started or isinstance(error, OSError) or code in (429, 500, 502, 503, 504)
    if not retryable or attempt >= MAX_ATTEMPTS:
        return 'failed', 0
    delay = min(3600, 30 * 2 ** (attempt - 1)) + random.randint(0, 10)
    response = getattr(error, 'result_json', None) or {}
    retry_after = (response.get('parameters') or {}).get('retry_after', 0)
    if isinstance(retry_after, int):
        delay = max(delay, retry_after + 1)
    return 'retry', delay


def _claim():
    conn = get_db_connection()
    if not conn:
        delivery_log(log, 'outbox_database_unavailable')
        return None
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute('''
            UPDATE telegram_outbox SET status = 'unknown', locked_until = NULL,
                last_error = %s, updated_at = (now() AT TIME ZONE 'utc')
            WHERE status = 'sending' AND locked_until < (now() AT TIME ZONE 'utc')
            RETURNING id
        ''', (json_value({'reason': 'worker_interrupted; inspect message IDs before retry'}),))
        interrupted = cursor.fetchall()
        cursor.execute('''
            WITH candidate AS (
                SELECT q.id FROM telegram_outbox q
                WHERE q.status IN ('pending', 'retry')
                  AND q.next_attempt_at <= (now() AT TIME ZONE 'utc')
                  AND NOT EXISTS (
                      SELECT 1 FROM telegram_outbox earlier
                      WHERE earlier.target_key = q.target_key AND earlier.id < q.id
                        AND earlier.status IN ('pending', 'sending', 'retry'))
                ORDER BY q.next_attempt_at, q.id FOR UPDATE OF q SKIP LOCKED LIMIT 1
            )
            UPDATE telegram_outbox q SET status = 'sending', attempts = attempts + 1,
                locked_until = (now() AT TIME ZONE 'utc') + INTERVAL '30 minutes',
                updated_at = (now() AT TIME ZONE 'utc')
            FROM candidate WHERE q.id = candidate.id RETURNING q.*
        ''')
        row = cursor.fetchone()
        conn.commit()
        cursor.close()
        for item in interrupted:
            delivery_log(log, 'delivery_unknown', outbox_id=item['id'], reason='worker_interrupted')
        return row
    finally:
        conn.close()


def _checkpoint(outbox_id, progress):
    conn = None
    try:
        encrypted = encrypt_password(_encode(progress))
        if not encrypted:
            raise CheckpointError('Progress encryption unavailable')
        conn = get_db_connection()
        if not conn:
            raise CheckpointError('Progress database unavailable')
        cursor = conn.cursor()
        cursor.execute('''
            UPDATE telegram_outbox SET progress_encrypted = %s,
                locked_until = (now() AT TIME ZONE 'utc') + INTERVAL '30 minutes',
                updated_at = (now() AT TIME ZONE 'utc')
            WHERE id = %s AND status = 'sending' RETURNING id
        ''', (encrypted, outbox_id))
        if not cursor.fetchone():
            raise CheckpointError('Delivery claim lost')
        conn.commit()
        cursor.close()
    except Exception as error:
        raise CheckpointError('Delivery progress not persisted') from error
    finally:
        if conn:
            conn.close()


def process_one():
    row = _claim()
    if not row:
        return False
    outbox_id, attempt = row['id'], row['attempts']
    delivery_log(log, 'attempt_started', outbox_id=outbox_id, attempt=attempt,
                 notification_type=row['notification_type'], source_id=row['source_id'])
    details, delay, payload = None, 0, {}
    try:
        payload = json.loads(decrypt_password(row['payload_encrypted']) or '')
        progress = json.loads(decrypt_password(row['progress_encrypted']) or '{}') if row['progress_encrypted'] else {}
        from .telegram_bot import send_telegram_message
        ok = send_telegram_message(**payload, progress=progress,
                                   checkpoint=lambda value: _checkpoint(outbox_id, value),
                                   raise_errors=True, delivery_id=f'outbox:{outbox_id}:{attempt}')
        if not ok:
            raise RuntimeError('Incomplete delivery')
        status = 'sent'
    except Exception as error:
        status, delay = retry_policy(error, attempt)
        details = error_details(error, (payload.get('bot_token'),))
    conn = get_db_connection()
    if not conn:
        delivery_log(log, 'outcome_save_failed', outbox_id=outbox_id, outcome=status)
        return True
    try:
        cursor = conn.cursor()
        cursor.execute('''
            UPDATE telegram_outbox SET status = %s, last_error = %s, locked_until = NULL,
                next_attempt_at = (now() AT TIME ZONE 'utc') + %s * INTERVAL '1 second',
                sent_at = CASE WHEN %s = 'sent' THEN (now() AT TIME ZONE 'utc') ELSE NULL END,
                updated_at = (now() AT TIME ZONE 'utc')
            WHERE id = %s AND status = 'sending'
        ''', (status, json_value(details), delay, status, outbox_id))
        conn.commit()
        cursor.close()
    finally:
        conn.close()
    delivery_log(log, 'attempt_finished', outbox_id=outbox_id, attempt=attempt,
                 status=status, retry_in_seconds=delay, error=details)
    return True


def _loop():
    delivery_log(log, 'outbox_worker_started')
    while not _stop.is_set():
        try:
            if process_one():
                continue
        except Exception as error:
            delivery_log(log, 'outbox_worker_error', **error_details(error))
        _wake.wait(5)
        _wake.clear()


def start():
    global _thread
    if _thread and _thread.is_alive():
        return
    _stop.clear()
    _thread = threading.Thread(target=_loop, name='telegram-outbox', daemon=True)
    _thread.start()


def stop():
    _stop.set()
    _wake.set()
    if _thread:
        _thread.join(timeout=5)
