#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

ENV_FILE=".env"
SECRETS_DIR="secrets"
UPLOADS_DIR="server_advanced/uploads/custom_homework"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

random_token() {
  python3 -c "import secrets; print(secrets.token_urlsafe(32))"
}

random_password() {
  python3 -c "import secrets; print(secrets.token_urlsafe(18))"
}

fernet_key() {
  python3 -c "import base64, os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())"
}

read_value() {
  local prompt="$1"
  local default_value="${2:-}"
  local value

  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt [$default_value]: " value
    printf '%s' "${value:-$default_value}"
  else
    read -r -p "$prompt: " value
    printf '%s' "$value"
  fi
}

read_secret() {
  local prompt="$1"
  local value

  read -r -s -p "$prompt: " value
  printf '\n' >&2
  printf '%s' "$value"
}

read_yes_no() {
  local prompt="$1"
  local default_value="${2:-y}"
  local answer
  local suffix="[Y/n]"

  if [[ "$default_value" == "n" ]]; then
    suffix="[y/N]"
  fi

  read -r -p "$prompt $suffix: " answer
  answer="${answer:-$default_value}"

  [[ "$answer" =~ ^[YyДд] ]]
}

normalize_domain() {
  local value="$1"
  value="${value#http://}"
  value="${value#https://}"
  value="${value%%/*}"
  value="${value%%:*}"
  printf '%s' "$value"
}

escape_env_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

write_env_line() {
  local key="$1"
  local value="$2"
  printf '%s=' "$key" >> "$ENV_FILE"
  escape_env_value "$value" >> "$ENV_FILE"
  printf '\n' >> "$ENV_FILE"
}

ensure_python() {
  if ! command_exists python3; then
    echo "python3 не найден. Он нужен только для генерации токенов." >&2
    exit 1
  fi
}

run_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif command_exists sudo; then
    sudo "$@"
  else
    echo "Нужны root-права для установки Docker. Запустите скрипт от root или установите sudo." >&2
    exit 1
  fi
}

install_docker_apt() {
  export DEBIAN_FRONTEND=noninteractive
  run_root apt-get update

  if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
    run_root apt-get install -y docker.io docker-compose-v2
  elif apt-cache show docker-compose-plugin >/dev/null 2>&1; then
    run_root apt-get install -y docker.io docker-compose-plugin
  else
    run_root apt-get install -y docker.io docker-compose
  fi

  run_root systemctl enable --now docker || true
}

install_docker_dnf() {
  run_root dnf install -y docker docker-compose-plugin
  run_root systemctl enable --now docker || true
}

install_docker_yum() {
  run_root yum install -y docker docker-compose-plugin
  run_root systemctl enable --now docker || true
}

ensure_docker() {
  if command_exists docker && docker compose version >/dev/null 2>&1; then
    return
  fi

  echo
  echo "Docker или docker compose не найдены. Устанавливаю автоматически..."

  if command_exists apt-get; then
    install_docker_apt
  elif command_exists dnf; then
    install_docker_dnf
  elif command_exists yum; then
    install_docker_yum
  else
    echo "Не удалось определить пакетный менеджер. Установите Docker вручную." >&2
    exit 1
  fi

  if ! command_exists docker; then
    echo "Docker не установился или недоступен в PATH." >&2
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "docker compose недоступен после установки." >&2
    echo "Попробуйте: apt-get install -y docker-compose-v2" >&2
    exit 1
  fi

  echo "Docker установлен и запущен."
}

create_env() {
  local db_user db_password db_name eschool_username eschool_password server_domain public_base_url
  local api_token encryption_key debug_logs

  ensure_python

  db_user="$(read_value "DB_USER" "reschool")"
  db_password="$(read_value "DB_PASSWORD" "$(random_password)")"
  db_name="$(read_value "DB_NAME" "reschool")"
  eschool_username="$(read_value "ESCHOOL_USERNAME")"
  eschool_password="$(read_secret "ESCHOOL_PASSWORD")"
  server_domain="$(normalize_domain "$(read_value "SERVER_DOMAIN, например school.example.com (можно оставить пустым и настроить позже из приложения)")")"
  if [[ -n "$server_domain" ]]; then
    public_base_url="$(read_value "PUBLIC_BASE_URL для Telegram-кнопок" "https://$server_domain")"
  else
    public_base_url="$(read_value "PUBLIC_BASE_URL, например https://eschool.example.com (можно оставить пустым)")"
  fi
  api_token="$(read_value "API_TOKEN" "$(random_token)")"
  encryption_key="$(read_value "CF3_ENCRYPTION_KEY" "$(fernet_key)")"

  debug_logs="false"
  if read_yes_no "Включить подробные request/response логи? Только для локальной отладки" "n"; then
    debug_logs="true"
  fi

  : > "$ENV_FILE"
  write_env_line "ESCHOOL_USERNAME" "$eschool_username"
  write_env_line "ESCHOOL_PASSWORD" "$eschool_password"
  write_env_line "DB_HOST" "db"
  write_env_line "DB_PORT" "5432"
  write_env_line "DB_USER" "$db_user"
  write_env_line "DB_PASSWORD" "$db_password"
  write_env_line "DB_NAME" "$db_name"
  write_env_line "REDIS_HOST" "redis"
  write_env_line "REDIS_PORT" "6379"
  write_env_line "SERVER_DOMAIN" "$server_domain"
  write_env_line "PUBLIC_BASE_URL" "$public_base_url"
  write_env_line "API_TOKEN" "$api_token"
  write_env_line "DEBUG_REQUEST_LOG_FULL" "$debug_logs"
  write_env_line "CF3_ENCRYPTION_KEY" "$encryption_key"

  chmod 600 "$ENV_FILE"
  echo "Создан $ENV_FILE"
}

echo "reSchool server_advanced Docker setup"
echo

mkdir -p "$SECRETS_DIR" "$UPLOADS_DIR"
mkdir -p "server_advanced/runtime"

if [[ -f "$ENV_FILE" ]]; then
  echo "Файл $ENV_FILE уже существует."
  if read_yes_no "Перезаписать его новой интерактивной настройкой" "n"; then
    create_env
  else
    echo "Оставляю существующий $ENV_FILE без изменений."
  fi
else
  create_env
fi


ensure_docker

echo
echo "Основные команды:"
echo "  docker compose up --build -d"
echo "  docker compose logs -f server_advanced"
echo "  docker compose down"
echo
echo "После запуска:"
echo "  API:        http://localhost:20001"
echo "  HTTPS:      https://<ip>:4443 на своём сертификате, домен и сертификат от CA не нужны"
echo "  Отпечаток:  docker compose logs certgen, ссылку из него открывают на телефоне"
echo "  Домен:      если он есть, его можно задать из приложения, Caddy слушает 80/443"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  if [[ "${SERVER_DOMAIN:-}" != "" ]]; then
    echo "  Домен:      https://${SERVER_DOMAIN}"
    echo "  Сертификат: Caddy получит и продлит автоматически через Let's Encrypt"
  fi
fi
echo "  Adminer:    http://localhost:8080 (docker compose --profile dev up -d adminer)"

if read_yes_no "Запустить контейнеры сейчас" "y"; then
  docker compose up --build -d
fi
