from flask import Blueprint

from . import verification
from . import homework
from . import notifications
from . import proxy
from . import textbooks
from . import cloud
from . import bell_time
from . import server_settings


def register_routes(app):
    """подключаем обработчики маршрутов к приложению flask"""
    app.register_blueprint(verification.bp)
    app.register_blueprint(homework.bp)
    app.register_blueprint(notifications.bp)
    app.register_blueprint(proxy.bp)
    app.register_blueprint(textbooks.bp)
    app.register_blueprint(cloud.bp)
    app.register_blueprint(bell_time.bp)
    app.register_blueprint(server_settings.bp)
