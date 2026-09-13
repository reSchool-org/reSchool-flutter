import hashlib
import random
import string

from .devices import DEVICES
from .config import ALLOWED_EXTENSIONS


def generate_random_string(length):
    """создаём случайную строку из букв и цифр"""
    chars = string.ascii_letters + string.digits
    return ''.join(random.choice(chars) for _ in range(length))


def get_random_device_model():
    """выбираем модель устройства для имитации мобильного клиента"""
    return random.choice(DEVICES)


def sha256_hash(text):
    """считаем хеш текста алгоритмом sha256"""
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def allowed_file(filename):
    """пропускаем только разрешённые расширения файлов"""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS
