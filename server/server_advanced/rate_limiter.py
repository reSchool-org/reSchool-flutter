import ipaddress
import os
import time
import threading
from collections import defaultdict
from functools import wraps

from flask import request, jsonify

from . import cache
from .logging_utils import log


TRUSTED_PROXY_NETWORKS = []
for raw_proxy_ip in os.getenv("TRUSTED_PROXY_IPS", "").split(","):
    raw_proxy_ip = raw_proxy_ip.strip()
    if not raw_proxy_ip:
        continue
    try:
        TRUSTED_PROXY_NETWORKS.append(ipaddress.ip_network(raw_proxy_ip, strict=False))
    except ValueError:
        pass


class RateLimiter:
    """скользящее окно на запросы, считаем в redis, а без него в памяти процесса"""

    def __init__(self):
        self.requests = defaultdict(list)
        self.lock = threading.Lock()
        # последний ответ redis, чтобы get_retry_after не ходил за ним второй раз
        self._last_retry_after = {}

        self.limits = {
            'verification': {'requests': 5, 'window': 300},
            'notification_register': {'requests': 2, 'window': 300},  # два раза за пять минут
            'token_check': {'requests': 30, 'window': 60},
            'devices': {'requests': 20, 'window': 60},
            'default': {'requests': 60, 'window': 60},
        }

    def _limit_for(self, limit_type):
        return self.limits.get(limit_type, self.limits['default'])

    def _clean_old_requests(self, ip, window):
        """запросы за пределами окна больше не влияют на лимит"""
        now = time.time()
        self.requests[ip] = [t for t in self.requests[ip] if now - t < window]

    def is_allowed(self, ip, limit_type='default'):
        """разрешённый запрос сразу учитываем в лимите"""
        limit = self._limit_for(limit_type)
        max_requests = limit['requests']
        window = limit['window']

        shared = cache.rate_limit_hit(f"{limit_type}:{ip}", max_requests, window)
        if shared is not None:
            allowed, retry_after = shared
            # запоминаем только отказы, иначе словарь будет расти на каждый успешный запрос
            if allowed:
                self._last_retry_after.pop((ip, limit_type), None)
            else:
                self._last_retry_after[(ip, limit_type)] = retry_after
            return allowed

        with self.lock:
            self._clean_old_requests(ip, window)

            if len(self.requests[ip]) >= max_requests:
                return False

            self.requests[ip].append(time.time())
            return True

    def get_retry_after(self, ip, limit_type='default'):
        """возвращаем число секунд до следующей разрешённой попытки"""
        limit = self._limit_for(limit_type)
        window = limit['window']

        shared = self._last_retry_after.pop((ip, limit_type), None)
        if shared is not None:
            return shared

        with self.lock:
            if not self.requests[ip]:
                return 0
            oldest = min(self.requests[ip])
            return max(0, int(window - (time.time() - oldest)))


# общий ограничитель на всё приложение
rate_limiter = RateLimiter()


def _parse_ip(ip):
    if not ip:
        return None
    try:
        return ipaddress.ip_address(ip)
    except ValueError:
        return None


def is_local_ip(ip):
    """проверяем, что адрес действительно принадлежит локальному хосту"""
    parsed = _parse_ip(ip)
    if not parsed:
        return False
    return parsed.is_loopback


def _is_trusted_proxy(ip):
    parsed = _parse_ip(ip)
    if not parsed:
        return False
    return parsed.is_loopback or any(parsed in network for network in TRUSTED_PROXY_NETWORKS)


def _client_ip():
    remote_ip = request.remote_addr
    if _is_trusted_proxy(remote_ip):
        forwarded_for = request.headers.get('X-Forwarded-For')
        if forwarded_for:
            first_hop = forwarded_for.split(',')[0].strip()
            if _parse_ip(first_hop):
                return first_hop
    return remote_ip or 'unknown'


def client_ip():
    return _client_ip()


def rate_limit(limit_type='default'):
    """ограничиваем частоту запросов к обработчику"""
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            ip = _client_ip()

            # лимит снимаем только для настоящих локальных вызовов, подделанному заголовку с цепочкой прокси не верим
            if is_local_ip(request.remote_addr) and not request.headers.get('X-Forwarded-For'):
                return f(*args, **kwargs)

            if not rate_limiter.is_allowed(ip, limit_type):
                retry_after = rate_limiter.get_retry_after(ip, limit_type)
                log(f"Rate limit exceeded for {ip} on {limit_type}")
                response = jsonify({
                    'error': 'Too many requests',
                    'retry_after': retry_after
                })
                response.headers['Retry-After'] = str(retry_after)
                return response, 429

            return f(*args, **kwargs)
        return wrapper
    return decorator
