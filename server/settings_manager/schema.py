"""метаданные формы доступны клиенту, значения секретов в ответ не попадают"""
import re
from urllib.parse import urlsplit

FIELDS = {}


def field(key, label, group, default='', kind='text', *, secret=False, hint='', minimum=0, maximum=2147483647, locked=''):
    FIELDS[key] = dict(key=key, label=label, group=group, default=default, kind=kind,
                       secret=secret, hint=hint, minimum=minimum, maximum=maximum, locked=locked)


field('ESCHOOL_USERNAME', 'Логин сервера', 'eschool', hint='Аккаунт eSchool для проверки пользователей')
field('ESCHOOL_PASSWORD', 'Пароль eSchool', 'eschool', secret=True)
field('ESCHOOL_VERSION_URL', 'Источник версии eSchool', 'eschool', 'https://github.com/reSchool-org/reSchool-flutter/releases/latest/download/eschool-version.txt', 'url')
field('ESCHOOL_VERSION_FALLBACK', 'Запасная версия eSchool', 'eschool', '8.1.0')
for key, label, default in [('MIN_CHECK_INTERVAL', 'Минимальный интервал, мин', '10'), ('DEFAULT_CHECK_INTERVAL', 'Интервал по умолчанию, мин', '10')]:
    field(key, label, 'eschool', default, 'integer', minimum=1, maximum=1440)
field('ANALYSIS_ENABLED', 'Разбор заданий нейросетью', 'ai', 'true', 'boolean')
field('AI_PROVIDER', 'Провайдер ИИ', 'ai', 'google', 'select')
FIELDS['AI_PROVIDER']['options'] = [
    {'value': 'google', 'label': 'Google'},
    {'value': 'openrouter', 'label': 'OpenRouter'},
]
field('OPENROUTER_API_KEY', 'Ключ OpenRouter API', 'ai', secret=True, hint='API-ключ из личного кабинета OpenRouter')
field('OPENROUTER_MODEL', 'Модель OpenRouter', 'ai', 'google/gemini-3.8-flash', hint='Идентификатор из каталога OpenRouter. Для учебников нужна модель с поддержкой изображений и JSON Schema.')
field('OPENROUTER_TIMEOUT_SECONDS', 'Ожидание ответа OpenRouter, сек', 'ai', '900', 'integer', minimum=10, maximum=3600)
field('GEMINI_VERTEX_PROJECT', 'Проект Google Cloud', 'ai', hint='Для Vertex AI; ключ сервисного аккаунта уже хранится на сервере')
field('GEMINI_VERTEX_LOCATION', 'Регион Vertex AI', 'ai', 'global')
field('GEMINI_API_KEY', 'Ключ Gemini API', 'ai', secret=True, hint='Альтернатива Vertex AI')
field('GEMINI_MODEL', 'Модель', 'ai', 'gemini-3.8-flash')
field('GEMINI_TIMEOUT_SECONDS', 'Ожидание ответа ИИ, сек', 'ai', '900', 'integer', minimum=10, maximum=3600)
field('ANALYSIS_NOTIFICATION_TIMEOUT_SECONDS', 'Ожидание разбора для уведомления, сек', 'ai', '300', 'integer', minimum=10, maximum=3600)
field('TEXTBOOK_INDEX_CHUNK', 'Страниц в запросе индексации', 'ai', '16', 'integer', minimum=1, maximum=16)
field('MAX_TEXTBOOK_SIZE', 'Максимальный размер PDF, байт', 'ai', str(400 * 1024 * 1024), 'integer', minimum=1048576, maximum=1073741824)
field('CUSTOM_MODERATION_DELAY_SECONDS', 'Задержка проверки задания, сек', 'ai', '40', 'integer', minimum=0, maximum=3600)
field('MERGE_REBUILD_DELAY_SECONDS', 'Задержка объединения заданий, сек', 'ai', '30', 'integer', minimum=0, maximum=3600)
field('PUBLIC_BASE_URL', 'Публичный адрес', 'network', kind='url', hint='Адрес для ссылок из Telegram')
field('ALLOWED_CORS_ORIGINS', 'Разрешённые сайты', 'network', hint='Адреса HTTPS через запятую')
field('BROWSER_SIGNAL_URL', 'Сервер браузерного подключения', 'browser', 'wss://reschool.app/signal', 'wss')
field('BROWSER_SIGNAL_PUBLIC_URL', 'Публичный адрес подключения', 'browser', kind='wss', hint='Пусто - использовать адрес выше')
field('BROWSER_SERVER_URL', 'Адрес сервера для устройств', 'browser', kind='url', hint='Изменение адреса может потребовать переподключения браузера')
field('BROWSER_ALLOW_INSECURE_SIGNALING', 'Разрешить подключение без TLS', 'browser', 'false', 'boolean', hint='Только для локальной сети')
field('CACHE_ENABLED', 'Кеширование', 'cache', 'true', 'boolean')
field('CACHE_PREFIX', 'Префикс кеша', 'cache', 'reschool')
for key, label, default in [('CACHE_TTL_SECONDS', 'Срок хранения данных, сек', '300'), ('CACHE_SESSION_TTL_SECONDS', 'Срок хранения сессий, сек', '3600'), ('CACHE_AUTH_TTL_SECONDS', 'Срок хранения авторизации, сек', '120')]:
    field(key, label, 'cache', default, 'integer', minimum=1, maximum=86400)
