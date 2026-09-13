from cryptography.fernet import Fernet

from .config import ENCRYPTION_KEY
from .logging_utils import log


# состояние шифрования
_encryption_key = ENCRYPTION_KEY
_cipher = None


def init_encryption():
    """подготавливаем шифрование сохранённых паролей"""
    global _cipher, _encryption_key

    if _cipher:
        return True

    if not _encryption_key:
        log("[Encryption] ENCRYPTION_KEY is not configured. Set a persistent Fernet key before starting.")
        return False

    try:
        # ключ должен быть в байтах
        key = _encryption_key.encode() if isinstance(_encryption_key, str) else _encryption_key
        _cipher = Fernet(key)
        log("[Encryption] Initialized successfully")
        return True
    except Exception as e:
        log(f"[Encryption] Initialization error: {e}")
        return False


def encrypt_password(password):
    """шифруем пароль перед сохранением"""
    if not _cipher:
        init_encryption()
    if not _cipher:
        return None
    try:
        return _cipher.encrypt(password.encode()).decode()
    except Exception as e:
        log(f"[Encryption] Error: {e}")
        return None


def decrypt_password(encrypted_password):
    """расшифровываем сохранённый пароль"""
    if not _cipher:
        init_encryption()
    if not _cipher:
        return None
    try:
        return _cipher.decrypt(encrypted_password.encode()).decode()
    except Exception as e:
        log(f"[Encryption] Decryption error: {e}")
        return None
