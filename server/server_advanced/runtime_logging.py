"""собираем ошибки сервера в общий журнал без секретов"""
import logging
from logging.handlers import RotatingFileHandler
import os
import re
import sys
import threading

_handler = None
_lock = threading.Lock()
_configured = False


def safe_text(value):
    text = str(value)
    text = re.sub(r'https?://[^\s<>"\']+', '[URL]', text)
    text = re.sub(r'\b\d{3,}:[A-Za-z0-9_-]{3,}', '[BOT_TOKEN]', text)
    text = re.sub(r'(?i)((?:[\w-]*(?:token|password|passwd|secret|cookie|authorization|api_key)[\w-]*)["\']?\s*[:=]\s*)(?:"[^"\n]*"|\'[^\'\n]*\'|[^\s,;]+)',
                  r'\1[REDACTED]', text)
    return text


class SafeFormatter(logging.Formatter):
    def format(self, record):
        return safe_text(super().format(record))


class SafeFileHandler(RotatingFileHandler):
    def handleError(self, record):
        # стандартный обработчик печатает исходную запись с неочищенными данными
        print('[Logging] Persistent log write failed', file=sys.stderr, flush=True)


def _get_handler():
    global _handler
    runtime = os.environ.get('RESCHOOL_RUNTIME_DIR')
    if not runtime:
        return None
    with _lock:
        if _handler is None:
            folder = os.path.join(runtime, 'logs')
            os.makedirs(folder, mode=0o750, exist_ok=True)
            _handler = SafeFileHandler(os.path.join(folder, 'server.log'),
                                          maxBytes=20 * 1024 * 1024, backupCount=4, encoding='utf-8')
            _handler.setFormatter(SafeFormatter('%(asctime)s %(levelname)s [%(threadName)s] %(message)s'))
        return _handler


def write_log(message, exc_info=None):
    try:
        handler = _get_handler()
        if handler:
            record = logging.LogRecord('reschool', logging.ERROR if exc_info else logging.INFO,
                                       '', 0, message, (), exc_info)
            handler.handle(record)
    except Exception as error:
        print(f'[Logging] Persistent log unavailable: {type(error).__name__}', flush=True)


def configure():
    global _configured
    if _configured:
        return
    handler = _get_handler()
    if not handler:
        return
    _configured = True
    # ошибки библиотек тоже нужны в общем журнале
    handler.setLevel(logging.INFO)
    logging.getLogger().addHandler(handler)
    original_sys_hook = sys.excepthook
    original_thread_hook = threading.excepthook

    def sys_hook(kind, value, tb):
        write_log('Unhandled exception', (kind, value, tb))
        original_sys_hook(kind, value, tb)

    def thread_hook(args):
        write_log(f'Unhandled thread exception: {args.thread.name}',
                  (args.exc_type, args.exc_value, args.exc_traceback))
        original_thread_hook(args)

    sys.excepthook = sys_hook
    threading.excepthook = thread_hook
