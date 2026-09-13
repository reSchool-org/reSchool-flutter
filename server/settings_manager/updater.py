"""обновление выполняет хост, клиент не может задать адрес скачивания или команду"""
import hashlib
import io
import json
from pathlib import PurePosixPath
import re
import tarfile
import threading
import time
import urllib.request

REPOSITORY = 'reSchool-org/reSchool-flutter'
ACTIVE = ('queued', 'applying', 'rolling_back')
MAX_ARCHIVE = 32 * 1024 * 1024


def version(value):
    if not isinstance(value, str) or not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', value):
        raise ValueError('Некорректная версия сервера')
    return tuple(map(int, value.split('.')))


def download(url, limit):
    request = urllib.request.Request(url, headers={'User-Agent': 'reSchool-Server-Updater', 'Accept': 'application/vnd.github+json' if url.startswith('https://api.github.com/') else 'application/octet-stream'})
    with urllib.request.urlopen(request, timeout=10) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError('Файл обновления слишком большой')
    return data


def code_file(name):
    path = PurePosixPath(name)
    if path.is_absolute() or '..' in path.parts or str(path) != name:
        return False
    if name in ('VERSION', 'Dockerfile', 'requirements.txt', 'entrypoint.sh', '.dockerignore'):
        return True
    if path.parts[0] == 'server_advanced':
        return not {'runtime', 'uploads', '__pycache__'}.intersection(path.parts) and path.suffix in ('.py', '.sql', '.svg', '.js')
    if path.parts[0] == 'browser_transport':
        return len(path.parts) == 2 and (path.suffix == '.py' or path.name in ('Dockerfile', 'requirements.txt'))
    return False


def unpack(data, expected):
    files = {}
    total = 0
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        for member in archive:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not member.isfile():
                raise ValueError('Небезопасный архив обновления')
            total += member.size
            if total > MAX_ARCHIVE * 4:
                raise ValueError('Распакованное обновление слишком большое')
            # релиз не заменяет настройки развёртывания, секреты и службу хоста
            if not code_file(member.name):
                continue
            if member.name in files:
                raise ValueError('Повторяющийся файл обновления')
            files[member.name] = archive.extractfile(member).read()
    required = {'VERSION', 'Dockerfile', 'requirements.txt', 'entrypoint.sh', 'server_advanced/__main__.py'}
    if not required.issubset(files) or files['VERSION'].decode().strip() != expected:
        raise ValueError('Архив не соответствует выбранной версии')
    return files


