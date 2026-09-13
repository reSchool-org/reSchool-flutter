"""подключение к облаку с явным выбором доступа к аккаунту"""

import hashlib
import hmac
import json
import re
import secrets
import time
import uuid
from functools import lru_cache
import requests

from flask import Blueprint, g, jsonify, request
from telebot import TeleBot

from .. import chat_notifications
from ..cloud_access import account_primary, server_bot, restart_server_bot
from ..account_class import resolve_account_class
from ..config import BASE_URL, USER_AGENT, MIN_CHECK_INTERVAL, DEFAULT_CHECK_INTERVAL
from ..check_schedule import MAX_CHECK_INTERVAL
from ..database import get_db_connection, invalidate_classmate, invalidate_verified_user, invalidate_registration, load_user_session
from ..encryption import encrypt_password, decrypt_password, init_encryption
from ..keep_alive import update_session, get_session
from ..logging_utils import log
from ..rate_limiter import rate_limit
from ..telegram_bot import send_telegram_message, start_telegram_bot, stop_telegram_bot, restart_all_telegram_bots
from .verification import normalize_grade_class, get_verified_name
from .notifications import (
    login_and_get_data, _hash_registration_secret, _require_registration_owner,
    _compute_homework_hash, _compute_grade_hash, _save_item_hashes,
)

bp = Blueprint('cloud', __name__)


def _data():
    data = request.get_json(silent=True)
    return data if isinstance(data, dict) else {}


def _hash(value):
    return hashlib.sha256(value.encode()).hexdigest()


def _text(data, key, limit):
    value = data.get(key)
    return value.strip() if isinstance(value, str) and len(value) <= limit else ''


def _telegram_id(value):
    return isinstance(value, str) and re.fullmatch(r'[1-9][0-9]{0,15}', value) is not None


@lru_cache(maxsize=128)
def _telegram_bot_username(token, cache_period):
    """кэшируем имя и временные ошибки на пять минут, отдельно для каждого токена"""
    try:
        response = requests.get(f'https://api.telegram.org/bot{token}/getMe', timeout=5)
        response.raise_for_status()
        data = response.json()
        if data.get('ok'):
            return (data['result'].get('username') or '').strip()
    except (requests.RequestException, ValueError, KeyError, TypeError, AttributeError):
        pass
    return ''


@bp.route('/cloud/invites', methods=['POST'])
@rate_limit('devices')
def create_invite():
    grade_class = normalize_grade_class(_data().get('gradeClass'))
    if not grade_class:
        return jsonify(error='Укажите класс для приглашения'), 400
    token = secrets.token_urlsafe(32)
    conn = get_db_connection()
    if not conn:
        return jsonify(error='База данных недоступна'), 503
    cursor = conn.cursor()
    try:
        cursor.execute('DELETE FROM cloud_invites WHERE expires_at < LOCALTIMESTAMP')
        cursor.execute('''INSERT INTO cloud_invites (token_hash, grade_class, expires_at)
                          VALUES (%s, %s, LOCALTIMESTAMP + INTERVAL '1 hour')''', (_hash(token), grade_class))
        conn.commit()
        return jsonify(inviteToken=token, expiresInMinutes=60, gradeClass=grade_class)
    finally:
        cursor.close()
        conn.close()


