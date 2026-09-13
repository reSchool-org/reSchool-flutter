#!/usr/bin/env python3
"""служба хоста доступна через закрытый unix сокет; поля формы разрешены явно, команды и пути фиксируются при запуске"""
import argparse
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import socketserver
import subprocess
import tempfile
import threading
import time
import urllib.request

from schema import FIELDS, validate
from updater import ServerUpdater

KEY_LINE = re.compile(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=')


def atomic_write(path, data, mode=0o600):
    path = Path(path)
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as file:
            os.fchmod(file.fileno(), mode)
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def patch_env(raw, changes):
    """сохраняем нетронутые байты, комментарии и порядок; кавычки защищают значения от подстановок"""
    text = raw.decode('utf-8')
    lines = text.splitlines(keepends=True)
    found = set()
    result = []
    for line in lines:
        match = KEY_LINE.match(line)
        key = match.group(1) if match else None
        if key in changes:
            if key not in found:
                # compose раскрывает слеши и кавычки в двойных кавычках, экранированный доллар остаётся буквальным
                value = json.dumps(changes[key], ensure_ascii=False).replace("$", "\\$")
                result.append(f"{key}={value}\n")
                found.add(key)
        else:
            result.append(line)
    for key, value in changes.items():
        if key not in found:
            if result and not result[-1].endswith('\n'):
                result[-1] += '\n'
            value = json.dumps(value, ensure_ascii=False).replace("$", "\\$")
            result.append(f"{key}={value}\n")
    return ''.join(result).encode('utf-8')


class SettingsManager:
    def __init__(self, root, socket_dir, compose_files):
        self.root = Path(root).resolve()
        self.env = self.root / '.env'
        self.socket_dir = Path(socket_dir)
        self.socket_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.socket_dir, 0o700)
        self.backups = self.root / 'backups' / 'settings'
        self.backups.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.backups, 0o700)
        self.state_path = self.backups / 'operation.json'
        self.lock = threading.RLock()
        self.compose = ['docker', 'compose']
        for name in compose_files:
            self.compose += ['-f', str(self.root / name)]
        self.operation = json.loads(self.state_path.read_text()) if self.state_path.exists() else None
        self.config_files = [self.root / name for name in compose_files]
        self.updater = ServerUpdater(self)

    def run(self, args, timeout=30):
        # stderr compose может содержать раскрытые секреты, наружу его не передаём
        result = subprocess.run(args, cwd=self.root, capture_output=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError('Не удалось выполнить проверку или перезапуск сервера')
        return result.stdout

    def config(self):
        return json.loads(self.run(self.compose + ['config', '--format', 'json']))

    def revision(self):
        h = hashlib.sha256(self.env.read_bytes())
        for path in self.config_files:
            h.update(path.read_bytes())
        return h.hexdigest()

    def containers(self):
        ids = self.run(self.compose + ['ps', '-q']).decode().split()
        if not ids:
            raise RuntimeError('Сервер не запущен')
        rows = json.loads(self.run(['docker', 'inspect', *ids]))
        return {r['Config']['Labels']['com.docker.compose.service']: r for r in rows}

    @staticmethod
    def environment(container):
        return dict(item.split('=', 1) for item in container['Config']['Env'] if '=' in item)

    def snapshot(self):
        with self.lock:
            config = self.config()
            rows = self.containers()
            environments = {name: self.environment(row) for name, row in rows.items()}
            raw = self.env.read_text()
            present = {match.group(1) for line in raw.splitlines() if (match := KEY_LINE.match(line))}
            fields = []
            for key in dict.fromkeys([*FIELDS, *sorted(present)]):
                if key in ('ENCRYPTION_KEY', 'CF3_MIN_CHECK_INTERVAL', 'CF3_DEFAULT_CHECK_INTERVAL') and key not in present:
                    continue
                spec = dict(FIELDS.get(key, dict(key=key, label=key, group='other', default='', kind='text', secret=True, hint='', minimum=0, maximum=4096, locked='Служебная настройка установки; изменение через форму пока не поддерживается.')))
                service = 'browser_bridge' if key.startswith('BROWSER_') else 'server_advanced'
                effective = environments.get(service, {})
                desired = config['services'].get(service, {}).get('environment', {})
                value = effective.get(key, str(spec['default']))
                source = 'env' if key in present else ('deployment' if key in effective else 'default')
                # обычный вывод compose смешивает env_file и environment, поэтому читаем конфиг без раскрытия значений
                spec.update(value='' if spec['secret'] else value,
                            configured=bool(value), source=source, present=key in present)
                if service not in rows:
                    spec['locked'] = 'Браузерный сервис не установлен на этом сервере.'
                if key in desired and str(desired[key]).replace('$$', '$') != value:
                    spec['locked'] = 'Файл изменён вне приложения. Сначала примените изменения установки.'
                if '\n' in value or '\r' in value:
                    spec['locked'] = 'Многострочное значение управляется при установке.'
                fields.append(spec)
            # параметр no-env-resolution отделяет явное environment от env_file
            explicit = json.loads(self.run(self.compose + ['config', '--no-env-resolution', '--format', 'json']))
            for spec in fields:
                service = 'browser_bridge' if spec['key'].startswith('BROWSER_') else 'server_advanced'
                env = explicit['services'].get(service, {}).get('environment', {})
                if spec['key'] in env:
                    # compose намеренно связывает BROWSER_SERVER_URL с файлом .env
                    if spec['key'] != 'BROWSER_SERVER_URL':
                        spec['source'] = 'deployment'
                        spec['locked'] = spec['locked'] or 'Значение закреплено в настройках установки Docker.'
            return dict(revision=self.revision(), fields=fields, operation=self.operation,
                        restartRequired=True)

    def set_operation(self, **values):
        with self.lock:
            self.operation = {**(self.operation or {}), **values}
            atomic_write(self.state_path, json.dumps(self.operation, ensure_ascii=False).encode())

    def submit(self, payload):
        with self.lock:
            operation_id = payload.get('operationId', '')
            if not isinstance(operation_id, str) or not re.fullmatch(r'[a-f0-9-]{36}', operation_id):
                raise ValueError('Некорректный номер операции')
            if self.operation and self.operation['id'] == operation_id:
                return self.operation
            if self.operation and self.operation['status'] in ('queued', 'applying', 'rolling_back', 'recovery_required'):
                raise ValueError('Предыдущее изменение ещё применяется')
            if payload.get('revision') != self.revision():
                raise ValueError('Настройки уже изменились. Обновите экран перед сохранением.')
            snapshot = self.snapshot()
            changes = payload.get('changes')
            validate(changes, snapshot['fields'])
            current = {f['key']: f['value'] for f in snapshot['fields'] if not f['secret']}
            proposed = {**current, **changes}
            if int(float(proposed.get('DB_POOL_MIN_SIZE', '1'))) > int(float(proposed.get('DB_POOL_MAX_SIZE', '10'))):
                raise ValueError('Минимум соединений не может превышать максимум')
            for minimum, default in [('MIN_CHECK_INTERVAL', 'DEFAULT_CHECK_INTERVAL'), ('CF3_MIN_CHECK_INTERVAL', 'CF3_DEFAULT_CHECK_INTERVAL')]:
                if minimum in proposed and default in proposed and int(proposed[minimum]) > int(proposed[default]):
                    raise ValueError('Интервал по умолчанию не может быть меньше минимального')
            if proposed.get('BROWSER_ALLOW_INSECURE_SIGNALING') != 'true' and proposed.get('BROWSER_SIGNAL_URL', '').startswith('ws:'):
                raise ValueError('Для браузерного подключения укажите адрес wss://')
            before = self.env.read_bytes()
            backup = self.backups / (operation_id + '.env')
            atomic_write(backup, before)
            # копию для отката сохраняем до изменения .env, чтобы пережить перезапуск; в json задачи секретов нет
            self.operation = None
            self.set_operation(id=operation_id, status='queued', message='Создана резервная копия. Применяем настройки…', keys=list(changes), startedAt=int(time.time()), backup=backup.name, proposedHash=hashlib.sha256(patch_env(before, changes)).hexdigest())
            thread = threading.Thread(target=self.apply, args=(before, changes), daemon=True)
            thread.start()
            return dict(self.operation)

    def recreate(self):
        available = self.config()['services']
        services = [name for name in ('server_advanced', 'browser_bridge') if name in available]
        self.run(self.compose + ['up', '-d', '--no-build', '--no-deps', '--force-recreate', *services], timeout=150)

    def healthy(self, expected=None):
        deadline = time.monotonic() + 150
        while time.monotonic() < deadline:
            try:
                rows = self.containers()
                app = rows['server_advanced']
                env = self.environment(app)
                request = urllib.request.Request('http://127.0.0.1:20001/server-settings/health', headers={'X-API-Token': env['API_TOKEN']})
                with urllib.request.urlopen(request, timeout=5) as response:
                    ready = json.load(response).get('ok') is True
                ready = ready and app['State']['Running'] and app['RestartCount'] == 0
                bridge = rows.get('browser_bridge')
                ready = ready and (bridge is None or bridge['State']['Running'] and bridge['RestartCount'] == 0)
                if expected:
                    for key, value in expected.items():
                        target = rows.get('browser_bridge') if key.startswith('BROWSER_') else app
                        ready = ready and target is not None and self.environment(target).get(key) == value
                if ready:
                    return True
            except Exception:
                pass
            time.sleep(3)
        return False

    def rollback(self):
        backup = self.backups / self.operation['backup']
        if self.operation.get('proposedHash') and self.env.read_bytes() != backup.read_bytes() and hashlib.sha256(self.env.read_bytes()).hexdigest() != self.operation['proposedHash']:
            raise RuntimeError('Файл изменён вне приложения во время применения')
        self.set_operation(status='rolling_back', message='Возвращаем предыдущие настройки…')
        atomic_write(self.env, backup.read_bytes())
        self.recreate()
        if not self.healthy():
            raise RuntimeError('Проверка восстановления не завершена')
        self.set_operation(status='rolled_back', message='Изменения не прошли проверку. Прежние настройки восстановлены.')

    def apply(self, before, changes):
        # даём запросу завершиться до пересоздания flask
        time.sleep(2)
        try:
            with self.lock:
                if self.env.read_bytes() != before:
                    self.set_operation(status='cancelled', message='Файл изменился вне приложения. Сохранение отменено; обновите экран.')
                    return
                self.set_operation(status='applying', message='Перезапускаем сервер и проверяем соединение…')
                atomic_write(self.env, patch_env(before, changes))
                self.config()  # ошибки синтаксиса и подстановок вызывают откат до запуска
            self.recreate()
            # ждём немного, чтобы обнаружить быстрый цикл падений до сообщения об успехе
            time.sleep(5)
            if not self.healthy(changes):
                raise RuntimeError('Проверка сервера не пройдена')
            with self.lock:
                self.set_operation(status='applied', message='Настройки применены. Сервер работает.', finishedAt=int(time.time()))
        except Exception:
            try:
                self.rollback()
            except Exception:
                self.set_operation(status='recovery_required', message='Восстановление не завершено. Резервная копия сохранена; требуется проверка администратором.')

    def recover(self):
        if self.operation and self.operation['status'] in ('queued', 'applying', 'rolling_back'):
            try:
                if self.operation.get('kind') == 'update':
                    self.updater.recover()
                else:
                    self.rollback()
            except Exception:
                self.set_operation(status='recovery_required', message='Восстановление прерванной операции требует проверки сервера.')


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def handle_request(self):
        try:
            if self.command == 'GET' and self.path == '/settings':
                result = self.server.manager.snapshot()
            elif self.command == 'GET' and self.path == '/operation':
                result = {'operation': self.server.manager.operation}
            elif self.command == 'GET' and self.path in ('/updates', '/updates/check'):
                result = self.server.manager.updater.snapshot(check=self.path.endswith('/check'))
            elif self.command == 'POST' and self.path in ('/settings', '/updates'):
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 65536:
                    raise ValueError('Слишком большой запрос')
                payload = json.loads(self.rfile.read(length))
                if not isinstance(payload, dict):
                    raise ValueError('Некорректный запрос')
                result = {'operation': (self.server.manager.updater.submit(payload) if self.path == '/updates' else self.server.manager.submit(payload))}
            else:
                self.send_error(404)
                return
            status = 200
        except ValueError as error:
            result, status = {'error': str(error)}, 409
        except Exception:
            result, status = {'error': 'Сервис настройки временно недоступен'}, 503
        content = json.dumps(result, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(content)))
        self.end_headers()
        self.wfile.write(content)

    do_GET = handle_request
    do_POST = handle_request


class UnixServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', required=True)
    parser.add_argument('--socket-dir', required=True)
    parser.add_argument('--compose-file', action='append', required=True)
    args = parser.parse_args()
    manager = SettingsManager(args.root, args.socket_dir, args.compose_file)
    manager.recover()
    socket_path = Path(args.socket_dir) / 'settings.sock'
    socket_path.unlink(missing_ok=True)
    with UnixServer(str(socket_path), Handler) as server:
        os.chmod(socket_path, 0o600)
        server.manager = manager
        server.serve_forever()
