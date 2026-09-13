import json
import time
import requests

from .config import (BASE_URL, USER_AGENT, ESCHOOL_USERNAME, ESCHOOL_PASSWORD,
                     ESCHOOL_VERSION_URL, ESCHOOL_VERSION_FALLBACK)
from .database import save_session
from .logging_utils import log, log_request, log_response
from .utils import sha256_hash, generate_random_string, get_random_device_model

_version_cache: str | None = None
_version_cache_time: float = 0
_VERSION_TTL = 24 * 3600  # сутки


def _parse_version(text: str) -> str:
    """версия может прийти строкой или внутри json"""
    text = text.strip()
    if text.startswith('{'):
        try:
            data = json.loads(text)
            text = (data.get('version') or '').strip()
        except Exception:
            return ''
    import re
    return text if re.match(r'^\d+\.\d+', text) else ''


def get_eschool_version() -> str:
    """версию клиента из релиза github кешируем на сутки"""
    global _version_cache, _version_cache_time
    now = time.time()
    if _version_cache and (now - _version_cache_time) < _VERSION_TTL:
        return _version_cache

    try:
        response = requests.get(ESCHOOL_VERSION_URL, timeout=5)
        if response.status_code == 200:
            version = _parse_version(response.text)
            if version:
                _version_cache = version
                _version_cache_time = now
                log(f"Fetched eSchool version: {version}")
                return version
    except Exception as e:
        log(f"Error fetching eSchool version: {e}")

    # в кэше мог остаться json от прошлого неудачного запроса
    valid_cache = _version_cache if _version_cache and _parse_version(_version_cache) else None
    return valid_cache or ESCHOOL_VERSION_FALLBACK


# состояние сервера
class ServerState:
    """общее состояние хранит школьную сессию сервера"""
    cookies = None
    prs_id = None


server_state = ServerState()


def login(username, password):
    """входим в eschool и возвращаем куки сессии"""
    if not username or not password:
        return None

    password_hash = sha256_hash(password)
    device_id = generate_random_string(16).lower()
    push_token = generate_random_string(152)
    device_model = get_random_device_model()

    device_payload = {
        "cliType": "mobile",
        "cliVer": get_eschool_version(),
        "pushToken": push_token,
        "deviceId": device_id,
        "deviceName": "-",
        "deviceModel": device_model,
        "cliOs": "android",
        "cliOsVer": "9"
    }

    body = {
        "username": username,
        "password": password_hash,
        "device": json.dumps(device_payload)
    }

    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Accept-Language": "ru-RU,en,*",
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/",
        "Content-Type": "application/x-www-form-urlencoded"
    }

    try:
        url = f"{BASE_URL}/login"
        log_request("POST", url, headers, body)
        response = requests.post(url, data=body, headers=headers)
        log_response(response)

        if response.status_code == 200:
            if 'JSESSIONID' in response.cookies or len(response.text) > 5:
                save_session(response.cookies)
                return response.cookies
        return None
    except Exception as e:
        log(f"Login error: {e}")
        return None


def get_state(cookies):
    """получаем состояние аккаунта eschool"""
    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/"
    }
    try:
        url = f"{BASE_URL}/state"
        log_request("GET", url, headers)
        response = requests.get(url, headers=headers, cookies=cookies)
        log_response(response)

        if response.status_code == 200:
            return response.json()
        return None
    except Exception:
        return None


def get_messages(cookies):
    """получаем список школьных бесед"""
    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/"
    }
    try:
        url = f"{BASE_URL}/chat/threads?newOnly=false&row=0&rowsCount=50"
        log_request("GET", url, headers)
        response = requests.get(url, headers=headers, cookies=cookies)
        log_response(response)

        if response.status_code == 401:
            log("Received 401, attempting re-login...")
            new_cookies = login(ESCHOOL_USERNAME, ESCHOOL_PASSWORD)
            if new_cookies:
                server_state.cookies = new_cookies
                log("Re-login successful, retrying request...")
                response = requests.get(url, headers=headers, cookies=new_cookies)
                log_response(response)
            else:
                log("Re-login failed.")
                return []

        if response.status_code == 200:
            threads = response.json()
            messages = []
            for thread in threads:
                messages.append({
                    "threadId": thread.get('threadId'),
                    "preview": thread.get('msgPreview', ''),
                    "sender": thread.get('senderFio', ''),
                    "imgObjId": thread.get('imgObjId'),
                    "date": thread.get('sendDate', 0)
                })
            return messages
        return []
    except Exception as e:
        log(f"Error fetching messages: {e}")
        return []


def get_thread_messages(cookies, thread_id):
    """получаем сообщения выбранной беседы"""
    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/",
        "Content-Type": "application/json"
    }
    try:
        url = f"{BASE_URL}/chat/messages?getNew=false&isSearch=false&rowStart=0&rowsCount=50&threadId={thread_id}"
        body = json.dumps({"msgNums": None, "searchText": None})

        log_request("PUT", url, headers, body)
        response = requests.put(url, headers=headers, cookies=cookies, data=body)
        log_response(response)

        if response.status_code == 401:
            log("Received 401, attempting re-login...")
            new_cookies = login(ESCHOOL_USERNAME, ESCHOOL_PASSWORD)
            if new_cookies:
                server_state.cookies = new_cookies
                log("Re-login successful, retrying request...")
                response = requests.put(url, headers=headers, cookies=new_cookies, data=body)
                log_response(response)
            else:
                log("Re-login failed.")
                return []

        if response.status_code == 200:
            return response.json()
        return []
    except Exception as e:
        log(f"Error fetching thread messages: {e}")
        return []
