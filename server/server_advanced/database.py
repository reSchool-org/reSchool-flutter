"""слой хранения: postgres как источник правды, redis как кеш поверх него
соединения раздаёт пул psycopg. Обёртка PooledConnection повторяет привычный
здесь API драйвера: cursor(dictionary=True), commit, rollback, close, только close
не рвёт соединение, а возвращает его в пул"""

import json
import threading

import psycopg
import requests
from psycopg.rows import dict_row, tuple_row
from psycopg.types.json import Jsonb
from psycopg_pool import ConnectionPool

from . import cache
from .config import (
    CACHE_AUTH_TTL_SECONDS,
    CACHE_SESSION_TTL_SECONDS,
    DB_CONNECT_TIMEOUT,
    DB_DSN,
    DB_POOL_MAX_SIZE,
    DB_POOL_MIN_SIZE,
    DB_POOL_TIMEOUT,
    DB_STATEMENT_TIMEOUT_MS,
)
from .logging_utils import log


_pool = None
_pool_lock = threading.Lock()
_pool_failed_reported = False


def _connection_kwargs():
    # часовой пояс держим в utc, тогда naive время из базы совпадает с datetime.now() в контейнере
    return {
        'autocommit': False,
        'connect_timeout': DB_CONNECT_TIMEOUT,
        'options': f"-c timezone=UTC -c statement_timeout={DB_STATEMENT_TIMEOUT_MS}",
        'application_name': 'reschool-server',
    }


def get_pool():
    """ленивый пул соединений, None если postgres так и не поднялся"""
    global _pool, _pool_failed_reported

    if _pool is not None:
        return _pool

    with _pool_lock:
        if _pool is not None:
            return _pool
        try:
            pool = ConnectionPool(
                conninfo=DB_DSN,
                min_size=DB_POOL_MIN_SIZE,
                max_size=DB_POOL_MAX_SIZE,
                kwargs=_connection_kwargs(),
                name='reschool',
                open=False,
                check=ConnectionPool.check_connection,
            )
            pool.open(wait=False)
        except Exception as e:
            if not _pool_failed_reported:
                _pool_failed_reported = True
                log(f"DB pool creation failed: {e}")
            return None
        _pool = pool
        _pool_failed_reported = False
        return _pool


class PooledConnection:
    """соединение из пула с привычным по mysql-connector интерфейсом"""

    __slots__ = ('_pool', '_conn', '_released')

    def __init__(self, pool, conn):
        self._pool = pool
        self._conn = conn
        self._released = False

    @property
    def raw(self):
        return self._conn

    def cursor(self, dictionary=False, **kwargs):
        """dictionary=True отдаёт строки словарями, как раньше делал драйвер mysql"""
        return self._conn.cursor(row_factory=dict_row if dictionary else tuple_row, **kwargs)

    def execute(self, query, params=None):
        return self._conn.execute(query, params)

    def commit(self):
        self._conn.commit()

    def rollback(self):
        self._conn.rollback()

    def close(self):
        """отдаём соединение в пул, откатив то, что читающие места не закоммитили,
        иначе пул сделает это сам и напишет предупреждение в лог"""
        if self._released:
            return
        self._released = True
        try:
            if self._conn.info.transaction_status != psycopg.pq.TransactionStatus.IDLE:
                self._conn.rollback()
        except Exception:
            pass
        try:
            self._pool.putconn(self._conn)
        except Exception as e:
            log(f"DB pool release failed: {e}")

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        if exc_type is not None:
            try:
                self.rollback()
            except Exception:
                pass
        self.close()
        return False


def json_value(value):
    """обёртка для jsonb колонки, голый dict psycopg разложить не умеет"""
    return None if value is None else Jsonb(value)


def get_db_connection():
    """соединение из пула или None, если база недоступна"""
    pool = get_pool()
    if pool is None:
        return None
    try:
        conn = pool.getconn(timeout=DB_POOL_TIMEOUT)
    except Exception as e:
        log(f"DB Connection failed: {e}")
        return None
    return PooledConnection(pool, conn)


def init_db():
    """доводим схему до актуальной версии, миграции лежат рядом в migrations"""
    # импорт локальный, иначе migrator и database закольцуются
    from .migrator import run_migrations
    return run_migrations()


