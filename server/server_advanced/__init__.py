# пакет server_advanced
# модульный flask сервер для приложения reSchool

from .app import app, run_server, initialize_server

__all__ = ['app', 'run_server', 'initialize_server']
