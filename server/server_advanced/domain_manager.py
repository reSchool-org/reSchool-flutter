import ipaddress
import json
import re
import threading
import time
import uuid

import requests

from .config import get_public_base_url, get_server_domain, set_runtime_server_domain


_DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)(?!-)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$"
)
_JOBS = {}
_JOBS_LOCK = threading.Lock()


def normalize_domain(value):
    domain = (value or "").strip().lower()
    domain = domain.removeprefix("http://").removeprefix("https://")
    domain = domain.split("/", 1)[0].split(":", 1)[0].rstrip(".")
    try:
        domain = domain.encode("idna").decode("ascii")
    except Exception:
        return ""
    return domain


def validate_domain(value):
    domain = normalize_domain(value)
    if not domain:
        return None, "Введите домен"
    try:
        ipaddress.ip_address(domain)
        return None, "Нужен домен с A-записью, а не IP-адрес"
    except ValueError:
        pass
    if domain in {"localhost", "local"} or not _DOMAIN_RE.match(domain):
        return None, "Неверный домен"
    return domain, None


def _domain_caddyfile(domain):
    # самоподписанный вход на 4443 оставляем всегда, иначе уже привязанные телефоны отвалятся
    return (
        "{\n  admin 0.0.0.0:2019\n}\n\n"
        ":4443 {\n"
        "  encode zstd gzip\n"
        "  tls /tls/cert.pem /tls/key.pem\n"
        "  reverse_proxy server_advanced:20001\n"
        "}\n\n"
        f"{domain} {{\n"
        "  encode zstd gzip\n"
        "  reverse_proxy server_advanced:20001\n"
        "}\n"
    )


def apply_domain_to_caddy(domain, admin_url="http://caddy:2019"):
    admin_url = (admin_url or "http://caddy:2019").rstrip("/")
    caddyfile = _domain_caddyfile(domain)

    try:
        adapt = requests.post(
            f"{admin_url}/adapt?adapter=caddyfile",
            data=caddyfile.encode("utf-8"),
            headers={"Content-Type": "text/caddyfile"},
            timeout=10,
        )
    except requests.RequestException as exc:
        return False, f"Caddy недоступен: {exc}"
    if adapt.status_code >= 400:
        return False, f"Caddy не принял конфигурацию: {adapt.text}"

    try:
        adapted_config = adapt.json().get("result")
    except (json.JSONDecodeError, AttributeError):
        adapted_config = None
    if not adapted_config:
        return False, f"Caddy вернул пустую конфигурацию: {adapt.text}"

    try:
        load = requests.post(
            f"{admin_url}/load",
            data=json.dumps(adapted_config).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            timeout=10,
        )
    except requests.RequestException as exc:
        return False, f"Caddy недоступен: {exc}"
    if load.status_code >= 400:
        return False, f"Caddy не перезагрузился: {load.text}"

    return True, None


def _update_job(job_id, **fields):
    with _JOBS_LOCK:
        job = _JOBS.get(job_id)
        if not job:
            return
        job.update(fields)
        job["updatedAt"] = time.time()


def get_domain_job(job_id):
    with _JOBS_LOCK:
        job = _JOBS.get(job_id)
        if not job:
            return None
        return dict(job)


def _wait_for_https(domain, job_id, timeout_seconds=90):
    url = f"https://{domain}/config"
    deadline = time.time() + timeout_seconds
    last_error = ""

    while time.time() < deadline:
        try:
            response = requests.get(url, timeout=8)
            if response.status_code == 200:
                return True, None
            last_error = f"HTTPS ответил кодом {response.status_code}"
        except requests.RequestException as exc:
            last_error = str(exc)

        remaining = max(0, int(deadline - time.time()))
        _update_job(
            job_id,
            step="certificate",
            message=f"Жду выпуск сертификата Let's Encrypt... осталось до {remaining} сек.",
        )
        time.sleep(3)

    return False, last_error or "HTTPS не стал доступен"


def _run_domain_job(job_id, raw_domain, admin_url):
    _update_job(
        job_id,
        status="running",
        step="validate",
        message="Проверяю домен...",
    )
    domain, error = validate_domain(raw_domain)
    if error:
        _update_job(job_id, status="failed", step="validate", error=error, message=error)
        return

    _update_job(
        job_id,
        domain=domain,
        publicBaseUrl=f"https://{domain}",
        step="caddy",
        message="Передаю домен в Caddy...",
    )
    ok, error = apply_domain_to_caddy(domain, admin_url=admin_url)
    if not ok:
        _update_job(job_id, status="failed", step="caddy", error=error, message=error)
        return

    _update_job(
        job_id,
        step="certificate",
        message="Caddy принял конфигурацию. Запрашиваю HTTPS, чтобы выпустить сертификат...",
    )
    ok, error = _wait_for_https(domain, job_id)
    if not ok:
        _update_job(
            job_id,
            status="failed",
            step="certificate",
            error=(
                "Caddy настроен, но HTTPS пока не заработал. "
                "Проверьте A-запись домена и открытые порты 80/443. "
                f"Последняя ошибка: {error}"
            ),
            message="Не удалось дождаться HTTPS-сертификата.",
        )
        return

    set_runtime_server_domain(domain)
    _update_job(
        job_id,
        status="success",
        step="done",
        message="HTTPS-сертификат выпущен, домен готов.",
        domain=domain,
        publicBaseUrl=f"https://{domain}",
    )


def start_domain_job(domain, admin_url="http://caddy:2019"):
    job_id = uuid.uuid4().hex
    with _JOBS_LOCK:
        _JOBS[job_id] = {
            "jobId": job_id,
            "status": "queued",
            "step": "queued",
            "message": "Задача поставлена в очередь...",
            "error": None,
            "domain": normalize_domain(domain),
            "publicBaseUrl": "",
            "createdAt": time.time(),
            "updatedAt": time.time(),
        }

    thread = threading.Thread(
        target=_run_domain_job,
        args=(job_id, domain, admin_url),
        daemon=True,
    )
    thread.start()
    return get_domain_job(job_id)


def configure_server_domain(domain, admin_url="http://caddy:2019"):
    domain, error = validate_domain(domain)
    if error:
        return None, error

    ok, error = apply_domain_to_caddy(domain, admin_url=admin_url)
    if not ok:
        return None, error

    set_runtime_server_domain(domain)
    return {
        "domain": domain,
        "publicBaseUrl": f"https://{domain}",
    }, None


def current_domain_status():
    return {
        "domain": get_server_domain(),
        "publicBaseUrl": get_public_base_url(),
    }
