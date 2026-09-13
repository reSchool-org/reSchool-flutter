import json
import time

from flask import Flask, jsonify, request, g

from .config import ESCHOOL_USERNAME, ESCHOOL_PASSWORD, API_TOKEN, REQUEST_LOG_FULL_DEBUG
from .database import init_db, load_session, get_db_connection, get_classmate_by_token
from .logging_utils import log, redact_data, redact_headers, redact_url
from .eschool_api import login, get_state, server_state
from .encryption import init_encryption
from .routes import register_routes
from .routes.notifications import start_notification_monitor
from .ai_worker import start as start_ai_worker
from .keep_alive import start_keep_alive
from .config import get_server_domain, RUNTIME_DIR, ENCRYPTION_KEY
from .server_credentials import credentials_changed, accept_credentials
from .domain_manager import apply_domain_to_caddy
from .tls_manager import connection_hint, ensure_certificate
from .cloud_access import member_path_allowed
from .ip_blacklist import is_ip_blocked
from .rate_limiter import client_ip, is_local_ip


app = Flask(__name__)

@app.before_request
def block_blacklisted_ip():
    ip = client_ip()
    if is_local_ip(request.remote_addr) and not request.headers.get('X-Forwarded-For'):
        return None
    if is_ip_blocked(ip):
        log(f"[Security] Blocked blacklisted IP: {ip}")
        return jsonify({"error": "IP address is blocked"}), 403
    return None


@app.before_request
def check_api_token():
    """проверяем токен запроса, без API_TOKEN в .env доступ закрыт"""
    # публичное чтение и редактор звонков используют отдельные правила доступа
    if request.blueprint == 'bell_time':
        return None
    if not API_TOKEN:
        log("[Auth] WARNING: API_TOKEN not set in .env - all requests are blocked for safety")
        return jsonify({"error": "Server misconfigured: API_TOKEN not set"}), 503

    # публичные эндпоинты, токен не нужен
    # запрос и проверка подтверждения открыты потому,
    # что одноклассник дёргает их до того, как получит хоть какой то токен
    if request.path in ('/config', '/cloud/join', '/classmate-join', '/request-verification', '/check-verification', '/open') \
            or (request.path in ('/proxy', '/proxy/version') and request.method == 'OPTIONS'):
        g.is_classmate = False
        return None

    token = request.headers.get('X-API-Token')
    if not token:
        token = (request.get_json(silent=True, force=True) or {}).get('apiToken')

    # админский токен, полный доступ
    if token == API_TOKEN:
        g.is_classmate = False
        g.cloud_role = 'admin'
        return None

    # токен одноклассника, ответ базы кешируем в redis: он нужен на каждый запрос
    if token:
        classmate = get_classmate_by_token(token)
        if classmate:
            registration_id = classmate.get('monitoring_registration_id')
            if not member_path_allowed(request.path, bool(registration_id)):
                return jsonify({"error": "Forbidden"}), 403
            g.is_classmate = True
            g.cloud_role = 'user' if registration_id else 'classmate'
            g.cloud_registration_id = registration_id
            g.classmate_id = classmate['id']
            g.classmate_grade_class = classmate['grade_class']
            g.classmate_display_name = classmate['display_name']
            return None

    return jsonify({"error": "Unauthorized"}), 401


@app.route('/auth-check', methods=['GET'])
def auth_check():
    """лёгкий защищённый запрос позволяет клиенту проверить сервер и токен"""
    return jsonify({"ok": True, "role": getattr(g, "cloud_role", "admin")})


@app.route('/browser-connection', methods=['GET'])
def browser_connection():
    """код личности сервера доступен авторизованным администраторам"""
    import os
    from pathlib import Path
    runtime = os.getenv('RESCHOOL_RUNTIME_DIR', str(Path(__file__).parent / 'runtime'))
    try:
        code = Path(runtime, 'browser', 'connection-code.txt').read_text().strip()
    except FileNotFoundError:
        return jsonify({'error': 'Включите браузерное подключение на сервере'}), 503
    return jsonify({'connectionCode': code})