def close_pool():
    """закрываем пул, нужно при штатной остановке сервера"""
    global _pool
    with _pool_lock:
        if _pool is None:
            return
        try:
            _pool.close()
        except Exception as e:
            log(f"DB pool close failed: {e}")
        _pool = None


# сессии eSchool

_SERVER_SESSION_CACHE_KEY = 'session:server'


def _cookies_to_dict(cookies):
    """приводим cookiejar или словарь к обычному dict, его и храним"""
    if cookies is None:
        return {}
    if hasattr(cookies, '_cookies'):
        return requests.utils.dict_from_cookiejar(cookies)
    if hasattr(cookies, 'items'):
        return dict(cookies)
    return {}


def _user_session_cache_key(registration_id):
    return f"session:user:{registration_id}"


def save_session(cookies):
    """сохраняем куки серверного аккаунта, копию кладём в кеш"""
    cookie_dict = _cookies_to_dict(cookies)
    cache.set(_SERVER_SESSION_CACHE_KEY, cookie_dict, CACHE_SESSION_TTL_SECONDS)

    conn = get_db_connection()
    if not conn:
        log("Cannot save session: DB not available")
        return

    try:
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO server_sessions (id, cookies)
            VALUES (1, %s)
            ON CONFLICT (id) DO UPDATE
            SET cookies = EXCLUDED.cookies,
                updated_at = (now() AT TIME ZONE 'utc')
        """, (json.dumps(cookie_dict),))
        conn.commit()
        cursor.close()
        log("Session saved to DB.")
    except Exception as e:
        conn.rollback()
        log(f"Error saving session to DB: {e}")
    finally:
        conn.close()


def load_session():
    """куки серверного аккаунта, сначала из кеша, потом из базы"""
    cached = cache.get(_SERVER_SESSION_CACHE_KEY)
    if cached is not cache.MISS and isinstance(cached, dict) and cached:
        return requests.utils.cookiejar_from_dict(cached)

    conn = get_db_connection()
    if not conn:
        return None

    try:
        cursor = conn.cursor()
        cursor.execute("SELECT cookies FROM server_sessions WHERE id = 1")
        row = cursor.fetchone()
        cursor.close()

        if row and row[0]:
            cookie_dict = json.loads(row[0])
            if cookie_dict:
                cache.set(_SERVER_SESSION_CACHE_KEY, cookie_dict, CACHE_SESSION_TTL_SECONDS)
                return requests.utils.cookiejar_from_dict(cookie_dict)
    except Exception as e:
        log(f"Error loading session from DB: {e}")
    finally:
        conn.close()

    return None


def save_user_session(registration_id, cookies):
    """куки пользователя пишем и в базу, и в кеш: их читает каждый круг монитора"""
    cookie_dict = _cookies_to_dict(cookies)
    cache.set(_user_session_cache_key(registration_id), cookie_dict, CACHE_SESSION_TTL_SECONDS)

    conn = get_db_connection()
    if not conn:
        return

    try:
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO cf3_sessions (registration_id, cookies)
            VALUES (%s, %s)
            ON CONFLICT (registration_id) DO UPDATE
            SET cookies = EXCLUDED.cookies,
                updated_at = (now() AT TIME ZONE 'utc')
        """, (registration_id, json.dumps(cookie_dict)))
        conn.commit()
        cursor.close()
    except Exception as e:
        conn.rollback()
        log(f"Error saving user session for {registration_id}: {e}")
    finally:
        conn.close()


def load_user_session(registration_id):
    """куки пользователя, cookiejar или None"""
    cached = cache.get(_user_session_cache_key(registration_id))
    if cached is not cache.MISS and isinstance(cached, dict) and cached:
        return requests.utils.cookiejar_from_dict(cached)

    conn = get_db_connection()
    if not conn:
        return None

    try:
        cursor = conn.cursor()
        cursor.execute("SELECT cookies FROM cf3_sessions WHERE registration_id = %s", (registration_id,))
        row = cursor.fetchone()
        cursor.close()

        if row and row[0]:
            cookie_dict = json.loads(row[0])
            if cookie_dict:
                cache.set(_user_session_cache_key(registration_id), cookie_dict, CACHE_SESSION_TTL_SECONDS)
                return requests.utils.cookiejar_from_dict(cookie_dict)
    except Exception as e:
        log(f"Error loading user session for {registration_id}: {e}")
    finally:
        conn.close()

    return None


