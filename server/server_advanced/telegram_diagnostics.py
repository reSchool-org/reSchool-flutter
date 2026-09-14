"""для диагностики доставки не нужны токены, текст задания и содержимое вложений"""
import json
import logging
from logging.handlers import RotatingFileHandler
import os
import re
import threading
from datetime import datetime, timezone


_handler = None
_handler_lock = threading.Lock()


def error_details(error, secrets=()):
    result = {'error_type': type(error).__name__}
    method = getattr(error, 'function_name', None)
    if isinstance(method, str) and re.fullmatch(r'[A-Za-z_]+', method):
        result['method'] = method
    # текст сетевой ошибки может содержать полный адрес с токеном бота
    code = getattr(error, 'error_code', None)
    description = getattr(error, 'description', None)
    if isinstance(code, int) and isinstance(description, str):
        for secret in secrets:
            if isinstance(secret, str) and secret:
                description = description.replace(secret, '[REDACTED]')
        description = re.sub(r'https?://\S+', '[URL]', description)
        description = re.sub(r'\b\d+:[A-Za-z0-9_-]+', '[BOT_TOKEN]', description)
        description = re.sub(r'(?i)(token|password|secret|cookie|authorization)\s*[=:]\s*\S+',
                             r'\1=[REDACTED]', description)
        result.update(error_code=code, description=description[:1000])
        response = getattr(error, 'result_json', None)
        parameters = response.get('parameters', {}) if isinstance(response, dict) else {}
        if isinstance(parameters, dict) and isinstance(parameters.get('retry_after'), int):
            result['retry_after'] = parameters['retry_after']
    return result


def delivery_log(logger, event, **fields):
    global _handler
    record = json.dumps({
        'time': datetime.now(timezone.utc).isoformat(), 'event': event, **fields,
    }, ensure_ascii=False, default=str)
    logger('[TelegramDelivery] ' + record)
    # папка журналов смонтирована с хоста, поэтому переживает пересоздание контейнера
    runtime = os.environ.get('RESCHOOL_RUNTIME_DIR')
    if not runtime:
        return
    try:
        with _handler_lock:
            if _handler is None:
                folder = os.path.join(runtime, 'logs')
                os.makedirs(folder, mode=0o750, exist_ok=True)
                _handler = RotatingFileHandler(os.path.join(folder, 'telegram-delivery.jsonl'),
                                              maxBytes=5 * 1024 * 1024, backupCount=4, encoding='utf-8')
                _handler.setFormatter(logging.Formatter('%(message)s'))
            _handler.handle(logging.LogRecord('telegram.delivery', logging.INFO, '', 0, record, (), None))
    except Exception as error:
        logger(f'[TelegramDelivery] File log unavailable: {type(error).__name__}')
