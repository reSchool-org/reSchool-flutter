import os
import json
from urllib.parse import urlparse
from dotenv import load_dotenv

load_dotenv()

# доступ к api eSchool
BASE_URL = "https://app.eschool.center/ec-server"
USER_AGENT = "eSchoolMobile"

# база данных, postgres
DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_USER = os.getenv("DB_USER", "reschool")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password")
DB_NAME = os.getenv("DB_NAME", "reschool")

# строка DATABASE_URL перебивает поля выше, удобно для внешней базы
DATABASE_URL = os.getenv("DATABASE_URL", "").strip()


def build_database_dsn():
    """строка подключения libpq, собранная из отдельных полей"""
    if DATABASE_URL:
        return DATABASE_URL
    return (
        f"host={DB_HOST} port={DB_PORT} dbname={DB_NAME} "
        f"user={DB_USER} password={DB_PASSWORD}"
    )


DB_DSN = build_database_dsn()
DB_CONNECT_TIMEOUT = int(os.getenv("DB_CONNECT_TIMEOUT", "10"))
DB_POOL_MIN_SIZE = int(os.getenv("DB_POOL_MIN_SIZE", "1"))
DB_POOL_MAX_SIZE = int(os.getenv("DB_POOL_MAX_SIZE", "10"))
# сколько ждём свободное соединение из пула, прежде чем сдаться
DB_POOL_TIMEOUT = float(os.getenv("DB_POOL_TIMEOUT", "10"))
DB_STATEMENT_TIMEOUT_MS = int(os.getenv("DB_STATEMENT_TIMEOUT_MS", "15000"))
# накатанную миграцию править нельзя, но иногда очень надо, тогда включаем этот флаг
MIGRATIONS_ALLOW_CHECKSUM_DRIFT = os.getenv(
    "MIGRATIONS_ALLOW_CHECKSUM_DRIFT", "false"
).strip().lower() in {"1", "true", "yes", "on"}