for key, label, default, maximum in [('DB_CONNECT_TIMEOUT', 'Ожидание подключения, сек', '10', 120), ('DB_POOL_MIN_SIZE', 'Минимум соединений', '1', 100), ('DB_POOL_MAX_SIZE', 'Максимум соединений', '10', 100), ('DB_POOL_TIMEOUT', 'Ожидание свободного соединения, сек', '10', 120), ('DB_STATEMENT_TIMEOUT_MS', 'Ожидание запроса, мс', '15000', 300000)]:
    field(key, label, 'database', default, 'integer', minimum=1, maximum=maximum)

IDENTITY = 'Защищено: замена требует переноса базы или повторной привязки устройств.'
for key, label, default, secret in [('DB_HOST', 'Хост базы данных', 'db', False), ('DB_PORT', 'Порт базы данных', '5432', False), ('DB_USER', 'Пользователь базы данных', 'reschool', False), ('DB_PASSWORD', 'Пароль базы данных', '', True), ('DB_NAME', 'База данных', 'reschool', False), ('DATABASE_URL', 'Строка подключения к базе', '', True)]:
    field(key, label, 'database', default, secret=secret, locked=IDENTITY)
for key, label, default, secret in [('REDIS_HOST', 'Хост Redis', 'redis', False), ('REDIS_PORT', 'Порт Redis', '6379', False), ('REDIS_DB', 'База Redis', '0', False), ('REDIS_PASSWORD', 'Пароль Redis', '', True), ('REDIS_URL', 'Строка подключения Redis', '', True)]:
    field(key, label, 'cache', default, secret=secret, locked='Подключение задаётся при установке Redis; изменение требует согласованной настройки сервиса.')
field('API_TOKEN', 'Ключ администратора', 'security', secret=True, locked=IDENTITY)
for key in ('CF3_ENCRYPTION_KEY', 'ENCRYPTION_KEY'):
    field(key, 'Ключ шифрования' + (' (основной)' if key == 'ENCRYPTION_KEY' else ''), 'security', secret=True, locked='Защищает сохранённые пароли. Замена без перешифрования сделает их недоступными.')
field('TLS_SANS', 'Адреса сертификата', 'network', locked='Сертификат уже закреплён на устройствах. Его параметры меняются при перевыпуске.')
field('TLS_PORT', 'Порт HTTPS', 'network', '4443', locked='Порт согласован с прокси и сертификатом при установке.')
field('SERVER_PUBLIC_IP', 'Публичный IP', 'network', locked='Используется при выпуске сертификата; текущий сертификат сохраняется.')
field('SERVER_DOMAIN', 'Домен сервера', 'network', locked='Используйте раздел «Свой домен» на предыдущем экране: там проверяется HTTPS.')
field('DEBUG_REQUEST_LOG_FULL', 'Подробный журнал запросов', 'security', 'false', 'boolean', locked='Подробный журнал может содержать пароли. Для рабочего сервера доступен только просмотр.')
field('MIGRATIONS_ALLOW_CHECKSUM_DRIFT', 'Изменение применённых миграций', 'security', 'false', 'boolean', locked='Служебный режим восстановления базы данных.')
for alias, source in [('CF3_MIN_CHECK_INTERVAL', 'MIN_CHECK_INTERVAL'), ('CF3_DEFAULT_CHECK_INTERVAL', 'DEFAULT_CHECK_INTERVAL')]:
    field(alias, FIELDS[source]['label'] + ' (старое имя)', 'eschool', '10', 'integer', minimum=1, maximum=1440)


def validate(changes, fields):
    if not isinstance(changes, dict) or not changes or len(changes) > len(fields):
        raise ValueError('Выберите настройки для изменения')
    available = {f['key']: f for f in fields}
    for key, value in changes.items():
        spec = available.get(key)
        if spec is None or spec['locked']:
            raise ValueError(f'{key}: настройка защищена')
        if not isinstance(value, str) or len(value) > 4096 or any(ord(c) < 32 for c in value):
            raise ValueError(f'{spec["label"]}: недопустимое значение')
        if spec['kind'] == 'integer':
            if not re.fullmatch(r'[0-9]+', value) or not spec['minimum'] <= int(value) <= spec['maximum']:
                raise ValueError(f'{spec["label"]}: введите число от {spec["minimum"]} до {spec["maximum"]}')
        if spec['kind'] == 'boolean' and value not in ('true', 'false'):
            raise ValueError(f'{spec["label"]}: выберите да или нет')
        if spec['kind'] == 'select' and value not in {option['value'] for option in spec['options']}:
            raise ValueError(f'{spec["label"]}: выберите значение из списка')
        if spec['kind'] in ('url', 'wss') and value:
            url = urlsplit(value)
            schemes = ('ws', 'wss') if spec['kind'] == 'wss' else ('http', 'https')
            if url.scheme not in schemes or not url.hostname or url.username or url.password or url.fragment:
                raise ValueError(f'{spec["label"]}: введите полный адрес без пароля и фрагмента')
        if key == 'ALLOWED_CORS_ORIGINS' and value:
            for origin in value.split(','):
                url = urlsplit(origin.strip())
                if url.scheme != 'https' or not url.hostname or url.path not in ('', '/') or url.query or url.fragment or url.username:
                    raise ValueError('Разрешённые сайты: укажите HTTPS адреса через запятую')
        if key in ('GEMINI_MODEL', 'OPENROUTER_MODEL', 'GEMINI_VERTEX_LOCATION', 'CACHE_PREFIX') and not value.strip():
            raise ValueError(f'{spec["label"]}: значение не может быть пустым')
