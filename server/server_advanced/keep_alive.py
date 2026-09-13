"""держим сессию как веб клиент через events и digest; повторный вход выполняет монитор, здесь ждём update_session"""
import json
import threading
import time
import requests

from .config import BASE_URL, USER_AGENT
from .database import get_db_connection, save_user_session, load_user_session, delete_user_session
from .logging_utils import log
from .eschool_api import server_state, login as server_login
from .config import ESCHOOL_USERNAME, ESCHOOL_PASSWORD


# состояние keep alive
_keep_alive_running = False
_account_threads = {}  # {account_id: {"events": поток, "news": поток, "stop": Event}}
_account_threads_lock = threading.Lock()

# сессии: {account_id: куки или пусто}
# пусто значит сессия протухла и ждём повторного входа из cf3
_sessions = {}
_sessions_lock = threading.Lock()

# таймеры подсмотрены у веб клиента app.eschool.center
EVENT_RECONNECT_DELAY = 5
NEWS_DIGEST_INTERVAL = 200

# браузер держит EventSource сколько угодно, так что этот таймаут просто сторож
# от зависших сокетов, обычные переподключения инициирует сервер или сеть
EVENT_READ_TIMEOUT = 600


def _is_running(stop_event=None):
    return _keep_alive_running and not (stop_event and stop_event.is_set())


def _browser_headers(accept, referer="https://app.eschool.center/Private/student/diary/1"):
    """заголовки повторяют запросы школьного веб клиента"""
    return {
        "Accept": accept,
        "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
        "User-Agent": USER_AGENT,
        "Origin": "https://app.eschool.center",
        "Referer": referer,
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-origin",
    }


def _wait_seconds(seconds, stop_event=None):
    for _ in range(seconds):
        if not _is_running(stop_event):
            break
        time.sleep(1)


def _is_authorized(cookies, account_name):
    """перед восстановлением событий проверяем сессию; None означает временный сбой, False означает истечение"""
    try:
        response = requests.get(
            f"{BASE_URL}/isAuthorized",
            headers=_browser_headers("application/json, text/plain, */*"),
            cookies=cookies,
            timeout=30,
        )
        if response.status_code == 200:
            return True
        if response.status_code in (401, 403):
            log(f"[KeepAlive] isAuthorized {response.status_code} for {account_name}")
            return False
        log(f"[KeepAlive] isAuthorized unexpected {response.status_code} for {account_name}")
        return None
    except requests.RequestException as e:
        log(f"[KeepAlive] isAuthorized error for {account_name}: {e}")
        return None


def _fetch_news_digest(cookies, account_name):
    """повторяем фоновый запрос новостей веб клиента"""
    try:
        response = requests.get(
            f"{BASE_URL}/news/digest",
            params={"page": 1, "pageSize": 1},
            headers=_browser_headers(
                "application/json, text/plain, */*",
                "https://app.eschool.center/Private/student/diary/1",
            ),
            cookies=cookies,
            timeout=30,
        )
        if response.status_code == 200:
            log(f"[KeepAlive] news/digest OK for {account_name}")
            return False
        if response.status_code in (401, 403):
            log(f"[KeepAlive] news/digest {response.status_code} for {account_name}")
            return True
        log(f"[KeepAlive] news/digest unexpected {response.status_code} for {account_name}")
    except requests.RequestException as e:
        log(f"[KeepAlive] news/digest error for {account_name}: {e}")
    return False


def _hold_events_stream(cookies, account_name, stop_event=None):
    """держим соединение событий до истечения сессии"""
    start_time = time.time()
    response = None
    headers = _browser_headers("text/event-stream")
    headers["Cache-Control"] = "no-cache"

    try:
        response = requests.get(
            f"{BASE_URL}/events",
            headers=headers,
            cookies=cookies,
            stream=True,
            timeout=(10, EVENT_READ_TIMEOUT),
        )

        if response.status_code == 401:
            log(f"[KeepAlive] 401 for {account_name} - session expired, waiting for re-login")
            return True

        if response.status_code != 200:
            log(f"[KeepAlive] Unexpected {response.status_code} for {account_name}")
            return False

        log(f"[KeepAlive] EventSource connected for {account_name}")
        for _ in response.iter_content(chunk_size=1024):
            if not _is_running(stop_event):
                break

        elapsed = time.time() - start_time
        log(f"[KeepAlive] EventSource closed after {elapsed:.1f}s for {account_name}")
        return False

    except (requests.exceptions.ReadTimeout, requests.exceptions.Timeout):
        elapsed = time.time() - start_time
        log(f"[KeepAlive] EventSource stale after {elapsed:.1f}s for {account_name}")
        return False
    except requests.exceptions.ConnectionError as e:
        log(f"[KeepAlive] Connection error for {account_name}: {e}")
        return False
    except Exception as e:
        log(f"[KeepAlive] Error for {account_name}: {e}")
        return False
    finally:
        if response is not None:
            response.close()