def delete_user_session(registration_id):
    """убираем сессию отовсюду, иначе кеш вернёт уже мёртвые куки"""
    cache.delete(_user_session_cache_key(registration_id))

    conn = get_db_connection()
    if not conn:
        return

    try:
        cursor = conn.cursor()
        cursor.execute("DELETE FROM cf3_sessions WHERE registration_id = %s", (registration_id,))
        conn.commit()
        cursor.close()
    except Exception as e:
        conn.rollback()
        log(f"Error deleting user session for {registration_id}: {e}")
    finally:
        conn.close()


# кешированные выборки

_CLASSMATE_AUTH_KEY = 'auth:classmate:v2'
_CLASSMATE_TOKEN_INDEX_KEY = 'auth:classmate-token-of'
_VERIFIED_AUTH_KEY = 'auth:verified'
_HOMEWORK_VERSION_KEY = 'homework'


def get_classmate_by_token(token):
    """одноклассник по его токену, dict или None, ответ кешируем, а отзыв чистит кеш явно"""
    if not token:
        return None

    cached = cache.get(f"{_CLASSMATE_AUTH_KEY}:{token}")
    if cached is not cache.MISS:
        return cached

    conn = get_db_connection()
    if not conn:
        return None

    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT id, grade_class, display_name, monitoring_registration_id FROM classmate_registrations WHERE classmate_token = %s",
            (token,)
        )
        row = cursor.fetchone()
        cursor.close()
    except Exception as e:
        log(f"[Auth] Classmate token check error: {e}")
        return None
    finally:
        conn.close()

    if not row:
        return None

    classmate = {'id': row[0], 'grade_class': row[1], 'display_name': row[2], 'monitoring_registration_id': row[3]}
    remember_classmate_token(classmate['id'], token, classmate)
    return classmate


def remember_classmate_token(classmate_id, token, classmate):
    """держим и обратный индекс токенов по id, без него нечего чистить при выходе"""
    cache.set(f"{_CLASSMATE_AUTH_KEY}:{token}", classmate, CACHE_AUTH_TTL_SECONDS)
    cache.set(f"{_CLASSMATE_TOKEN_INDEX_KEY}:{classmate_id}", token, CACHE_SESSION_TTL_SECONDS)


def invalidate_classmate(classmate_id, token=None):
    """сносим кеш авторизации одноклассника, токен ищем через обратный индекс"""
    if token is None:
        stored = cache.get(f"{_CLASSMATE_TOKEN_INDEX_KEY}:{classmate_id}")
        token = stored if stored is not cache.MISS else None
    keys = [f"{_CLASSMATE_TOKEN_INDEX_KEY}:{classmate_id}"]
    if token:
        keys.append(f"{_CLASSMATE_AUTH_KEY}:{token}")
    cache.delete(*keys)


def get_cached_verified_user(token):
    """пара (prs_id, grade_class) из кеша или None"""
    cached = cache.get(f"{_VERIFIED_AUTH_KEY}:{token}")
    if cached is cache.MISS or not isinstance(cached, list) or len(cached) != 2:
        return None
    return cached[0], cached[1]


def cache_verified_user(token, prs_id, grade_class):
    """кешируем только удачный разбор токена, промахи пусть каждый раз идут в базу"""
    if not token or not prs_id:
        return
    cache.set(f"{_VERIFIED_AUTH_KEY}:{token}", [prs_id, grade_class], CACHE_AUTH_TTL_SECONDS)


def invalidate_verified_user(*tokens):
    cache.delete(*[f"{_VERIFIED_AUTH_KEY}:{token}" for token in tokens if token])


def invalidate_registration(registration_id):
    """регистрация удалилась, снимаем её горячую копию сессии, иначе кеш отдаст мёртвые куки"""
    cache.delete(_user_session_cache_key(registration_id))


def homework_version(grade_class):
    """версия набора домашних заданий класса, входит в ключ кеша списка"""
    value = cache.version(f"{_HOMEWORK_VERSION_KEY}:{grade_class}")
    return 0 if value is None else value


def invalidate_homework(grade_class):
    """двигаем версию, все закешированные списки этого класса разом протухают"""
    if grade_class:
        cache.bump_version(f"{_HOMEWORK_VERSION_KEY}:{grade_class}")
