import base64
import binascii
import requests
from flask import Blueprint, request, jsonify, make_response
from urllib.parse import urlparse

from ..config import BASE_URL, ALLOWED_CORS_ORIGINS
from ..logging_utils import log
from ..eschool_api import get_eschool_version

bp = Blueprint('proxy', __name__)

# заголовки браузера, которые в eSchool пробрасывать не надо
_HOP_BY_HOP = {
    'host', 'connection', 'keep-alive', 'proxy-authenticate',
    'proxy-authorization', 'te', 'trailers', 'transfer-encoding',
    'upgrade', 'content-length', 'x-api-token',
}

# заголовки ответа eSchool, которые не надо отдавать браузеру
_SKIP_RESPONSE_HEADERS = {
    'transfer-encoding', 'connection', 'keep-alive',
    'access-control-allow-origin', 'access-control-allow-methods',
    'access-control-allow-headers', 'access-control-allow-credentials',
}


def _cors_headers():
    origin = (request.headers.get('Origin') or '').rstrip('/')
    if not origin or origin not in ALLOWED_CORS_ORIGINS:
        return {}
    return {
        'Access-Control-Allow-Origin': origin,
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, X-Api-Token',
        'Access-Control-Max-Age': '86400',
        'Vary': 'Origin',
    }


def _effective_port(parsed):
    if parsed.port:
        return parsed.port
    return 443 if parsed.scheme == 'https' else 80


def _is_allowed_target_url(target_url):
    try:
        base = urlparse(BASE_URL)
        target = urlparse(target_url)
    except Exception:
        return False

    if target.scheme != base.scheme:
        return False
    if target.hostname != base.hostname:
        return False
    if _effective_port(target) != _effective_port(base):
        return False

    base_path = base.path.rstrip('/')
    target_path = target.path.rstrip('/')
    return target_path == base_path or target.path.startswith(f"{base_path}/")


@bp.after_request
def add_proxy_cors(response):
    # добавляем заголовки и к ошибкам авторизации до маршрута, иначе браузер скроет статус
    for key, value in _cors_headers().items():
        response.headers[key] = value
    return response


@bp.route('/proxy/version', methods=['GET'], provide_automatic_options=False)
def proxy_version():
    return jsonify({'version': get_eschool_version()})


@bp.route('/proxy/version', methods=['OPTIONS'])
@bp.route('/proxy', methods=['OPTIONS'])
def proxy_preflight():
    """отвечаем на предварительный запрос cors браузера"""
    headers = _cors_headers()
    if request.headers.get('Origin') and not headers:
        return make_response(jsonify({'error': 'CORS origin not allowed'}), 403)
    resp = make_response('', 204)
    for k, v in headers.items():
        resp.headers[k] = v
    return resp


@bp.route('/proxy', methods=['POST'])
def proxy_request():
    """проксируем школьный запрос веб клиента только к разрешённому адресу eschool"""
    data = request.get_json(force=True, silent=True) or {}
    method = str(data.get('method', 'GET')).upper()
    target_url = str(data.get('url', ''))
    fwd_headers = data.get('headers') or {}
    body = data.get('body')  # бывает пустым, бывает строкой
    body_bytes = body.encode('utf-8') if isinstance(body, str) else None
    if 'bodyBase64' in data:
        try:
            body_bytes = base64.b64decode(data['bodyBase64'], validate=True)
        except (ValueError, TypeError, binascii.Error):
            return jsonify({'error': 'Invalid base64 request body'}), 400

    # безопасность: пускаем только на заранее заданный адрес и путь eSchool
    if not _is_allowed_target_url(target_url):
        log(f"[Proxy] Rejected URL not matching BASE_URL: {target_url}")
        resp = make_response(jsonify({'error': 'Forbidden: URL not allowed'}), 403)
        for k, v in _cors_headers().items():
            resp.headers[k] = v
        return resp

    # выкидываем заголовки, живущие только на одном участке соединения
    clean_headers = {
        k: v for k, v in fwd_headers.items()
        if k.lower() not in _HOP_BY_HOP
    }

    log(f"[Proxy] {method} {target_url}")

    try:
        eschool_resp = requests.request(
            method,
            target_url,
            headers=clean_headers,
            data=body_bytes,
            timeout=30,
            allow_redirects=False,
        )
    except requests.RequestException as e:
        log(f"[Proxy] Request error: {e}")
        resp = make_response(jsonify({'error': f'Proxy request failed: {e}'}), 502)
        for k, v in _cors_headers().items():
            resp.headers[k] = v
        return resp

    # собираем заголовки ответа, часть выбрасываем
    response_headers = {
        k: v for k, v in eschool_resp.headers.items()
        if k.lower() not in _SKIP_RESPONSE_HEADERS
    }

    # текстовый json портит двоичные файлы, новым клиентам отдаём base64, старым сохраняем текстовый формат
    binary = data.get('responseEncoding') == 'base64'
    result = jsonify({
        'status': eschool_resp.status_code,
        'headers': response_headers,
        'body': (base64.b64encode(eschool_resp.content).decode('ascii')
                 if binary else eschool_resp.text),
        **({'bodyEncoding': 'base64'} if binary else {}),
    })

    resp = make_response(result, 200)
    for k, v in _cors_headers().items():
        resp.headers[k] = v
    return resp