def _account_keep_alive_loop(account_id, account_name, get_cookies_func, on_session_expired, stop_event):
    """сами не входим заново, ждём внешнего вызова update_session"""
    global _keep_alive_running

    log(f"[KeepAlive] Started EventSource thread for {account_name}")

    while _is_running(stop_event):
        cookies = get_cookies_func()

        if not cookies:
            # сессии нет, ждём повторного входа из cf3
            _wait_seconds(10, stop_event)
            continue

        session_expired = _hold_events_stream(cookies, account_name, stop_event)

        if session_expired:
            should_stop = on_session_expired()
            if should_stop:
                stop_event.set()
                break
            # ждём входа, проверяем раз в десять секунд
            log(f"[KeepAlive] Paused for {account_name}, waiting for re-login...")
            while _is_running(stop_event):
                _wait_seconds(10, stop_event)
                if get_cookies_func():
                    log(f"[KeepAlive] Resumed for {account_name}")
                    break
            continue

        if not _is_running(stop_event):
            break

        # браузер переоткрывает EventSource после обрывов, а перед этим
        # веб приложение дёргает /isAuthorized
        _wait_seconds(EVENT_RECONNECT_DELAY, stop_event)
        latest_cookies = get_cookies_func()
        if latest_cookies:
            authorized = _is_authorized(latest_cookies, account_name)
            if authorized is False:
                should_stop = on_session_expired()
                if should_stop:
                    stop_event.set()
                    break
            elif authorized is None:
                _wait_seconds(EVENT_RECONNECT_DELAY, stop_event)

    log(f"[KeepAlive] Stopped EventSource thread for {account_name}")


def _account_news_digest_loop(account_id, account_name, get_cookies_func, on_session_expired, stop_event):
    """запрашиваем новости аккаунта с тем же интервалом, что и веб клиент"""
    log(f"[KeepAlive] Started news digest thread for {account_name}")
    next_run = 0

    while _is_running(stop_event):
        cookies = get_cookies_func()
        if not cookies:
            next_run = 0
            _wait_seconds(10, stop_event)
            continue

        now = time.time()
        if now >= next_run:
            session_expired = _fetch_news_digest(cookies, account_name)
            if session_expired:
                should_stop = on_session_expired()
                if should_stop:
                    stop_event.set()
                    break
                next_run = 0
            else:
                next_run = now + NEWS_DIGEST_INTERVAL

        _wait_seconds(1, stop_event)

    log(f"[KeepAlive] Stopped news digest thread for {account_name}")


def _start_account_threads(account_id, account_name, get_cookies_func, on_session_expired):
    """запускаем фоновые соединения для поддержания сессии аккаунта"""
    stop_event = threading.Event()
    events_thread = threading.Thread(
        target=_account_keep_alive_loop,
        args=(account_id, account_name, get_cookies_func, on_session_expired, stop_event),
        daemon=True,
    )
    news_thread = threading.Thread(
        target=_account_news_digest_loop,
        args=(account_id, account_name, get_cookies_func, on_session_expired, stop_event),
        daemon=True,
    )
    events_thread.start()
    news_thread.start()

    with _account_threads_lock:
        _account_threads[account_id] = {
            "events": events_thread,
            "news": news_thread,
            "stop": stop_event,
        }


def _stop_account_threads(account_id):
    with _account_threads_lock:
        entry = _account_threads.pop(account_id, None)
    if entry:
        entry["stop"].set()


def _account_threads_alive(account_id):
    entry = _account_threads.get(account_id)
    return bool(entry and entry["events"].is_alive() and entry["news"].is_alive())