@bp.route('/cloud/join', methods=['POST'])
@bp.route('/cloud/account', methods=['POST'])
@rate_limit('notification_register')
def join():
    data = _data()
    admin = request.path == '/cloud/account'
    mode = 'admin' if admin else data.get('mode')
    if not admin and mode not in ('user', 'classmate'):
        return jsonify(error='Выберите режим подключения'), 400
    invite = _text(data, 'inviteToken', 128)
    if not admin and not invite:
        return jsonify(error='Нужно приглашение администратора'), 400
    username = _text(data, 'username', 256)
    password = data.get('password')
    if mode == 'classmate' and any(key in data for key in ('username', 'password', 'telegramUserId', 'telegramBotToken')):
        return jsonify(error='Этот режим не принимает данные eSchool и Telegram'), 400
    request_id = _text(data, 'requestId', 64)
    if not re.fullmatch(r'[a-zA-Z0-9_-]{16,64}', request_id):
        return jsonify(error='Не найден идентификатор попытки подключения'), 400
    request_hash = _hash(request_id + ':' + ('admin' if admin else invite))
    if 'telegramBotToken' in data:
        return jsonify(error='Бота настраивает администратор отдельно'), 400
    user_id = _text(data, 'telegramUserId', 16)
    if user_id and not _telegram_id(user_id):
        return jsonify(error='Telegram ID должен быть положительным числом'), 400
    interval = data.get('checkIntervalMinutes', DEFAULT_CHECK_INTERVAL)
    if type(interval) is not int or interval > 1440:
        return jsonify(error='Интервал должен быть от 10 до 1440 минут'), 400
    interval = max(MIN_CHECK_INTERVAL, interval)
    full_name = _text(data, 'fullName', 256) or 'Пользователь'
    grade_class = normalize_grade_class(data.get('gradeClass'))
    device_name = _text(data, 'deviceName', 128) or 'reSchool'
    registration_id = None
    verification_token = None
    registration_secret = None
    cookies = None
    hw, grades, threads = [], [], []
    if mode != 'classmate':
        if not username or not isinstance(password, str) or not 0 < len(password) <= 4096:
            return jsonify(error='Войдите в eSchool заново, логин и пароль недоступны'), 400
        if not init_encryption():
            return jsonify(error='На сервере не настроено шифрование'), 503
        # приглашение проверяем до обращения к eSchool, затем ещё раз под блокировкой
    conn = get_db_connection()
    if not conn:
        return jsonify(error='База данных недоступна'), 503
    cursor = conn.cursor(dictionary=True)
    try:
        # одинаковая попытка ждёт первый запрос, а затем получает его результат
        lock_key = int.from_bytes(bytes.fromhex(request_hash[:16]), 'big', signed=True)
        cursor.execute('SELECT pg_advisory_xact_lock(%s)', (lock_key,))
        cursor.execute('SELECT result_encrypted FROM cloud_join_attempts WHERE request_hash = %s AND expires_at > LOCALTIMESTAMP', (request_hash,))
        previous = cursor.fetchone()
        if previous:
            result = json.loads(decrypt_password(previous['result_encrypted']))
            if result['role'] != mode:
                return jsonify(error='Эта попытка относится к другому режиму'), 409
            return jsonify(result)
        if not admin:
            cursor.execute('''SELECT grade_class FROM cloud_invites WHERE token_hash = %s
                              AND used_at IS NULL AND expires_at > LOCALTIMESTAMP''', (_hash(invite),))
            inv = cursor.fetchone()
            if not inv:
                return jsonify(error='Приглашение недействительно, истекло или уже использовано'), 401
            grade_class = inv['grade_class']
        if not grade_class and not admin:
            return jsonify(error='Не удалось определить класс аккаунта'), 400
        if mode != 'classmate':
            hw, grades, threads, _, cookies, prs_id = login_and_get_data(username, password)
            if hw is None or type(prs_id) is not int or prs_id <= 0:
                return jsonify(error='Не удалось войти в eSchool, проверьте логин и пароль'), 401
            full_name = get_verified_name(prs_id, cookies)
            if not full_name:
                return jsonify(error='eSchool не вернул профиль аккаунта, попробуйте позже'), 503
            if admin and not grade_class:
                grade_class = resolve_account_class(cookies, prs_id)
            if not grade_class:
                return jsonify(error='Не удалось определить класс аккаунта. Укажите класс во вкладке «Обзор»'), 400
            encrypted = encrypt_password(password)
            if not encrypted:
                return jsonify(error='Не удалось зашифровать пароль'), 503
            registration_id = str(uuid.uuid4())
            registration_secret = secrets.token_urlsafe(32)
            if admin:
                verification_token = str(uuid.uuid4())
                cursor.execute('''INSERT INTO verified_users (token, prs_id, device_name, full_name, grade_class)
                                  VALUES (%s, %s, %s, %s, %s)''',
                               (verification_token, prs_id, device_name, full_name, grade_class))
        if not admin:
            # только один из одновременных входов сможет забрать приглашение
            cursor.execute('''UPDATE cloud_invites SET used_at = LOCALTIMESTAMP WHERE token_hash = %s
                              AND used_at IS NULL AND expires_at > LOCALTIMESTAMP RETURNING grade_class''', (_hash(invite),))
            if not cursor.fetchone():
                conn.rollback()
                return jsonify(error='Приглашение уже использовано или истекло'), 409
        if registration_id:
            cursor.execute('''INSERT INTO cf3_registrations
                (id, username, full_name, grade_class, password_encrypted,
                 check_interval_minutes, verification_token, registration_secret_hash,
                 last_homework_ids, last_grade_ids, last_notification_ids, cloud_role,
                 telegram_enabled, telegram_user_id)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)''',
                (registration_id, username, full_name, grade_class, encrypted,
                 interval, verification_token, _hash_registration_secret(registration_secret),
                 json.dumps([int(h['id']) for h in (hw or []) if h.get('id') is not None]),
                 json.dumps([int(m['id']) for m in (grades or []) if m.get('id') is not None]),
                 json.dumps(chat_notifications.initial_state(threads or [])), mode, bool(user_id), user_id or None))
            _save_item_hashes(conn, registration_id, 'homework', {
                str(h['id']): _compute_homework_hash(h) for h in (hw or []) if h.get('id') is not None})
            _save_item_hashes(conn, registration_id, 'grade', {
                str(m['id']): _compute_grade_hash(m) for m in (grades or []) if m.get('id') is not None})
        member_id, member_token = None, None
        if not admin:
            member_id, member_token = str(uuid.uuid4()), secrets.token_urlsafe(32)
            cursor.execute('''INSERT INTO classmate_registrations
                (id, display_name, grade_class, device_name, classmate_token, monitoring_registration_id)
                VALUES (%s, %s, %s, %s, %s, %s)''',
                (member_id, full_name, grade_class, device_name, member_token, registration_id))
        interval_max = None
        if registration_id:
            cursor.execute('SELECT check_interval_minutes, check_interval_max_minutes FROM cf3_registrations WHERE id = %s',
                           (registration_id,))
            saved = cursor.fetchone()
            interval, interval_max = saved['check_interval_minutes'], saved['check_interval_max_minutes']
        result = dict(success=True, role=mode, registrationId=registration_id,
                      registrationSecret=registration_secret, verificationToken=verification_token,
                      classmateId=member_id, apiToken=member_token, gradeClass=grade_class,
                      checkIntervalMinutes=interval, checkIntervalMaxMinutes=interval_max)
        encrypted_result = encrypt_password(json.dumps(result))
        if not encrypted_result:
            raise RuntimeError('connection encryption unavailable')
        cursor.execute('DELETE FROM cloud_join_attempts WHERE expires_at < LOCALTIMESTAMP')
        cursor.execute('''INSERT INTO cloud_join_attempts (request_hash, result_encrypted, registration_id, classmate_id)
            VALUES (%s, %s, %s, %s)''', (request_hash, encrypted_result, registration_id, member_id))
        conn.commit()
    except Exception as exc:
        conn.rollback()
        log(f'[Cloud] Join failed: {type(exc).__name__}')
        return jsonify(error='Не удалось сохранить подключение'), 503
    finally:
        cursor.close()
        conn.close()
    # регистрация уже сохранена, сбой необязательных доставок не должен расходовать приглашение повторно
    try:
        if registration_id:
            update_session(registration_id, cookies)
    except Exception as exc:
        log(f'[Cloud] Delivery setup delayed: {type(exc).__name__}')
    return jsonify(result)


