import json
import re
import sys
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from .config import REQUEST_LOG_FULL_DEBUG
from .runtime_logging import safe_text, write_log


_SENSITIVE_KEYS = {
    "auth",
    "code",
    "pass",
    "registrationid",
}


def _normalise_key(key):
    return re.sub(r"[^a-z0-9]", "", str(key).lower())


def _is_sensitive_key(key):
    normalised = _normalise_key(key)
    return normalised in _SENSITIVE_KEYS or any(
        part in normalised
        for part in (
            "password", "passwd", "passphrase", "pwd", "token", "secret", "cookie",
            "authorization", "authentication", "apikey", "privatekey", "encryptionkey",
            "accesskey", "signingkey",
            "credential", "session", "verificationcode",
        )
    )


def redact_value(value):
    if value is None:
        return None
    return "[REDACTED]"


def redact_data(value):
    if isinstance(value, dict):
        return {
            key: redact_value(val) if _is_sensitive_key(key) else redact_data(val)
            for key, val in value.items()
        }
    if isinstance(value, (list, tuple)):
        return [redact_data(item) for item in value]
    return value


def redact_headers(headers):
    return {
        key: redact_value(value) if _is_sensitive_key(key) else value
        for key, value in (headers or {}).items()
    }


def redact_url(url):
    if not url:
        return url
    try:
        parts = urlsplit(str(url))
        query = urlencode(
            [
                (key, redact_value(value) if _is_sensitive_key(key) else value)
                for key, value in parse_qsl(parts.query, keep_blank_values=True)
            ]
        )
        netloc = parts.netloc.rsplit("@", 1)[-1]
        # во фрагменте тоже бывают креды, к тому же на сервер он не уходит
        return urlunsplit((parts.scheme, netloc, parts.path, query, ""))
    except Exception:
        return "[REDACTED]"


def serialise_log_body(body):
    if isinstance(body, (str, bytes, bytearray)):
        try:
            body = json.loads(body)
        except (ValueError, UnicodeError):
            return "[REDACTED]"
    if isinstance(body, (dict, list, tuple)):
        return json.dumps(redact_data(body), ensure_ascii=False)
    return "[REDACTED]"


def log(message):
    """сразу сбрасываем сообщение в журнал"""
    message = safe_text(message)
    print(message, flush=True)
    current = sys.exc_info()
    write_log(message, current if current[0] else None)


def log_request(method, url, headers, body=None):
    """журналируем сведения об исходящем запросе api"""
    log("\n========== API REQUEST ==========")
    log(f"URL: {redact_url(url)}")
    log(f"Method: {method}")
    log("Headers:")
    for key, value in redact_headers(headers).items():
        log(f"  {key}: {value}")

    if body:
        log(f"Body: {serialise_log_body(body)}")
    else:
        log("Body: [empty]")
    log("==================================\n")


def log_response(response):
    """журналируем сведения об ответе api"""
    log("\n========== API RESPONSE ==========")
    log(f"URL: {redact_url(response.url)}")
    log(f"Status Code: {response.status_code}")
    log("Headers:")
    for key, value in redact_headers(response.headers).items():
        log(f"  {key}: {value}")

    if response.text:
        text = serialise_log_body(response.text) if REQUEST_LOG_FULL_DEBUG else "[REDACTED]"
        if len(text) > 2000:
            log(f"Response Body: {text[:2000]}... [Truncated]")
        else:
            log(f"Response Body: {text}")
    else:
        log("Response Body: [empty]")
    log("==================================\n")