class ServerUpdater:
    def __init__(self, manager):
        self.manager = manager
        self.release = None
        self.checked_at = None

    def current(self):
        try:
            value = (self.manager.root / 'VERSION').read_text().strip()
            version(value)
            return value
        except (OSError, ValueError):
            return None

    def snapshot(self, check=False):
        if check:
            try:
                releases = json.loads(download(f'https://api.github.com/repos/{REPOSITORY}/releases?per_page=100', 2 * 1024 * 1024))
                candidates = []
                for release in releases:
                    tag = release.get('tag_name', '')
                    if release.get('draft') or release.get('prerelease') or not re.fullmatch(r'server-v\d+\.\d+\.\d+', tag):
                        continue
                    value = tag.removeprefix('server-v')
                    assets = {a['name'] for a in release.get('assets', [])}
                    if {'reschool-server.tar.gz', 'reschool-server.tar.gz.sha256'} <= assets:
                        candidates.append((version(value), value))
                self.release = max(candidates)[1] if candidates else None
                self.checked_at = int(time.time())
            except Exception as error:
                raise ValueError('Не удалось проверить обновления на GitHub. Повторите позже.') from error
        current = self.current()
        return dict(currentVersion=current, latestVersion=self.release,
                    updateAvailable=bool(current and self.release and version(self.release) > version(current)),
                    checkedAt=self.checked_at,
                    operation=self.manager.operation if (self.manager.operation or {}).get('kind') == 'update' else None,
                    supported=current is not None)

    def submit(self, payload):
        m = self.manager
        with m.lock:
            operation_id = payload.get('operationId')
            if not isinstance(operation_id, str) or not re.fullmatch(r'[a-f0-9-]{36}', operation_id):
                raise ValueError('Некорректный номер операции')
            if m.operation and m.operation['id'] == operation_id:
                if m.operation.get('kind') != 'update':
                    raise ValueError('Номер операции уже используется')
                return dict(m.operation)
            if m.operation and m.operation['status'] in (*ACTIVE, 'recovery_required'):
                raise ValueError('Предыдущая операция ещё не завершена')
            state = self.snapshot()
            if not state['supported']:
                raise ValueError('Сначала установите версию сервера с поддержкой обновлений через SSH')
            if not state['updateAvailable'] or payload.get('version') != self.release:
                raise ValueError('Сначала проверьте доступную версию обновления')
            m.operation = None
            m.set_operation(id=operation_id, kind='update', status='queued', version=self.release,
                            previousVersion=state['currentVersion'], startedAt=int(time.time()),
                            message='Скачиваем обновление reSchool Server…')
            threading.Thread(target=self.apply, args=(self.release,), daemon=True).start()
            return dict(m.operation)

    def restore(self):
        from manager import atomic_write
        m = self.manager
        m.set_operation(status='rolling_back', message='Возвращаем предыдущую версию сервера…')
        backup = m.backups / m.operation['id']
        manifest = json.loads((backup / 'files.json').read_text())
        for name, existed in manifest.items():
            target = m.root / name
            if existed:
                atomic_write(target, (backup / name).read_bytes(), 0o755 if name == 'entrypoint.sh' else 0o644)
            else:
                target.unlink(missing_ok=True)
        for item in m.operation['images']:
            m.run(['docker', 'image', 'tag', item['id'], item['tag']])
        m.recreate()
        if not m.healthy():
            raise RuntimeError('Восстановленная версия не прошла проверку')
        m.set_operation(status='rolled_back', message='Обновление не прошло проверку. Предыдущая версия восстановлена.', finishedAt=int(time.time()))

    def recover(self):
        m = self.manager
        if m.operation.get('prepared'):
            self.restore()
        else:
            m.set_operation(status='cancelled', message='Обновление прервано до установки. Проверьте обновления ещё раз.')

    def apply(self, selected):
        from manager import atomic_write
        m = self.manager
        time.sleep(2)
        try:
            base = f'https://github.com/{REPOSITORY}/releases/download/server-v{selected}/reschool-server.tar.gz'
            checksum = download(base + '.sha256', 256).decode().split()[0]
            if not re.fullmatch(r'[a-f0-9]{64}', checksum):
                raise ValueError('Некорректная контрольная сумма')
            data = download(base, MAX_ARCHIVE)
            if hashlib.sha256(data).hexdigest() != checksum:
                raise ValueError('Контрольная сумма обновления не совпала')
            files = unpack(data, selected)
            backup = m.backups / m.operation['id']
            backup.mkdir(mode=0o700)
            rows = m.containers()
            images = [dict(id=row['Image'], tag=row['Config']['Image']) for name, row in rows.items()
                      if name in ('server_advanced', 'browser_bridge')]
            if not any(name == 'server_advanced' for name in rows):
                raise ValueError('Сервер не запущен')
            # копируем все заменяемые файлы до первой записи; данные, файлы compose, подключения и пины остаются на месте
            manifest = {}
            for name in files:
                target = m.root / name
                if any(p.is_symlink() for p in (target, *target.parents)):
                    raise ValueError('Файлы установки содержат символические ссылки')
                manifest[name] = target.exists()
                if target.exists():
                    saved = backup / name
                    saved.parent.mkdir(parents=True, exist_ok=True)
                    atomic_write(saved, target.read_bytes())
            atomic_write(backup / 'files.json', json.dumps(manifest).encode())
            # снимок базы сохраняем для ручного отката при несовместимой миграции
            m.set_operation(status='applying', message='Создаём резервную копию базы данных…')
            database = m.run(m.compose + ['exec', '-T', 'db', 'sh', '-c', 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc'], timeout=300)
            atomic_write(backup / 'database.dump', database)
            m.set_operation(prepared=True, images=images, message='Собираем новую версию сервера…')
            for name, content in files.items():
                if name == 'VERSION':
                    continue
                target = m.root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                atomic_write(target, content, 0o755 if name == 'entrypoint.sh' else 0o644)
            services = [name for name in ('server_advanced', 'browser_bridge') if name in rows]
            m.run(m.compose + ['build', *services], timeout=1200)
            m.set_operation(message='Перезапускаем сервер и проверяем соединение…')
            m.recreate()
            time.sleep(5)
            if not m.healthy():
                raise RuntimeError('Новая версия не прошла проверку запуска')
            atomic_write(m.root / 'VERSION', files['VERSION'], 0o644)
            m.set_operation(status='applied', message=f'reSchool Server обновлён до {selected}. Сервер работает.', finishedAt=int(time.time()))
        except Exception:
            if m.operation.get('prepared'):
                try:
                    self.restore()
                except Exception:
                    m.set_operation(status='recovery_required', message='Не удалось восстановить запуск сервера. Сохранены прежняя версия и копия базы; требуется проверка по SSH.')
            else:
                m.set_operation(status='failed', message='Не удалось подготовить обновление. Текущая версия сохранена. Проверьте доступ к GitHub и свободное место, затем повторите.')
