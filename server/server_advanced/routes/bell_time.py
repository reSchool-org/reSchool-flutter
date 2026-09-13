"""публичное время звонков и редактор с авторизацией по cookie работают независимо от eschool"""
import copy
import fcntl
import hmac
import json
import os
import re
import secrets
import tempfile
import time
from pathlib import Path

from flask import Blueprint, jsonify, make_response, render_template, request
from itsdangerous import BadSignature, SignatureExpired, URLSafeTimedSerializer

from ..config import API_TOKEN
from ..rate_limiter import rate_limit

bp = Blueprint('bell_time', __name__, template_folder='templates')
COOKIE = '__Secure-reschool-bell-session'
SESSION_AGE = 30 * 24 * 60 * 60
CAMPUSES = ('fml30_shevchenko', 'fml30_7liniya')
NAMES = ('Шевченко, 23', '7-я линия, 52')


def _lessons(times):
    return {str(i): dict(zip(('start', 'end'), pair.split('-')))
            for i, pair in enumerate(times.split(), 1)}


DEFAULTS = {
    'version': 1,
    'revision': 1,
    'updatedAt': None,
    'presets': {
        CAMPUSES[0]: {'offsetSeconds': 126, 'lessons': _lessons(
            '08:50-09:35 09:45-10:30 10:45-11:30 11:50-12:35 '
            '12:55-13:40 13:55-14:40 14:50-15:35')},
        CAMPUSES[1]: {'offsetSeconds': 0, 'lessons': _lessons(
            '08:30-09:15 09:25-10:10 10:25-11:10 11:30-12:15 '
            '12:35-13:20 13:35-14:20 14:30-15:15 15:25-16:10')},
    },
}


def _path():
    return Path(os.getenv('RESCHOOL_RUNTIME_DIR',
                         str(Path(__file__).resolve().parents[1] / 'runtime'))) / 'bell-time.json'


def _read():
    try:
        return json.loads(_path().read_text(encoding='utf-8'))
    except FileNotFoundError:
        return copy.deepcopy(DEFAULTS)


def _seconds(value):
    if not isinstance(value, str) or not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?', value):
        raise ValueError('Время должно быть в формате ЧЧ:ММ или ЧЧ:ММ:СС.')
    parts = [int(p) for p in value.split(':')]
    return parts[0] * 3600 + parts[1] * 60 + (parts[2] if len(parts) == 3 else 0)


def validate_presets(presets):
    if not isinstance(presets, dict) or set(presets) != set(CAMPUSES):
        raise ValueError('Нужны тайминги обоих корпусов ФМЛ № 30.')
    result = {}
    for campus, preset in presets.items():
        if not isinstance(preset, dict):
            raise ValueError('Некорректный корпус.')
        offset = preset.get('offsetSeconds')
        if type(offset) is not int or abs(offset) > 3600:
            raise ValueError('Коррекция должна быть целым числом секунд от −3600 до 3600.')
        lessons = preset.get('lessons')
        if not isinstance(lessons, dict) or not 1 <= len(lessons) <= 16:
            raise ValueError('Нужно от 1 до 16 уроков.')
        if any(not isinstance(k, str) or not re.fullmatch(r'(?:[0-9]|1[0-5])', k) for k in lessons):
            raise ValueError('Номер урока должен быть от 0 до 15.')
        previous_end = -1
        clean = {}
        for number in sorted(lessons, key=int):
            lesson = lessons[number]
            if not isinstance(lesson, dict):
                raise ValueError('Некорректный урок.')
            start, end = _seconds(lesson.get('start')), _seconds(lesson.get('end'))
            if start < previous_end or end <= start or not (0 <= start + offset < end + offset < 86400):
                raise ValueError('Уроки должны идти по порядку, без пересечений и перехода через полночь.')
            previous_end = end
            clean[number] = {'start': lesson['start'], 'end': lesson['end']}
        result[campus] = {'offsetSeconds': offset, 'lessons': clean}
    return result


def _session():
    if not API_TOKEN:
        return None
    try:
        return URLSafeTimedSerializer(API_TOKEN, salt='bell-time').loads(
            request.cookies.get(COOKIE, ''), max_age=SESSION_AGE)
    except (BadSignature, SignatureExpired):
        return None