@bp.route('/cloud/account/attach', methods=['POST'])
@rate_limit('devices')
def attach_account():
    """привязать установку к уже включённому аккаунту без нового входа в eSchool"""
    data = _data()
    username = _text(data, 'username', 256)
    request_id = _text(data, 'requestId', 64)
    proof = _text(data, 'accountCredentialProof', 64)
    if (not username or not re.fullmatch(r'[a-zA-Z0-9_-]{16,64}', request_id)
            or not re.fullmatch(r'[0-9a-f]{64}', proof)):
        return jsonify(error='Не удалось подтвердить аккаунт для подключения'), 400
    if getattr(g, 'cloud_role', None) != 'admin':
        return jsonify(error='Нужен доступ администратора'), 403
    if not init_encryption():
        return jsonify(error='На сервере не настроено шифрование'), 503
    # знание логина и ключа сервера не раскрывает чужой секрет регистрации
    # пароль не передаётся: проверяем HMAC с уже сохранённым на сервере паролем
    request_hash = _hash('attach:' + username + ':' + request_id + ':' + proof)
    conn = get_db_connection()
    if not conn:
        return jsonify(error='База данных недоступна'), 503
    cursor = conn.cursor(dictionary=True)
    try:
        lock_key = int.from_bytes(bytes.fromhex(request_hash[:16]), 'big', signed=True)
        cursor.execute('SELECT pg_advisory_xact_lock(%s)', (lock_key,))
        cursor.execute('''SELECT r.*, v.prs_id FROM cf3_registrations r
            JOIN verified_users v ON v.token = r.verification_token
            WHERE r.username = %s AND r.cloud_role = 'admin' ORDER BY r.created_at, r.id''', (username,))
        candidates = cursor.fetchall()
        if not candidates:
            return jsonify(monitoring=False)
        source = None
        message = f'reschool:attach:{request_id}:{username}'.encode()
        for candidate in candidates:
            password = decrypt_password(candidate['password_encrypted'])
            expected = hmac.new(password.encode(), message, hashlib.sha256).hexdigest()
            if hmac.compare_digest(expected, proof):
                source = candidate
                break
        if source is None:
            return jsonify(error='Пароль аккаунта на сервере отличается. Обновите вход в eSchool'), 409
        cursor.execute('''SELECT result_encrypted FROM cloud_join_attempts
            WHERE request_hash = %s AND expires_at > LOCALTIMESTAMP''', (request_hash,))
        previous = cursor.fetchone()
        if previous:
            return jsonify(json.loads(decrypt_password(previous['result_encrypted'])))

        registration_id, verification_token = str(uuid.uuid4()), str(uuid.uuid4())
        secret = secrets.token_urlsafe(32)
        device_name = _text(data, 'deviceName', 128) or 'reSchool'
        cursor.execute('''INSERT INTO verified_users (token, prs_id, device_name, full_name, grade_class)
            VALUES (%s, %s, %s, %s, %s)''', (verification_token, source['prs_id'], device_name,
                                           source['full_name'], source['grade_class']))
        cursor.execute('''INSERT INTO cf3_registrations
            (id, username, full_name, grade_class, password_encrypted,
             verification_token, registration_secret_hash, cloud_role, last_check_at,
             next_check_at, last_homework_ids, last_grade_ids, last_notification_ids,
             known_subjects, session_invalid, session_invalid_reason, session_invalid_at)
            SELECT %s, username, full_name, grade_class, password_encrypted, %s, %s,
                'admin', last_check_at, next_check_at, last_homework_ids, last_grade_ids,
                last_notification_ids, known_subjects, session_invalid, session_invalid_reason, session_invalid_at
            FROM cf3_registrations WHERE id = %s
            RETURNING check_interval_minutes, check_interval_max_minutes''',
            (registration_id, verification_token, _hash_registration_secret(secret), source['id']))
        saved = cursor.fetchone()
        if not saved:
            raise RuntimeError('Source registration removed')
        cursor.execute('''INSERT INTO cf3_item_hashes (registration_id, item_type, item_id, content_hash)
            SELECT %s, item_type, item_id, content_hash FROM cf3_item_hashes WHERE registration_id = %s''',
            (registration_id, source['id']))
        cursor.execute('''INSERT INTO cf3_sessions (registration_id, cookies)
            SELECT %s, cookies FROM cf3_sessions WHERE registration_id = %s''', (registration_id, source['id']))
        result = dict(success=True, monitoring=True, role='admin', registrationId=registration_id,
            registrationSecret=secret, verificationToken=verification_token, gradeClass=source['grade_class'],
            checkIntervalMinutes=saved['check_interval_minutes'],
            checkIntervalMaxMinutes=saved['check_interval_max_minutes'])
        encrypted_result = encrypt_password(json.dumps(result))
        if not encrypted_result:
            raise RuntimeError('Connection encryption unavailable')
        cursor.execute('DELETE FROM cloud_join_attempts WHERE expires_at < LOCALTIMESTAMP')
        cursor.execute('''INSERT INTO cloud_join_attempts (request_hash, result_encrypted, registration_id)
            VALUES (%s, %s, %s)''', (request_hash, encrypted_result, registration_id))
        conn.commit()
    except Exception as exc:
        conn.rollback()
        log(f'[Cloud] Account attach failed: {type(exc).__name__}')
        return jsonify(error='Не удалось восстановить подключение к мониторингу'), 503
    finally:
        cursor.close()
        conn.close()
    return jsonify(result)