# кеш, redis
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_DB = int(os.getenv("REDIS_DB", "0"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")


def build_redis_url():
    """строка REDIS_URL важнее отдельных полей, заданный пароль подставляем сами"""
    configured = os.getenv("REDIS_URL", "").strip()
    if configured:
        return configured
    auth = f":{REDIS_PASSWORD}@" if REDIS_PASSWORD else ""
    return f"redis://{auth}{REDIS_HOST}:{REDIS_PORT}/{REDIS_DB}"


REDIS_URL = build_redis_url()
CACHE_ENABLED = os.getenv("CACHE_ENABLED", "true").strip().lower() not in {"0", "false", "no", "off"}
CACHE_PREFIX = os.getenv("CACHE_PREFIX", "reschool").strip() or "reschool"
CACHE_TTL_SECONDS = int(os.getenv("CACHE_TTL_SECONDS", "300"))
# сессии eSchool держим дольше обычных выборок, они меняются редко
CACHE_SESSION_TTL_SECONDS = int(os.getenv("CACHE_SESSION_TTL_SECONDS", "3600"))
# токены авторизации кешируем совсем ненадолго, отзыв должен доезжать быстро
CACHE_AUTH_TTL_SECONDS = int(os.getenv("CACHE_AUTH_TTL_SECONDS", "120"))

# загрузка файлов
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RUNTIME_DIR = os.getenv("RESCHOOL_RUNTIME_DIR", os.path.join(SCRIPT_DIR, "runtime"))
DOMAIN_STATE_PATH = os.path.join(RUNTIME_DIR, "server-domain.json")
UPLOAD_FOLDER = os.path.join(SCRIPT_DIR, 'uploads', 'custom_homework')
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50 мегабайт
MAX_FILES_PER_HOMEWORK = 3
ALLOWED_EXTENSIONS = {'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'gif', 'txt', 'zip', 'rar'}

# ключ шифрования паролей
ENCRYPTION_KEY = os.getenv("ENCRYPTION_KEY") or os.getenv("CF3_ENCRYPTION_KEY")  # старое имя ключа тоже понимаем

# собственный аккаунт eSchool, им сервер ходит проверять пользователей
ESCHOOL_USERNAME = os.getenv("ESCHOOL_USERNAME")
ESCHOOL_PASSWORD = os.getenv("ESCHOOL_PASSWORD")

# публичный адрес сервера для подключения приложения и загрузки файлов
# значение PUBLIC_BASE_URL перебивает и домен из настроек, и SERVER_DOMAIN
SERVER_DOMAIN = os.getenv("SERVER_DOMAIN", "").strip().rstrip("/")
if SERVER_DOMAIN.startswith(("http://", "https://")):
    SERVER_DOMAIN = urlparse(SERVER_DOMAIN).netloc
SERVER_DOMAIN = SERVER_DOMAIN.split("/", 1)[0]
_PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "").strip().rstrip("/")


def _read_runtime_domain():
    try:
        with open(DOMAIN_STATE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        domain = str(data.get("domain") or "").strip().rstrip("/")
        return domain or ""
    except Exception:
        return ""


def get_server_domain():
    return _read_runtime_domain() or SERVER_DOMAIN


def set_runtime_server_domain(domain):
    os.makedirs(RUNTIME_DIR, exist_ok=True)
    with open(DOMAIN_STATE_PATH, "w", encoding="utf-8") as f:
        json.dump({"domain": domain}, f, ensure_ascii=False, indent=2)


def get_public_base_url():
    if _PUBLIC_BASE_URL:
        return _PUBLIC_BASE_URL
    domain = get_server_domain()
    if domain and not domain.startswith(":"):
        return f"https://{domain}"
    return ""


PUBLIC_BASE_URL = get_public_base_url()

# токен, которым клиенты доказывают, что они свои
API_TOKEN = os.getenv("API_TOKEN")

# логирование запросов и ответов, в полных логах лежат секреты, так что только локально
REQUEST_LOG_FULL_DEBUG = (
    os.getenv("DEBUG_REQUEST_LOG_FULL", "")
    or os.getenv("REQUEST_LOG_FULL_DEBUG", "")
    or os.getenv("FLASK_DEBUG", "")
).strip().lower() in {"1", "true", "yes", "on"} and os.getenv(
    "ALLOW_UNSAFE_FULL_REQUEST_LOGS", ""
).strip().lower() in {"1", "true", "yes", "on"}

# браузерные origin через запятую, им разрешаем ходить на эндпоинты с cors
# по умолчанию пусто: для своего сервера cors не нужен, нативным клиентам тем более
ALLOWED_CORS_ORIGINS = {
    origin.strip().rstrip("/")
    for origin in os.getenv("ALLOWED_CORS_ORIGINS", "").split(",")
    if origin.strip()
}

# как часто проверяем обновления
MIN_CHECK_INTERVAL = int(os.getenv("MIN_CHECK_INTERVAL", os.getenv("CF3_MIN_CHECK_INTERVAL", "10")))  # минуты
DEFAULT_CHECK_INTERVAL = int(os.getenv("DEFAULT_CHECK_INTERVAL", os.getenv("CF3_DEFAULT_CHECK_INTERVAL", "10")))  # минуты

# разбор учебников и домашнего задания нейросетью
AI_PROVIDER = os.getenv("AI_PROVIDER", "google").strip().lower() or "google"
OPENROUTER_API_KEY = os.getenv("OPENROUTER_API_KEY", "").strip()
OPENROUTER_MODEL = os.getenv("OPENROUTER_MODEL", "google/gemini-3.8-flash").strip() or "google/gemini-3.8-flash"
OPENROUTER_TIMEOUT_SECONDS = int(os.getenv("OPENROUTER_TIMEOUT_SECONDS", "900"))
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "").strip()
# версию клиента eSchool раз в три дня обновляет actions и кладёт в последний
# релиз, ссылка на latest не протухает
ESCHOOL_VERSION_URL = os.getenv(
    "ESCHOOL_VERSION_URL",
    "https://github.com/reSchool-org/reSchool-flutter/releases/latest/download/eschool-version.txt")
# если сеть недоступна, а кэша ещё нет
ESCHOOL_VERSION_FALLBACK = os.getenv("ESCHOOL_VERSION_FALLBACK", "8.1.0").strip()

GEMINI_VERTEX_PROJECT = os.getenv("GEMINI_VERTEX_PROJECT", "").strip()
GEMINI_VERTEX_LOCATION = os.getenv("GEMINI_VERTEX_LOCATION", "global").strip() or "global"
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.8-flash").strip()
GEMINI_TIMEOUT_SECONDS = int(os.getenv("GEMINI_TIMEOUT_SECONDS", "900"))
# лайты дают обрезанные координаты, так что модель тут не понижаем
ANALYSIS_ENABLED = os.getenv("ANALYSIS_ENABLED", "true").strip().lower() not in {"0", "false", "no", "off"}
# сколько ждём разбор, прежде чем сохранить уведомление без него
ANALYSIS_NOTIFICATION_TIMEOUT_SECONDS = int(os.getenv("ANALYSIS_NOTIFICATION_TIMEOUT_SECONDS", "300"))
# страниц в одном запросе при индексации, выше 16 растёт риск обрыва по лимиту вывода
TEXTBOOK_INDEX_CHUNK = int(os.getenv("TEXTBOOK_INDEX_CHUNK", "16"))
TEXTBOOK_FOLDER = os.path.join(SCRIPT_DIR, 'uploads', 'textbooks')
ANALYSIS_IMAGE_FOLDER = os.path.join(SCRIPT_DIR, 'uploads', 'analysis')
MAX_TEXTBOOK_SIZE = int(os.getenv("MAX_TEXTBOOK_SIZE", str(400 * 1024 * 1024)))

# папка для загрузок должна существовать
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
os.makedirs(RUNTIME_DIR, exist_ok=True)
os.makedirs(TEXTBOOK_FOLDER, exist_ok=True)
os.makedirs(ANALYSIS_IMAGE_FOLDER, exist_ok=True)