@app.before_request
def log_incoming_request():
    """журналируем входящие запросы"""
    if request.blueprint in ('bell_time', 'server_settings'):
        return None
    log("\n========== INCOMING REQUEST ==========")
    log(f"URL: {redact_url(request.url)}")
    log(f"Method: {request.method}")
    log("Headers:")
    for key, value in redact_headers(request.headers).items():
        log(f"  {key}: {value}")

    if request.is_json:
        body = request.get_json(silent=True, force=True)
        log(f"Body: {json.dumps(redact_data(body), ensure_ascii=False)}")
    elif request.form:
        log(f"Body (Form): {redact_data(request.form.to_dict())}")
    elif request.data:
        raw_body = request.data.decode('utf-8', errors='ignore')
        log(f"Body (Raw): {raw_body if REQUEST_LOG_FULL_DEBUG else '[REDACTED]'}")
    else:
        log("Body: [empty]")
    log("======================================\n")


@app.after_request
def log_outgoing_response(response):
    """журналируем исходящие ответы"""
    if request.blueprint in ('bell_time', 'server_settings'):
        return response
    log("\n========== OUTGOING RESPONSE ==========")
    log(f"Status Code: {response.status_code}")
    if response.is_json:
        if REQUEST_LOG_FULL_DEBUG and request.path != '/cloud/session':
            log(f"Response Body: {response.get_data(as_text=True)}")
        else:
            try:
                log(f"Response Body: {json.dumps(redact_data(response.get_json(silent=True)), ensure_ascii=False)}")
            except Exception:
                log("Response Body: [REDACTED]")
    else:
        log("Response Body: [Not JSON]")
    log("=======================================\n")
    return response


def initialize_server():
    """поднимаем сервер вместе с авторизацией и базой"""
    log("Initializing server...")

    # поднимаем базу
    init_db()

    if not init_encryption():
        raise RuntimeError("ENCRYPTION_KEY/CF3_ENCRYPTION_KEY is required for stored credentials")

    changed_credentials = credentials_changed(
        RUNTIME_DIR, ESCHOOL_USERNAME, ESCHOOL_PASSWORD, ENCRYPTION_KEY)
    cookies = None if changed_credentials else load_session()

    state = None
    if cookies:
        state = get_state(cookies)
        if not state:
            log("Session expired.")
            cookies = None

    if not cookies:
        if ESCHOOL_USERNAME and ESCHOOL_PASSWORD:
            cookies = login(ESCHOOL_USERNAME, ESCHOOL_PASSWORD)
            if cookies:
                state = get_state(cookies)

    if state and cookies:
        accept_credentials(RUNTIME_DIR, ESCHOOL_USERNAME, ESCHOOL_PASSWORD, ENCRYPTION_KEY)
        server_state.cookies = cookies
        server_state.prs_id = state.get('user', {}).get('prsId')
        name = state.get('profile', {}).get('firstName')
        log(f"Server authenticated as {name} (PRS ID: {server_state.prs_id})")
    else:
        if changed_credentials:
            raise RuntimeError("Не удалось войти с новыми настройками eSchool")
        log("Failed to authenticate server. Please check .env")

    domain = get_server_domain()
    if domain:
        ok, error = False, None
        for _ in range(6):
            ok, error = apply_domain_to_caddy(domain)
            if ok:
                break
            time.sleep(2)
        if ok:
            log(f"[Domain] Applied HTTPS domain: {domain}")
        else:
            log(f"[Domain] Could not apply saved domain {domain}: {error}")


# подключаем все маршруты
register_routes(app)


def run_server():
    """запускаем сервер flask"""
    # сертификат нужен caddy, но генерируем и тут: без докера certgen никто не запускает
    try:
        ensure_certificate()
        log(connection_hint(API_TOKEN or ""))
    except Exception as e:
        log(f"[TLS] Не удалось подготовить самоподписанный сертификат: {e}")

    initialize_server()
    init_encryption()
    start_notification_monitor()
    start_ai_worker()
    start_keep_alive()
    app.run(host='0.0.0.0', port=20001)


if __name__ == '__main__':
    run_server()
