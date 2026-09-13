"""права пользователей и общий бот сервера"""

from .database import get_db_connection
from .encryption import decrypt_password


MEMBER_PATHS = {
    '/auth-check', '/cloud/status', '/cloud/leave',
    '/classmate-leave',
    '/custom-homework/create', '/custom-homework/list',
    '/custom-homework/update', '/custom-homework/delete',
    '/notification-history', '/homework/analysis', '/homework/summary',
}
MONITOR_PATHS = {
    '/cloud/session',
    '/cloud/telegram', '/cloud/telegram/test', '/update-interval',
    '/get-account-status', '/retry-session', '/update-password',
}


def member_path_allowed(path, monitoring=False):
    clean = path.rstrip('/')
    return ((clean in MEMBER_PATHS and not (monitoring and clean in {'/classmate-leave'})) or
            (monitoring and clean in MONITOR_PATHS) or
            clean.startswith('/custom-homework/file/') or
            clean.startswith('/homework/analysis/image/') or
            clean.startswith('/homework/analysis/attachment/'))


def server_bot():
    conn = get_db_connection()
    if not conn:
        return None
    cursor = conn.cursor(dictionary=True)
    try:
        cursor.execute('SELECT * FROM cloud_server_bot WHERE id = 1')
        row = cursor.fetchone()
        if row:
            row['token'] = decrypt_password(row.pop('token_encrypted'))
        return row
    finally:
        cursor.close()
        conn.close()


def account_primary(registration_id):
    """стабильная регистрация для команд Telegram; права проверяет вызывающий код"""
    conn = get_db_connection()
    if not conn:
        raise RuntimeError('Database unavailable')
    try:
        row = conn.execute('SELECT cf3_account_primary(%s)', (registration_id,)).fetchone()
        return (row[0] if row else None) or registration_id
    finally:
        conn.close()


def apply_server_bot(registration_id, info):
    if not info:
        return info
    bot = server_bot()
    if bot:
        info['telegram_bot_token'] = bot['token']
        if info.get('cloud_role') == 'user':
            info['telegram_group_enabled'] = False
            info['telegram_group_chat_id'] = None
            info['chat_forward_map'] = '{}'
    return info


_active_server_bot = None


def restart_server_bot():
    global _active_server_bot
    from .telegram_bot import start_telegram_bot, stop_telegram_bot
    if _active_server_bot:
        stop_telegram_bot(_active_server_bot)
        _active_server_bot = None
    bot = server_bot()
    if not bot or not bot['token']:
        return
    owner = bot.get('owner_registration_id')
    if owner:
        owner = account_primary(owner)
    user_id = ''
    if owner:
        conn = get_db_connection()
        if not conn:
            return
        cursor = conn.cursor()
        try:
            cursor.execute('SELECT telegram_user_id FROM cf3_registrations WHERE id = %s', (owner,))
            row = cursor.fetchone()
            if row:
                user_id = row[0]
        finally:
            cursor.close()
            conn.close()
    # один опрос на весь токен, пользователям нужны только личные доставки
    _active_server_bot = owner or '__server__'
    start_telegram_bot(_active_server_bot, bot['token'], user_id or '0')