def _authorized():
    token = request.headers.get('X-API-Token', '')
    if API_TOKEN and token and hmac.compare_digest(token.encode(), API_TOKEN.encode()):
        return True
    session = _session()
    return bool(session and hmac.compare_digest(
        request.headers.get('X-CSRF-Token', ''), session['csrf']))


@bp.after_request
def headers(response):
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Vary'] = 'Accept, Cookie'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['Referrer-Policy'] = 'no-referrer'
    # публичный json доступен веб приложению с любого настроенного хоста, запросы с чужого сайта не передают данные входа
    if request.method in ('GET', 'HEAD', 'OPTIONS') and response.is_json:
        response.headers['Access-Control-Allow-Origin'] = '*'
    return response


@bp.route('/time', methods=['GET', 'PUT'])
def timings():
    if request.method == 'PUT':
        if not _authorized():
            return jsonify(error='Unauthorized'), 401
        if request.content_length is None or request.content_length > 32768:
            return jsonify(error='Слишком большой запрос.'), 413
        data = request.get_json(silent=True)
        try:
            if not isinstance(data, dict) or type(data.get('revision')) is not int:
                raise ValueError('Нужна версия редактируемого расписания.')
            presets = validate_presets(data.get('presets'))
        except ValueError as exc:
            return jsonify(error=str(exc)), 400
        path = _path()
        path.parent.mkdir(parents=True, exist_ok=True)
        # блокируем отдельный inode, чтобы os.replace не мешал атомарному чтению другими воркерами
        with path.with_suffix('.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            old = _read()
            if old['revision'] != data['revision']:
                return jsonify(error='Тайминги уже изменены. Обновите страницу перед сохранением.'), 409
            result = dict(version=1, revision=old['revision'] + 1,
                          updatedAt=int(time.time() * 1000), presets=presets)
            fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.bell-time-')
            try:
                with os.fdopen(fd, 'w', encoding='utf-8') as stream:
                    json.dump(result, stream, ensure_ascii=False)
                    stream.flush()
                    os.fsync(stream.fileno())
                os.replace(temporary, path)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
        return jsonify(result)

    data = _read()
    if request.accept_mimetypes['text/html'] > request.accept_mimetypes['application/json']:
        session = _session()
        nonce = secrets.token_urlsafe(18)
        response = make_response(render_template(
            'bell_time.html', data=data if session else None,
            csrf=session['csrf'] if session else None,
            campuses=CAMPUSES, names=NAMES, nonce=nonce))
        response.headers['Content-Security-Policy'] = (
            f"default-src 'none'; script-src 'nonce-{nonce}'; style-src 'nonce-{nonce}'; "
            "connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'")
        return response
    return jsonify(**data, serverTimeMs=int(time.time() * 1000), timezone='Europe/Moscow')


@bp.post('/time/login')
@rate_limit('token_check')
def login():
    # для входа нужны json и свой заголовок, форма с чужого сайта их не отправит
    if request.headers.get('X-Bell-Login') != '1' or not request.is_json:
        return jsonify(error='Forbidden'), 403
    data = request.get_json(silent=True)
    key = data.get('apiToken') if isinstance(data, dict) else None
    if not API_TOKEN or not isinstance(key, str) or not hmac.compare_digest(key.encode(), API_TOKEN.encode()):
        return jsonify(error='Неверный API-ключ.'), 401
    cookie = URLSafeTimedSerializer(API_TOKEN, salt='bell-time').dumps({'csrf': secrets.token_urlsafe(32)})
    response = jsonify(ok=True)
    response.set_cookie(COOKIE, cookie, max_age=SESSION_AGE, secure=True,
                        httponly=True, samesite='Strict', path='/time')
    return response


@bp.post('/time/logout')
def logout():
    if not _authorized():
        return jsonify(error='Unauthorized'), 401
    response = jsonify(ok=True)
    response.delete_cookie(COOKIE, path='/time', secure=True, httponly=True, samesite='Strict')
    return response