def mark_account_session_invalid(account_id, username=None, reason="session_expired", notify=True):
    """при недействительной сессии останавливаем обращения к eschool; True означает смену состояния"""
    if not account_id or account_id == "server":
        return False

    with _sessions_lock:
        _sessions[account_id] = None
    delete_user_session(account_id)
    _stop_account_threads(account_id)

    conn = get_db_connection()
    if not conn:
        return False

    changed = False
    account_username = username
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT username, session_invalid
            FROM cf3_registrations
            WHERE id = %s
        """, (account_id,))
        row = cursor.fetchone()
        if row:
            account_username = account_username or row.get('username')
            already_invalid = bool(row.get('session_invalid'))
            cursor.execute("""
                UPDATE cf3_registrations
                SET session_invalid = TRUE,
                    session_invalid_reason = %s,
                    session_invalid_at = COALESCE(session_invalid_at, NOW()),
                    last_check_at = NOW()
                WHERE id = %s
            """, (reason, account_id))
            changed = not already_invalid
        conn.commit()
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"[KeepAlive] Error marking session invalid for {account_id}: {e}")
        return False

    if changed and notify:
        try:
            from .telegram_bot import send_session_invalid_message
            send_session_invalid_message(account_id, account_username, reason)
        except Exception as e:
            log(f"[KeepAlive] Error sending session invalid notice for {account_id}: {e}")

    log(f"[KeepAlive] Session marked invalid for {account_id}: {reason}")
    return changed


def _start_server_account_thread():
    """поддерживаем сессию основного аккаунта сервера"""

    def get_cookies():
        return server_state.cookies

    def on_session_expired():
        # серверный аккаунт можем перелогинить сразу
        if ESCHOOL_USERNAME and ESCHOOL_PASSWORD:
            cookies = server_login(ESCHOOL_USERNAME, ESCHOOL_PASSWORD)
            if cookies:
                server_state.cookies = cookies
                log(f"[KeepAlive] Server re-logged in")
        return False

    _start_account_threads("server", "server", get_cookies, on_session_expired)


def _start_cf3_account_thread(reg_id, username):
    """поддерживаем сессию зарегистрированного аккаунта"""

        # если в памяти пусто, поднимаем из базы
    with _sessions_lock:
        if reg_id not in _sessions:
            persisted = load_user_session(reg_id)
            if persisted:
                _sessions[reg_id] = persisted
                log(f"[KeepAlive] Loaded persisted session for {username}")
            else:
                _sessions[reg_id] = None

    def get_cookies():
        with _sessions_lock:
            return _sessions.get(reg_id)

    def on_session_expired():
        # помечаем сессию негодной и глушим аккаунт, пока пользователь не зарегистрируется заново
        mark_account_session_invalid(reg_id, username, "session_expired", notify=True)
        return True

    _start_account_threads(reg_id, username, get_cookies, on_session_expired)


def _monitor_cf3_registrations():
    """подхватываем новые регистрации и запускаем поддержку их сессий"""
    global _keep_alive_running

    log("[KeepAlive] CF3 registration monitor started")

    while _keep_alive_running:
        try:
            conn = get_db_connection()
            if conn:
                cursor = conn.cursor(dictionary=True)
                cursor.execute("""
                    SELECT id, username
                    FROM cf3_registrations
                    WHERE COALESCE(session_invalid, FALSE) = FALSE
                """)
                registrations = cursor.fetchall()
                cursor.close()
                conn.close()

                for reg in registrations:
                    reg_id = reg['id']

                    with _account_threads_lock:
                        alive = _account_threads_alive(reg_id)
                    if alive:
                        continue

                    _stop_account_threads(reg_id)
                    _start_cf3_account_thread(reg_id, reg['username'])

                # подчищаем удалённые регистрации
                current_ids = {reg['id'] for reg in registrations}
                with _account_threads_lock:
                    dead_ids = [k for k in _account_threads.keys()
                               if k != "server" and k not in current_ids]
                for dead_id in dead_ids:
                    log(f"[KeepAlive] Removing threads for deleted registration: {dead_id}")
                    _stop_account_threads(dead_id)

                with _sessions_lock:
                    dead_sessions = [k for k in _sessions.keys() if k not in current_ids]
                    for dead_id in dead_sessions:
                        del _sessions[dead_id]

        except Exception as e:
            log(f"[KeepAlive] Monitor error: {e}")

        for _ in range(30):
            if not _keep_alive_running:
                break
            time.sleep(1)

    log("[KeepAlive] CF3 registration monitor stopped")


def start_keep_alive():
    """запускаем поддержку сессий"""
    global _keep_alive_running

    if _keep_alive_running:
        log("[KeepAlive] Already running")
        return

    _keep_alive_running = True

    _start_server_account_thread()

    monitor_thread = threading.Thread(target=_monitor_cf3_registrations, daemon=True)
    monitor_thread.start()

    log(
        f"[KeepAlive] Started (EventSource reconnect: {EVENT_RECONNECT_DELAY}s, "
        f"news digest: {NEWS_DIGEST_INTERVAL}s)"
    )


def stop_keep_alive():
    """останавливаем все потоки поддержки сессий"""
    global _keep_alive_running
    _keep_alive_running = False
    with _account_threads_lock:
        entries = list(_account_threads.values())
    for entry in entries:
        entry["stop"].set()
    log("[KeepAlive] Stop requested")


def get_session(account_id):
    """просроченная или отсутствующая сессия возвращает None"""
    with _sessions_lock:
        return _sessions.get(account_id)


def update_session(account_id, cookies):
    """после успешного входа обновляем куки и сохраняем их в базу, чтобы пережить перезапуск"""
    with _sessions_lock:
        _sessions[account_id] = cookies
    save_user_session(account_id, cookies)
    log(f"[KeepAlive] Session updated for {account_id}")


def invalidate_session(account_id):
    """помечаем истёкшую сессию недействительной"""
    mark_account_session_invalid(account_id, reason="session_invalidated", notify=True)
