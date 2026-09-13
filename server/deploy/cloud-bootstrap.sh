#!/usr/bin/env bash
# Bundled inside server.tar.gz; extracted and executed on the remote server.
set -euo pipefail
umask 077
work_dir="$1"
install_dir="/opt/reschool"
trap 'rm -f "$work_dir/connection.json"' EXIT
stage() { printf 'RESCHOOL_STAGE:%s\n' "$1"; }
if [[ $(id -u) != 0 ]]; then
  echo 'RESCHOOL_ERROR:Для установки нужны root или sudo'
  exit 1
fi
stage 'Подготавливаю Docker'
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  if ! command -v apt-get >/dev/null; then
    echo 'RESCHOOL_ERROR:Автоматическая установка поддерживает Ubuntu и Debian'
    exit 1
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y python3 ca-certificates curl
  . /etc/os-release
  case "$ID" in ubuntu|debian) ;; *)
    echo 'RESCHOOL_ERROR:Автоматическая установка поддерживает Ubuntu и Debian'
    exit 1;;
  esac
  if apt-cache show docker-compose-v2 >/dev/null 2>&1; then
    apt-get install -y docker.io docker-compose-v2
  else
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/reschool-docker.asc
    chmod a+r /etc/apt/keyrings/reschool-docker.asc
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/reschool-docker.asc] https://download.docker.com/linux/%s %s stable\n' \
      "$(dpkg --print-architecture)" "$ID" "${UBUNTU_CODENAME:-$VERSION_CODENAME}" > /etc/apt/sources.list.d/reschool-docker.list
    apt-get update
    if command -v docker >/dev/null; then
      apt-get install -y docker-compose-plugin
    else
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
  fi
fi
command -v python3 >/dev/null || apt-get install -y python3
systemctl enable --now docker
stage 'Устанавливаю Server Advanced'
mkdir -p "$install_dir"
# конфигурацию, ключи и данные уже установленного сервера сохраняем
if [[ -f "$install_dir/docker-compose.yml" ]]; then
  cp "$install_dir/docker-compose.yml" "$work_dir/docker-compose.previous.yml"
fi
tar -xzf "$work_dir/server.tar.gz" -C "$install_dir"
if [[ -f "$work_dir/docker-compose.previous.yml" ]]; then
  cp "$work_dir/docker-compose.previous.yml" "$install_dir/docker-compose.yml"
fi
mkdir -p "$install_dir/secrets" "$install_dir/server_advanced/runtime" "$install_dir/server_advanced/uploads"
python3 - "$work_dir/connection.json" "$install_dir/.env" <<'PY'
import base64
import json
import os
import secrets
import sys
from pathlib import Path

config = json.loads(Path(sys.argv[1]).read_text())
env = Path(sys.argv[2])
if not env.exists():
    values = {
        'DB_HOST': 'db', 'DB_PORT': '5432', 'DB_USER': 'reschool',
        'DB_NAME': 'reschool', 'DB_PASSWORD': secrets.token_urlsafe(32),
        'REDIS_HOST': 'redis', 'REDIS_PORT': '6379',
        'API_TOKEN': secrets.token_urlsafe(32),
        'CF3_ENCRYPTION_KEY': base64.urlsafe_b64encode(os.urandom(32)).decode(),
        'SERVER_PUBLIC_IP': config['host'], 'PUBLIC_BASE_URL': config['serverUrl'],
        'DEBUG_REQUEST_LOG_FULL': 'false', 'ANALYSIS_ENABLED': 'true',
    }
    def quote(value):
        return "'" + value.replace('\\', '\\\\').replace("'", "\\'") + "'"
    env.write_text(''.join(key + '=' + quote(value) + '\n' for key, value in values.items()))
    env.chmod(0o600)
PY
cd "$install_dir"
stage 'Подключаю настройки и обновления сервера'
# при первом запуске и управлении хостом нужен один набор файлов compose
compose_args=(-f docker-compose.yml)
[[ ! -f docker-compose.override.yml ]] || compose_args+=(-f docker-compose.override.yml)
compose_args+=(-f docker-compose.settings.yml)
python3 - <<'UNIT'
from pathlib import Path
root = Path('/opt/reschool')
unit = (root / 'settings_manager/reschool-settings.service').read_text()
files = ['docker-compose.yml']
if (root / 'docker-compose.override.yml').exists():
    files.append('docker-compose.override.yml')
files.append('docker-compose.settings.yml')
lines = unit.splitlines()
for i, line in enumerate(lines):
    if line.startswith('ExecStart='):
        lines[i] = 'ExecStart=/usr/bin/python3 /opt/reschool/settings_manager/manager.py --root /opt/reschool --socket-dir /run/reschool-settings ' + ' '.join('--compose-file ' + name for name in files)
Path('/etc/systemd/system/reschool-settings.service').write_text('\n'.join(lines) + '\n')
UNIT
systemctl daemon-reload
systemctl enable reschool-settings
systemctl restart reschool-settings
stage 'Запускаю базу данных и сервер'
docker compose "${compose_args[@]}" up --build -d
stage 'Проверяю готовность HTTPS'
python3 - <<'PY'
import json
import time
import urllib.request

for _ in range(120):
    try:
        with urllib.request.urlopen('http://127.0.0.1:20001/config', timeout=3) as response:
            if json.load(response).get('cloudProtocolVersion') == 2:
                break
    except Exception:
        pass
    time.sleep(2)
else:
    print('RESCHOOL_ERROR:Сервер не запустился, проверьте docker compose logs в /opt/reschool')
    raise SystemExit(1)
PY
docker compose "${compose_args[@]}" exec -T server_advanced python -c '
import base64, json
from server_advanced.config import API_TOKEN
from server_advanced.tls_manager import tls_status
print("RESCHOOL_RESULT:" + base64.b64encode(json.dumps({"apiToken": API_TOKEN, "pin": tls_status()["tlsPin"]}).encode()).decode())
'
stage 'Сервер готов'