@bp.route('/cloud/status', methods=['POST'])
def status():
    data = _data()
    role = getattr(g, 'cloud_role', 'admin')
    registration_id = getattr(g, 'cloud_registration_id', None) if role != 'admin' else data.get('registrationId')
    if role == 'admin' and registration_id:
        error = _require_registration_owner(registration_id, data)
        if error:
            return error
    bot = server_bot()
    bot_token = bot['token'] if bot else None
    result = dict(role=role, monitoring=False, telegramBotConfigured=bool(bot),
                  telegramBotUsername=bot['username'] if bot else '', minCheckIntervalMinutes=MIN_CHECK_INTERVAL,
                  maxCheckIntervalMinutes=MAX_CHECK_INTERVAL, randomCheckIntervalSupported=True)
    if registration_id:
        conn = get_db_connection()
        if not conn:
            return jsonify(error='База данных недоступна'), 503
        cursor = conn.cursor(dictionary=True)
        try:
            # Статус мониторинга относится к той же регистрации, что и команды
            # Telegram. Сессия устройства для /cloud/session остаётся отдельной.
            cursor.execute('''SELECT username, full_name, grade_class, check_interval_minutes, check_interval_max_minutes,
                telegram_enabled, telegram_user_id, telegram_bot_token, session_invalid, last_check_at
                FROM cf3_registrations WHERE id = COALESCE(cf3_account_primary(%s), %s)''',
                (registration_id, registration_id))
            row = cursor.fetchone()
            if row:
                # старые подключения хранят токен в регистрации, а не в cloud_server_bot
                if not bot and row['telegram_bot_token']:
                    result['telegramBotConfigured'] = True
                    bot_token = row['telegram_bot_token']
                result.update(monitoring=True, username=row['username'], fullName=row['full_name'],
                              gradeClass=row['grade_class'], checkIntervalMinutes=row['check_interval_minutes'],
                              checkIntervalMaxMinutes=row['check_interval_max_minutes'],
                              telegramEnabled=row['telegram_enabled'], telegramUserId=row['telegram_user_id'] or '',
                              sessionInvalid=row['session_invalid'], lastCheckAt=str(row['last_check_at']) if row['last_check_at'] else None)
        finally:
            cursor.close()
            conn.close()
    if role == 'classmate':
        # даже состояние бота в этом режиме не относится к пользователю
        result = {key: value for key, value in result.items() if not key.startswith('telegram')}
    elif bot_token and not (result['telegramBotUsername'] or '').strip():
        result['telegramBotUsername'] = _telegram_bot_username(bot_token, int(time.monotonic() // 300))
    return jsonify(result)


@bp.route('/cloud/session', methods=['POST'])
@rate_limit('devices')
def existing_session():
    """передать владельцу действующую сессию, не выполняя новый вход"""
    data = _data()
    registration_id = data.get('registrationId')
    username = _text(data, 'username', 256)
    expected_prs_id = data.get('prsId')
    if not isinstance(registration_id, str) or not registration_id or not username:
        return jsonify(error='Укажите аккаунт и регистрацию'), 400
    if expected_prs_id is not None and (type(expected_prs_id) is not int or expected_prs_id <= 0):
        return jsonify(error='Некорректный идентификатор аккаунта'), 400
    for key in ('registrationSecret', 'registration_secret'):
        if data.get(key) is not None and not isinstance(data[key], str):
            return jsonify(error='Некорректный секрет регистрации'), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    def result(**payload):
        response = jsonify(payload)
        response.headers['Cache-Control'] = 'no-store, private'
        response.headers['Pragma'] = 'no-cache'
        return response

    conn = get_db_connection()
    if not conn:
        return jsonify(error='База данных недоступна'), 503
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute('SELECT username, session_invalid FROM cf3_registrations WHERE id = %s', (registration_id,))
        registration = cursor.fetchone()
    finally:
        cursor.close()
        conn.close()
    if not registration or registration['username'] != username:
        return jsonify(error='Подключение относится к другому аккаунту'), 409
    if registration['session_invalid']:
        return result(available=False)
    cookies = get_session(registration_id) or load_user_session(registration_id)
    if not cookies:
        return result(available=False)
    cookie = cookies.get('JSESSIONID')
    if not isinstance(cookie, str) or not re.fullmatch(r'[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]{1,4096}', cookie):
        return result(available=False)
    try:
        state_response = requests.get(
            f'{BASE_URL}/state', headers={'User-Agent': USER_AGENT, 'Accept': 'application/json'},
            cookies={'JSESSIONID': cookie}, timeout=10, allow_redirects=False,
        )
        if state_response.status_code in (401, 403):
            return result(available=False)
        if state_response.status_code != 200:
            return jsonify(error='Не удалось проверить сессию eSchool'), 503
        state = state_response.json()
        user = state.get('user') if isinstance(state, dict) else None
        prs_id = user.get('prsId') if isinstance(user, dict) else None
        if type(prs_id) is not int or prs_id <= 0 or type(state.get('userId')) is not int or state['userId'] <= 0:
            return result(available=False)
        if expected_prs_id is not None and expected_prs_id != prs_id:
            return jsonify(error='Сессия относится к другому аккаунту'), 409
        # если eSchool обновил cookie при проверке, отдаём и сохраняем новый
        refreshed = state_response.cookies.get('JSESSIONID')
        if refreshed and refreshed != cookie:
            if not re.fullmatch(r'[\x21\x23-\x2B\x2D-\x3A\x3C-\x5B\x5D-\x7E]{1,4096}', refreshed):
                return result(available=False)
            cookie = refreshed
            update_session(registration_id, {'JSESSIONID': cookie})
        return result(available=True, username=username, prsId=prs_id, sessionCookie=cookie)
    except (requests.RequestException, ValueError, TypeError):
        return jsonify(error='Не удалось проверить сессию eSchool'), 503


@bp.route('/cloud/server-bot', methods=['POST'])
@rate_limit('devices')
def configure_bot():
    data = _data()
    token = _text(data, 'telegramBotToken', 128)
    if not re.fullmatch(r'[0-9]+:[A-Za-z0-9_-]+', token):
        return jsonify(error='Проверьте токен из BotFather'), 400
    owner = data.get('registrationId')
    if owner:
        error = _require_registration_owner(owner, data)
        if error:
            return error
    try:
        me = TeleBot(token).get_me()
    except Exception:
        return jsonify(error='Telegram не принял токен бота или временно недоступен'), 400
    encrypted = encrypt_password(token)
    if not encrypted:
        return jsonify(error='На сервере не настроено шифрование'), 503
    conn = get_db_connection()
    if not conn:
        return jsonify(error='База данных недоступна'), 503
    cursor = conn.cursor()
    try:
        cursor.execute('''INSERT INTO cloud_server_bot (id, token_encrypted, username, owner_registration_id)
            VALUES (1, %s, %s, %s) ON CONFLICT (id) DO UPDATE SET token_encrypted = EXCLUDED.token_encrypted,
            username = EXCLUDED.username, owner_registration_id = EXCLUDED.owner_registration_id''', (encrypted, me.username, owner))
        conn.commit()
    finally:
        cursor.close()
        conn.close()
    restart_server_bot()
    return jsonify(success=True, telegramBotConfigured=True, telegramBotUsername=me.username)


@bp.route('/cloud/telegram', methods=['POST'])
@bp.route('/cloud/telegram/test', methods=['POST'])
@rate_limit('devices')
def telegram_settings():
    data = _data()
    if any(key in data for key in ('telegramBotToken', 'telegramGroupChatId', 'telegramGroupEnabled')):
        return jsonify(error='Личные уведомления настраиваются только по Telegram ID'), 400
    registration_id = data.get('registrationId')
    error = _require_registration_owner(registration_id, data)
    if error:
        return error
    enabled = data.get('telegramEnabled', True)
    if type(enabled) is not bool:
        return jsonify(error='Некорректное состояние Telegram'), 400
    user_id = _text(data, 'telegramUserId', 16)
    if enabled and not _telegram_id(user_id):
        return jsonify(error='Введите личный Telegram ID, положительное число'), 400
    bot = server_bot()
    shared_bot = bool(bot)
    if not bot:
        conn = get_db_connection()
        if not conn:
            return jsonify(error='База данных недоступна'), 503
        try:
            row = conn.execute('SELECT telegram_bot_token FROM cf3_registrations WHERE id = %s',
                               (registration_id,)).fetchone()
            if row and row[0]:
                bot = {'token': row[0]}
        finally:
            conn.close()
    if enabled and not bot:
        return jsonify(error='Администратор ещё не подключил бота сервера'), 409
    if request.path.endswith('/test'):
        if not bot or not _telegram_id(user_id):
            return jsonify(error='Сначала настройте личные уведомления'), 400
        ok = send_telegram_message(bot['token'], user_id, 'reSchool подключён', 'Здесь будут новые ДЗ, оценки и сообщения.')
        return (jsonify(success=True) if ok else
                (jsonify(error='Откройте бота и нажмите «Старт», затем проверьте Telegram ID'), 400))
    conn = get_db_connection()
    if not conn:
        return jsonify(error='База данных недоступна'), 503
    cursor = conn.cursor()
    try:
        cursor.execute('UPDATE cf3_registrations SET telegram_enabled = %s, telegram_user_id = %s WHERE id = %s',
                       (enabled, user_id if enabled else None, registration_id))
        if getattr(g, 'cloud_role', 'admin') == 'admin':
            cursor.execute('UPDATE cloud_server_bot SET owner_registration_id = %s WHERE id = 1', (registration_id,))
        conn.commit()
    finally:
        cursor.close()
        conn.close()
    if getattr(g, 'cloud_role', 'admin') == 'admin' and shared_bot:
        restart_server_bot()
    elif not shared_bot:
        primary = account_primary(registration_id)
        stop_telegram_bot(primary)
        if enabled:
            start_telegram_bot(primary, bot['token'], user_id, None)
    return jsonify(success=True)


@bp.route('/cloud/leave', methods=['POST'])
@rate_limit('devices')
def leave():
    data = _data()
    member_id = getattr(g, 'classmate_id', None)
    registration_id = getattr(g, 'cloud_registration_id', None) if member_id else data.get('registrationId')
    if registration_id:
        error = _require_registration_owner(registration_id, data)
        if error:
            return error
    conn = get_db_connection()
    if not conn:
        return jsonify(error='Сервер недоступен, подключение сохранено для повторной попытки'), 503
    cursor = conn.cursor()
    verification_token = None
    try:
        if member_id:
            cursor.execute('DELETE FROM classmate_registrations WHERE id = %s', (member_id,))
        if registration_id:
            cursor.execute('DELETE FROM cf3_registrations WHERE id = %s RETURNING verification_token', (registration_id,))
            row = cursor.fetchone()
            verification_token = row[0] if row else None
            if verification_token:
                cursor.execute('DELETE FROM verified_users WHERE token = %s', (verification_token,))
        conn.commit()
    finally:
        cursor.close()
        conn.close()
    if member_id:
        invalidate_classmate(member_id)
    if registration_id:
        invalidate_registration(registration_id)
        invalidate_verified_user(verification_token)
        stop_telegram_bot(registration_id)
        restart_all_telegram_bots()
        restart_server_bot()
    return jsonify(success=True)
