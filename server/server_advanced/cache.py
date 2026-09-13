"""кеш на redis: горячие выборки, сессии eSchool и счётчики рейт лимита
кеш всегда необязателен. Если redis не поднят или отвалился, все функции
тихо превращаются в заглушки, а сервер продолжает ходить в postgres"""

import json
import threading
import time

from .config import (
    CACHE_ENABLED,
    CACHE_PREFIX,
    CACHE_TTL_SECONDS,
    REDIS_URL,
)
from .logging_utils import log


# отдельный объект, чтобы отличать промах кеша от закешированного None
MISS = object()

# пауза после обрыва: не долбимся в мёртвый redis на каждом запросе
_RETRY_AFTER_FAILURE = 30.0

_client = None
_lock = threading.Lock()
_disabled_until = 0.0
_reported_down = False
_reported_up = False

# атомарное окно рейт лимита: чистим протухшее, считаем, при запасе добавляем себя
_RATE_LIMIT_LUA = """
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])
redis.call('ZREMRANGEBYSCORE', KEYS[1], 0, now - window)
local used = redis.call('ZCARD', KEYS[1])
local oldest = redis.call('ZRANGE', KEYS[1], 0, 0, 'WITHSCORES')
local retry = 0
if oldest[2] then
    retry = math.ceil(window - (now - tonumber(oldest[2])))
    if retry < 0 then retry = 0 end
end
if used >= limit then
    return {0, retry}
end
redis.call('ZADD', KEYS[1], now, ARGV[4])
redis.call('EXPIRE', KEYS[1], window)
return {1, retry}
"""

_rate_limit_script = None


def _mark_down(error):
    """отключаем кеш на паузу и жалуемся ровно один раз на обрыв"""
    global _client, _disabled_until, _reported_down, _reported_up
    _client = None
    _rate_limit_script_reset()
    _disabled_until = time.time() + _RETRY_AFTER_FAILURE
    _reported_up = False
    if not _reported_down:
        _reported_down = True
        log(f"[Cache] Redis unavailable, falling back to Postgres only: {error}")


def _rate_limit_script_reset():
    global _rate_limit_script
    _rate_limit_script = None


def get_client():
    """соединение с redis или None, если кеша сейчас нет"""
    global _client, _disabled_until, _reported_down, _reported_up

    if not CACHE_ENABLED:
        return None
    if _client is not None:
        return _client
    if time.time() < _disabled_until:
        return None

    with _lock:
        if _client is not None:
            return _client
        try:
            import redis as redis_lib
        except ImportError as e:
            _mark_down(f"redis package is not installed ({e})")
            return None
        try:
            client = redis_lib.Redis.from_url(
                REDIS_URL,
                decode_responses=True,
                socket_timeout=2,
                socket_connect_timeout=2,
                health_check_interval=30,
            )
            client.ping()
        except Exception as e:
            _mark_down(e)
            return None

        _client = client
        _disabled_until = 0.0
        _reported_down = False
        if not _reported_up:
            _reported_up = True
            log("[Cache] Redis connected")
        return _client


def is_available():
    return get_client() is not None


def key(*parts):
    """собираем ключ вида reschool:auth:classmate:<token>"""
    return ':'.join([CACHE_PREFIX] + [str(part) for part in parts])


def get(name, default=MISS):
    """читаем значение, MISS означает, что в кеше его нет"""
    client = get_client()
    if client is None:
        return default
    try:
        raw = client.get(key(name))
    except Exception as e:
        _mark_down(e)
        return default
    if raw is None:
        return default
    try:
        return json.loads(raw)
    except ValueError:
        return default


def set(name, value, ttl=None):
    """кладём значение под json, ttl в секундах"""
    client = get_client()
    if client is None:
        return False
    try:
        client.setex(key(name), int(ttl or CACHE_TTL_SECONDS), json.dumps(value, ensure_ascii=False))
        return True
    except Exception as e:
        _mark_down(e)
        return False


def delete(*names):
    client = get_client()
    if client is None or not names:
        return False
    try:
        client.delete(*[key(name) for name in names])
        return True
    except Exception as e:
        _mark_down(e)
        return False


def delete_prefix(prefix):
    """сносим всё под префиксом, идём через scan, чтобы не блокировать redis"""
    client = get_client()
    if client is None:
        return False
    try:
        pattern = key(prefix) + '*'
        batch = []
        for found in client.scan_iter(match=pattern, count=500):
            batch.append(found)
            if len(batch) >= 500:
                client.delete(*batch)
                batch = []
        if batch:
            client.delete(*batch)
        return True
    except Exception as e:
        _mark_down(e)
        return False


def bump_version(name):
    """двигаем счётчик версии, старые ключи с ним в имени просто перестают находиться"""
    client = get_client()
    if client is None:
        return None
    try:
        return client.incr(key('ver', name))
    except Exception as e:
        _mark_down(e)
        return None


def version(name):
    """текущая версия набора, ноль если её ещё не заводили"""
    client = get_client()
    if client is None:
        return None
    try:
        raw = client.get(key('ver', name))
    except Exception as e:
        _mark_down(e)
        return None
    try:
        return int(raw or 0)
    except (TypeError, ValueError):
        return 0


def rate_limit_hit(name, limit, window):
    """скользящее окно на весь кластер, вернёт (allowed, retry_after) или None"""
    global _rate_limit_script
    client = get_client()
    if client is None:
        return None
    try:
        if _rate_limit_script is None:
            _rate_limit_script = client.register_script(_RATE_LIMIT_LUA)
        now = time.time()
        allowed, retry_after = _rate_limit_script(
            keys=[key('rl', name)],
            args=[now, window, limit, f"{now:.6f}"],
        )
        return bool(int(allowed)), max(0, int(retry_after))
    except Exception as e:
        _mark_down(e)
        return None
