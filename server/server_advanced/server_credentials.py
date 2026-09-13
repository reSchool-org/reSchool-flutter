"""привязываем кеш школьной сессии к данным входа серверного аккаунта"""
import hashlib
import hmac
import json
import os
from pathlib import Path
import tempfile


def _signature(username, password, encryption_key):
    # hmac позволяет не хранить в метке пароль или хеш для его подбора
    return hmac.new((encryption_key or '').encode(),
                    ((username or '') + '\0' + (password or '')).encode(),
                    hashlib.sha256).hexdigest()


def _write(path, value):
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.server-credentials-')
    try:
        with os.fdopen(fd, 'w') as file:
            os.fchmod(file.fileno(), 0o600)
            json.dump(value, file)
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def credentials_changed(runtime_dir, username, password, encryption_key):
    signature = _signature(username, password, encryption_key)
    path = Path(runtime_dir) / 'server-credentials.json'
    try:
        previous = json.loads(path.read_text())
    except FileNotFoundError:
        # при первом запуске старой установки принимаем её сохранённую сессию
        previous = {'signature': signature, 'pending': False}
    changed = previous.get('pending', False) or not hmac.compare_digest(previous['signature'], signature)
    # после неудачного входа требуем новый вход даже при откате, login мог сохранить сессию до проверки состояния
    _write(path, {**previous, 'pending': changed})
    return changed


def accept_credentials(runtime_dir, username, password, encryption_key):
    _write(Path(runtime_dir) / 'server-credentials.json',
           {'signature': _signature(username, password, encryption_key), 'pending': False})
