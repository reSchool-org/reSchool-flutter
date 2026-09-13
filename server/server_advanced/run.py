#!/usr/bin/env python3
"""позволяем запустить сервер напрямую"""

import sys
import os

# добавляем родительский каталог в путь, чтобы импортироваться пакетом
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from server_advanced.app import run_server

if __name__ == '__main__':
    run_server()
