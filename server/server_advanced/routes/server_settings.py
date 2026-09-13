"""только администратор получает доступ к ограниченной службе настроек хоста"""
import http.client
import json
import os
import socket

from flask import Blueprint, g, jsonify, request

bp = Blueprint('server_settings', __name__)


class UnixConnection(http.client.HTTPConnection):
    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(os.getenv('RESCHOOL_SETTINGS_SOCKET', '/run/reschool-settings/settings.sock'))


@bp.before_request
def require_admin():
    if getattr(g, 'cloud_role', None) != 'admin' or getattr(g, 'is_classmate', False):
        return jsonify(error='Настройки сервера доступны только администратору'), 403
    if request.content_length and request.content_length > 65536:
        return jsonify(error='Слишком большой запрос'), 413


@bp.after_request
def no_store(response):
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Pragma'] = 'no-cache'
    return response


@bp.route('/server-settings', methods=['GET', 'POST'])
@bp.route('/server-settings/operation', methods=['GET'])
def settings():
    connection = UnixConnection('localhost', timeout=15)
    try:
        body = None
        if request.method == 'POST':
            data = request.get_json(silent=True)
            if not isinstance(data, dict):
                return jsonify(error='Некорректные настройки'), 400
            # данные регистрации старых клиентов намеренно не принимаем
            body = json.dumps({key: data.get(key) for key in ('revision', 'changes', 'operationId')})
        path = '/operation' if request.path.endswith('/operation') else '/settings'
        connection.request(request.method, path, body, {'Content-Type': 'application/json'})
        response = connection.getresponse()
        return jsonify(json.loads(response.read(1048576))), response.status
    except (OSError, http.client.HTTPException, ValueError):
        return jsonify(error='Сервис настройки не подключён или перезапускается. Повторите через несколько секунд.'), 503
    finally:
        connection.close()


@bp.route('/server-settings/health', methods=['GET'])
def health():
    from ..database import get_db_connection
    conn = get_db_connection()
    if not conn:
        return jsonify(ok=False), 503
    try:
        conn.execute('SELECT 1').fetchone()
        return jsonify(ok=True)
    except Exception:
        return jsonify(ok=False), 503
    finally:
        conn.close()


@bp.route('/server-updates', methods=['GET', 'POST'])
@bp.route('/server-updates/check', methods=['GET'])
def updates():
    connection = UnixConnection('localhost', timeout=15)
    try:
        body = None
        if request.method == 'POST':
            data = request.get_json(silent=True)
            if not isinstance(data, dict):
                return jsonify(error='Некорректный запрос обновления'), 400
            body = json.dumps({key: data.get(key) for key in ('version', 'operationId')})
        path = '/updates/check' if request.path.endswith('/check') else '/updates'
        connection.request(request.method, path, body, {'Content-Type': 'application/json'})
        response = connection.getresponse()
        if response.status == 404:
            return jsonify(error='Обновите сервис управления сервером по SSH, чтобы включить обновления из приложения.'), 503
        return jsonify(json.loads(response.read(1048576))), response.status
    except (OSError, http.client.HTTPException, ValueError):
        return jsonify(error='Сервис обновлений не подключён или перезапускается. Для старой установки подключите reschool-settings по SSH.'), 503
    finally:
        connection.close()
