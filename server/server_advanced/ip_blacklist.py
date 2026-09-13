import ipaddress
import json
import os
import threading

from .config import RUNTIME_DIR


IP_BLACKLIST_PATH = os.path.join(RUNTIME_DIR, "ip-blacklist.json")
_LOCK = threading.Lock()


def _normalize_entry(value):
    raw = str(value or "").strip()
    if not raw:
        return None, "Пустое значение"
    try:
        if "/" in raw:
            return str(ipaddress.ip_network(raw, strict=False)), None
        return str(ipaddress.ip_address(raw)), None
    except ValueError:
        return None, f"Неверный IP или CIDR: {raw}"


def _read_entries_unlocked():
    try:
        with open(IP_BLACKLIST_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        entries = data.get("entries") if isinstance(data, dict) else data
    except Exception:
        return []

    normalized = []
    for entry in entries or []:
        value, error = _normalize_entry(entry)
        if value and not error and value not in normalized:
            normalized.append(value)
    return normalized


def get_ip_blacklist():
    with _LOCK:
        return _read_entries_unlocked()


def set_ip_blacklist(entries):
    normalized = []
    errors = []
    for entry in entries or []:
        value, error = _normalize_entry(entry)
        if error:
            errors.append(error)
            continue
        if value not in normalized:
            normalized.append(value)

    if errors:
        return None, "; ".join(errors)

    os.makedirs(RUNTIME_DIR, exist_ok=True)
    with _LOCK:
        with open(IP_BLACKLIST_PATH, "w", encoding="utf-8") as f:
            json.dump({"entries": normalized}, f, ensure_ascii=False, indent=2)
    return normalized, None


def is_ip_blocked(ip):
    try:
        parsed_ip = ipaddress.ip_address(ip)
    except ValueError:
        return False

    for entry in get_ip_blacklist():
        try:
            if "/" in entry:
                if parsed_ip in ipaddress.ip_network(entry, strict=False):
                    return True
            elif parsed_ip == ipaddress.ip_address(entry):
                return True
        except ValueError:
            continue
    return False
