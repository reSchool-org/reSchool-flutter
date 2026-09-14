"""команды и уведомления телеграма используют бота и получателя из настроек аккаунта"""
import threading
import time
import io
import os
import secrets
import string
import json
import requests
from html import escape as html_escape
from contextlib import ExitStack
from types import SimpleNamespace
from .school_dates import school_date, SCHOOL_TIMEZONE
from .notification_links import notification_open_url
from datetime import datetime, timedelta
from urllib.parse import urlsplit
from telebot import TeleBot
from telebot.types import (Message, InlineKeyboardMarkup, InlineKeyboardButton,
                           ReplyParameters, CopyTextButton)

from .config import API_TOKEN, USER_AGENT, get_public_base_url
from .logging_utils import log
from .database import get_db_connection
from .chat_notifications import fetch_threads, ChatSessionExpired
from .encryption import decrypt_password, encrypt_password, init_encryption
from . import telegram_formatting as presentation
from .telegram_delivery import send_card, edit_card
from .telegram_diagnostics import delivery_log, error_details


# живые боты, по одному на регистрацию
_active_bots = {}  # registration_id → экземпляр TeleBot
_bot_threads = {}  # registration_id → поток
_bot_running = {}  # registration_id → крутится ли он
_bot_tokens = {}   # registration_id → токен бота, чтобы один токен не подняли дважды
_activation_codes = {}  # коды активации со сроком действия по регистрации
_activation_codes_lock = threading.Lock()
_pending_topic_detects = {}       # обнаруженные топики со сроком действия по регистрации
_pending_topic_detects_lock = threading.Lock()
_pending_password_changes = {}    # ожидание ввода со сроком действия по регистрации
_pending_password_changes_lock = threading.Lock()
_MAX_ATTACHMENT_DOWNLOAD_BYTES = 50 * 1024 * 1024
SESSION_LOGIN_INSTRUCTIONS = (
    "Откройте reSchool и заново подключите облачные функции/уведомления. "
    "После успешного входа сервер создаст новую сессию и продолжит работу."
)


def _send_text(bot, chat_id, text, **kwargs):
    kwargs.pop('disable_web_page_preview', None)
    return send_card(bot, chat_id, text, **kwargs)


def _reply_text(bot, message, text):
    topic = getattr(message, 'message_thread_id', None)
    if text.startswith(('⏳', 'Отправляю тестовое')):
        bot.send_chat_action(message.chat.id, 'typing', message_thread_id=topic)
        return None
    return send_card(bot, message.chat.id, text, message_thread_id=topic,
                     reply_parameters=ReplyParameters(message.message_id))


def _menu_keyboard():
    markup = InlineKeyboardMarkup()
    markup.row(InlineKeyboardButton('📚 Домашние задания', callback_data='menu:homework', style='primary'),
               InlineKeyboardButton('📝 Оценки', callback_data='menu:grades'))
    markup.row(InlineKeyboardButton('💬 Беседы', callback_data='menu:messages'),
               InlineKeyboardButton('📅 Период', callback_data='menu:period'))
    markup.row(InlineKeyboardButton('⚙️ Статус', callback_data='menu:status'),
               InlineKeyboardButton('Справка', callback_data='menu:help'))
    return markup


def _get_user_session(registration_id: str):
    """вход с паролем требует явного действия, здесь читаем только готовую сессию"""
    conn = get_db_connection()
    if not conn:
        return None, None, None, "Ошибка подключения к базе данных"

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT username, selected_period_id, selected_period_name,
                   session_invalid, session_invalid_reason
            FROM cf3_registrations WHERE id = %s
        """, (registration_id,))
        reg = cursor.fetchone()
        cursor.close()
        conn.close()

        if not reg:
            return None, None, None, "Регистрация не найдена"

        if reg.get('session_invalid'):
            reason = reg.get('session_invalid_reason') or 'session_expired'
            log(f"[Telegram] Access blocked for invalid session {registration_id}: {reason}")
            return None, None, reg, SESSION_LOGIN_INSTRUCTIONS

        from .keep_alive import get_session, mark_account_session_invalid
        cookies = get_session(registration_id)
        if not cookies:
            mark_account_session_invalid(registration_id, reg['username'], 'session_missing', notify=True)
            return None, None, reg, SESSION_LOGIN_INSTRUCTIONS
        return reg['username'], cookies, reg, None

    except Exception as e:
        log(f"[Telegram] Error getting credentials: {type(e).__name__}")
        return None, None, None, f"Ошибка: {type(e).__name__}"


def _get_user_data_for_telegram(registration_id: str):
    """читаем задания, оценки и сообщения зарегистрированного пользователя"""
    # импорт тут, иначе получится циклический
    from .routes.notifications import fetch_data_with_session
    from .keep_alive import mark_account_session_invalid

    username, cookies, _, error = _get_user_session(registration_id)
    if error:
        return None, None, None, None, error

    # тянем данные из eSchool
    homework, grades, messages, first_name, expired, _ = fetch_data_with_session(cookies, username)
    if expired:
        mark_account_session_invalid(registration_id, username, 'session_expired', notify=True)
        return None, None, None, None, SESSION_LOGIN_INSTRUCTIONS

    if homework is None:
        return None, None, None, None, "Не удалось получить данные. Попробуйте позже."

    return homework, grades, messages, first_name, None


def _get_periods_for_telegram(registration_id: str):
    """получаем доступные периоды зарегистрированного пользователя"""
    from .routes.notifications import get_periods_for_user

    username, cookies, reg, error = _get_user_session(registration_id)
    if error:
        return None, None, error

    periods, _, error = get_periods_for_user(cookies, registration_id)
    if error:
        return None, None, error

    # ищем текущий период либо тот, что выбрали
    selected_period_id = reg.get('selected_period_id') if reg else None

    return periods, selected_period_id, None


def _get_grades_for_period_telegram(registration_id: str, period_id: int = None):
    """читаем оценки за выбранный период"""
    from .routes.notifications import get_grades_for_period, get_periods_for_user

    username, cookies, reg, error = _get_user_session(registration_id)
    if error:
        return None, None, error

    # если период не задали, берём выбранный
    if period_id is None:
        period_id = reg.get('selected_period_id') if reg else None

    # если и его нет, ищем текущий
    if period_id is None:
        periods, _, error = get_periods_for_user(cookies, registration_id)
        if error:
            return None, None, error
        if periods:
            # ищем текущий
            for p in periods:
                if p.get('isCurrent'):
                    period_id = p.get('id')
                    break
            # на совсем крайний случай берём первый
            if period_id is None and periods:
                period_id = periods[0].get('id')

    if period_id is None:
        return None, None, "Не удалось определить период"

    grades, period_name, _, error = get_grades_for_period(cookies, period_id, registration_id)
    if error:
        return None, None, error

    return grades, period_name, None


def _save_selected_period(registration_id: str, period_id: int, period_name: str):
    """сохраняем выбранный период в базе"""
    conn = get_db_connection()
    if not conn:
        return False

    try:
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE cf3_registrations
            SET selected_period_id = %s, selected_period_name = %s
            WHERE id = %s
        """, (period_id, period_name, registration_id))
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        log(f"[Telegram] Error saving period: {type(e).__name__}")
        return False


def _login_deep_link() -> str | None:
    """кнопки телеграма не принимают reschool://, поэтому открываем приложение через страницу https"""
    public_base_url = get_public_base_url()
    if not public_base_url or not API_TOKEN:
        return None

    from urllib.parse import quote
    server = quote(public_base_url, safe="")
    token = quote(API_TOKEN, safe="")
    return f"https://reschool.app/open?type=link-device&server={server}&token={token}&interval=10"


def send_session_invalid_message(registration_id: str, username: str = None, reason: str = None) -> bool:
    """при недействительной сессии предлагаем действия в уведомлении телеграма"""
    conn = get_db_connection()
    if not conn:
        return False

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT COALESCE(cf3_account_primary(id), id) = id AS telegram_delivery_primary,
                   cloud_role, username, telegram_enabled, telegram_bot_token, telegram_user_id, session_invalid_at
            FROM cf3_registrations WHERE id = %s
        """, (registration_id,))
        reg = cursor.fetchone()
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"[Telegram] Error loading session-invalid target: {type(e).__name__}")
        return False

    from .cloud_access import apply_server_bot
    reg = apply_server_bot(registration_id, reg)
    if not reg or not reg.get('telegram_enabled') or not reg.get('telegram_delivery_primary', True):
        return False
    if not reg.get('telegram_bot_token') or not reg.get('telegram_user_id'):
        return False

    account = username or reg.get('username') or registration_id
    try:
        card = presentation.Card('🔑 Нужно войти в eSchool').fact('Аккаунт', account)
        card.text('Подключение истекло. Проверка домашних заданий, оценок и сообщений приостановлена до повторного входа.')
        markup = InlineKeyboardMarkup()
        markup.add(InlineKeyboardButton('Войти снова', callback_data=f'session_login:{registration_id}', style='primary'))
        markup.add(InlineKeyboardButton('Остановить проверку', callback_data=f'session_stop:{registration_id}', style='danger'))
        if reg.get('cloud_role') == 'user':
            card.text('Обновите пароль во вкладке облачных функций reSchool.')
            markup = None
        ok = send_telegram_message(
            reg['telegram_bot_token'], reg['telegram_user_id'], '🔑 Нужно войти в eSchool',
            '\n\n'.join(plain for _, plain in card.parts),
            notification_type='session_invalid',
            notification_data={'id': registration_id[:8], 'revision': str(reg.get('session_invalid_at') or '')},
            reply_markup_data=markup.to_dict() if markup else None, durable=True)
        log(f"[Telegram] Session invalid notice queued={ok} for {registration_id}")
        return ok
    except Exception as e:
        log(f"[Telegram] Error sending session-invalid notice: {type(e).__name__}")
        return False


def _handle_session_stop_action(bot: TeleBot, call, registration_id: str):
    """останавливаем мониторинг после подтверждения в телеграме"""
    if registration_id not in call.data:
        bot.answer_callback_query(call.id, "Неверная кнопка")
        return

    conn = get_db_connection()
    if conn:
        try:
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE cf3_registrations
                SET session_invalid = TRUE,
                    session_invalid_reason = 'stopped_by_user',
                    session_invalid_at = COALESCE(session_invalid_at, NOW()),
                    last_check_at = NOW()
                WHERE id = %s
            """, (registration_id,))
            conn.commit()
            cursor.close()
            conn.close()
        except Exception as e:
            log(f"[Telegram] Error stopping monitoring from callback: {type(e).__name__}")

    try:
        from .database import delete_user_session
        delete_user_session(registration_id)
    except Exception as e:
        log(f"[Telegram] Error deleting stopped session: {type(e).__name__}")

    bot.answer_callback_query(call.id, "Мониторинг остановлен")
    try:
        bot.edit_message_reply_markup(
            chat_id=call.message.chat.id,
            message_id=call.message.message_id,
            reply_markup=None,
        )
    except Exception:
        pass


def _handle_session_login_action(bot: TeleBot, call, registration_id: str):
    """пробуем восстановить сессию из уведомления телеграма"""
    bot.answer_callback_query(call.id, "⏳ Подключаюсь...")
    try:
        bot.edit_message_reply_markup(
            chat_id=call.message.chat.id,
            message_id=call.message.message_id,
            reply_markup=None,
        )
    except Exception as e:
        log(f"[Telegram] Error removing session-login buttons: {type(e).__name__}")
    _perform_retry_session(bot, call.message.chat.id, registration_id)


_WEEKDAYS_RU = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс']
_MONTHS_RU = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
              'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря']


def _date_display(dt: datetime) -> str:
    return f"{_WEEKDAYS_RU[dt.weekday()]}, {dt.day} {_MONTHS_RU[dt.month - 1]}"


def _filter_homework_by_date(homework_list: list, date_str: str) -> list:
    """оставляем только задания на выбранную дату урока"""
    result = []
    for hw in homework_list:
        date_ms = hw.get('date')
        if not date_ms:
            continue
        if school_date(date_ms) == date_str:
            result.append(hw)
    return result


def _format_homework_for_date(homework_list: list, target_date: datetime):
    return presentation.homework(
        _filter_homework_by_date(homework_list, target_date.strftime('%Y-%m-%d')), target_date)


def _homework_keyboard(target_date: datetime, page=0, total=1) -> InlineKeyboardMarkup:
    prev_str = (target_date - timedelta(days=1)).strftime("%Y-%m-%d")
    next_str = (target_date + timedelta(days=1)).strftime("%Y-%m-%d")
    markup = InlineKeyboardMarkup()
    markup.row(
        InlineKeyboardButton("← Назад", callback_data=f"hw_date:{prev_str}"),
        InlineKeyboardButton("Вперёд →", callback_data=f"hw_date:{next_str}"),
    )
    if total > 1:
        date_str = target_date.strftime('%Y-%m-%d')
        markup.row(
            InlineKeyboardButton('‹', callback_data=f'hw_page:{date_str}:{max(0, page - 1)}'),
            InlineKeyboardButton(f'{page + 1} / {total}', callback_data=f'hw_page:{date_str}:{page}'),
            InlineKeyboardButton('›', callback_data=f'hw_page:{date_str}:{min(total - 1, page + 1)}'),
        )
    today = datetime.now(SCHOOL_TIMEZONE).strftime('%Y-%m-%d')
    markup.row(InlineKeyboardButton('Сегодня', callback_data=f'hw_date:{today}', style='primary'),
               InlineKeyboardButton('Оценки', callback_data='menu:grades'))
    return markup


def _homework_page(homework_list, target_date, page=0):
    card = _format_homework_for_date(homework_list, target_date)
    pages = card.pages()
    page = min(max(0, page), len(pages) - 1)
    rich, plain = pages[page]
    selected = presentation.Card(card.title + (f' · {page + 1}/{len(pages)}' if len(pages) > 1 else ''))
    selected.add(rich.partition('\n\n')[2], plain.partition('\n\n')[2])
    return selected, _homework_keyboard(target_date, page, len(pages))


def _period_keyboard(periods, selected_id=None):
    markup = InlineKeyboardMarkup()
    for period in sorted(periods, key=lambda p: p.get('date1') or 0, reverse=True)[:24]:
        period_id = period.get('id')
        if not isinstance(period_id, int) or period_id < 1:
            continue
        name = presentation.label(period.get('name') or 'Период', 40)
        year = presentation.label(period.get('schoolYear') or '', 20)
        markup.add(InlineKeyboardButton(f'{name} · {year}'.rstrip(' ·'),
                    callback_data=f'period:{period_id}', style='primary' if period_id == selected_id else None))
    return markup


def _owner_callback(call, user_id):
    return (getattr(call, 'message', None) is not None
            and str(call.message.chat.id) == str(user_id)
            and call.message.chat.type == 'private'
            and str(call.from_user.id) == str(user_id))


def _resolve_bot_registration(message, registration_id, owner_user_id, bot_token):
    """личная команда общего бота должна использовать только аккаунт отправителя"""
    chat = getattr(message, 'chat', None)
    sender = getattr(message, 'from_user', None)
    if (chat is None or sender is None or chat.type != 'private'
            or str(chat.id) != str(sender.id)):
        return None
    if str(sender.id) == str(owner_user_id):
        return registration_id if registration_id != '__server__' else None

    conn = get_db_connection()
    if not conn:
        raise RuntimeError('Database unavailable for Telegram authorization')
    cursor = None
    try:
        cursor = conn.cursor(dictionary=True)
        # отозванные подключения и регистрации другого бота не дают доступа
        cursor.execute('''SELECT r.id, b.token_encrypted
            FROM cf3_registrations r
            JOIN classmate_registrations m ON m.monitoring_registration_id = r.id
            CROSS JOIN cloud_server_bot b
            WHERE r.telegram_user_id = %s AND r.cloud_role = 'user' AND b.id = 1''',
            (str(sender.id),))
        rows = cursor.fetchall()
        if len(rows) != 1:
            delivery_log(log, 'bot_binding_denied', chat_id=chat.id,
                         reason='ambiguous_account' if rows else 'no_linked_account')
            return None
        if decrypt_password(rows[0]['token_encrypted']) != bot_token:
            delivery_log(log, 'bot_binding_denied', chat_id=chat.id, reason='different_bot')
            return None
        return rows[0]['id']
    finally:
        if cursor is not None:
            cursor.close()
        conn.close()


def _format_homework_message(homework_list: list, limit: int = 10):
    return presentation.homework(homework_list[:limit], datetime.now())


def _format_grades_message(grades_list: list, period_name: str = None, limit: int = 20):
    return presentation.grades(grades_list, period_name, limit)


def _format_periods_message(periods: list, selected_id: int = None):
    return presentation.periods(periods, selected_id)


def _format_messages_message(messages_list: list, limit: int = 5):
    return presentation.messages(messages_list, limit)


def _messages_page(messages, page=0):
    size = 5
    total = max(1, (len(messages) + size - 1) // size)
    page = max(0, min(page, total - 1))
    card = presentation.messages(messages, size, page * size)
    markup = InlineKeyboardMarkup()
    navigation = []
    if page > 0:
        navigation.append(InlineKeyboardButton('← Назад', callback_data=f'messages_page:{page - 1}'))
    if page + 1 < total:
        navigation.append(InlineKeyboardButton('Далее →', callback_data=f'messages_page:{page + 1}'))
    if navigation:
        markup.row(*navigation)
    markup.row(InlineKeyboardButton('Обновить', callback_data=f'messages_page:{page}'),
               InlineKeyboardButton('Главное меню', callback_data='menu:start'))
    return card, markup


def _get_messages_for_telegram(registration_id):
    # просмотр бесед не должен запускать вход или отменять ручную остановку аккаунта
    username, cookies, _, error = _get_user_session(registration_id)
    if error:
        return None, error
    try:
        headers = {
            'Accept': 'application/json, text/plain, */*',
            'User-Agent': USER_AGENT,
            'Origin': 'https://app.eschool.center',
            'Referer': 'https://app.eschool.center/',
        }
        return fetch_threads(cookies, headers), None
    except ChatSessionExpired:
        from .keep_alive import mark_account_session_invalid
        mark_account_session_invalid(registration_id, username, 'session_expired', notify=True)
        return None, SESSION_LOGIN_INSTRUCTIONS
    except Exception as error:
        log(f'[Telegram] Conversation list unavailable: {type(error).__name__}')
        return None, 'Не удалось загрузить список бесед. Попробуйте ещё раз.'


def _button_markup(deep_link_url):
    """кнопка со ссылкой. Схему кроме http, https и tg телеграм не принимает
    и отбивает всё сообщение целиком, поэтому такую ссылку молча пропускаем"""
    if not deep_link_url or not str(deep_link_url).startswith(("http://", "https://", "tg://")):
        return None
    markup = InlineKeyboardMarkup()
    markup.add(InlineKeyboardButton("Открыть в reSchool", url=str(deep_link_url), style="primary"))
    return markup


def _download_attachment(url, attachment_headers, attachment_cookies, name=None):
    """скачать вложение самим: часть ссылок eSchool отдаёт только по своей сессии"""
    parts = urlsplit(url) if isinstance(url, str) else None
    if (not parts or parts.scheme != "https"
            or parts.hostname != "app.eschool.center"
            or parts.port not in (None, 443)
            or parts.username is not None or parts.password is not None
            or "\\" in url or any(ord(char) <= 32 for char in url)):
        raise ValueError("Authenticated attachment origin is not allowed")

    with requests.get(
        url,
        headers=attachment_headers or {},
        cookies=attachment_cookies or {},
        timeout=30,
        allow_redirects=False,
        stream=True,
    ) as resp:
        file_buffer = io.BytesIO()
        if resp.status_code != 200:
            raise ValueError(f"download failed: {resp.status_code}")
        if int(resp.headers.get("Content-Length", "0")) > _MAX_ATTACHMENT_DOWNLOAD_BYTES:
            raise ValueError("Attachment exceeds download limit")
        # считаем и распакованные байты тоже: заявленная длина бывает пустой или врёт
        for chunk in resp.iter_content(chunk_size=64 * 1024):
            if file_buffer.tell() + len(chunk) > _MAX_ATTACHMENT_DOWNLOAD_BYTES:
                raise ValueError("Attachment exceeds download limit")
            file_buffer.write(chunk)
        if not file_buffer.tell():
            raise ValueError("Empty attachment")
        file_buffer.seek(0)
        file_buffer.name = str(name or "attachment")
        return file_buffer


def _rich_attachments(items, stack, headers, cookies, delivery_id=None):
    media, files, blocks, prepared, failed = [], {}, [], [], []
    photos = []
    for index, item in enumerate(items[:20]):
        name = presentation.label(item.get('name') or 'Вложение', 80)
        kind = 'photo' if item.get('isImage') else 'document'
        media_id = f'media{index}'
        try:
            path = item.get('path') or item.get('local_path')
            url = item.get('url')
            if path and os.path.isfile(path):
                if os.path.getsize(path) > _MAX_ATTACHMENT_DOWNLOAD_BYTES:
                    raise ValueError('Attachment exceeds upload limit')
                content = stack.enter_context(open(path, 'rb'))
            elif url and (headers or cookies):
                content = stack.enter_context(_download_attachment(url, headers, cookies, name))
            elif isinstance(url, str):
                parts = urlsplit(url)
                if (parts.scheme not in ('http', 'https') or not parts.hostname
                        or parts.username or parts.password or any(ord(c) <= 32 for c in url)):
                    raise ValueError('Invalid media URL')
                content = url
            else:
                raise ValueError('Attachment has no source')
            if isinstance(content, str):
                source = content
            else:
                files[media_id] = (name, content)
                source = 'attach://' + media_id
            media.append({'id': media_id, 'media': {'type': kind, 'media': source}})
            element = f'<img src="tg://photo?id={media_id}"/>' if kind == 'photo' else (
                f'<tg-document src="tg://document?id={media_id}"></tg-document>')
            block = f'<figure>{element}<figcaption>{html_escape(name)}</figcaption></figure>'
            if kind == 'photo':
                photos.append(block)
            else:
                blocks.append(block)
            prepared.append(item)
        except Exception as error:
            failed.append(name)
            delivery_log(log, 'attachment_preparation_failed', delivery_id=delivery_id,
                         attachment_index=index, **error_details(error))
    if len(photos) > 1:
        blocks.insert(0, '<tg-collage>' + ''.join(photos) + '</tg-collage>')
    elif photos:
        blocks.insert(0, photos[0])
    return media, files, blocks, prepared, failed


def _send_remaining_attachments(bot, user_id, items, headers, cookies, message_thread_id, delivery_id=None,
                                progress=None, checkpoint=None, indexes=None, raise_errors=False):
    sent = 0
    progress = progress if progress is not None else {}
    completed = progress.setdefault('attachments_done', [])
    for index, attachment in enumerate(items):
        original_index = indexes[index] if indexes is not None else index
        if original_index in completed:
            sent += 1
            continue
        local_path = attachment.get('path') or attachment.get('local_path')
        url = attachment.get('url')
        name = presentation.label(attachment.get('name') or 'Вложение', 240)
        kwargs = {'chat_id': user_id, 'caption': name}
        if message_thread_id is not None:
            kwargs['message_thread_id'] = message_thread_id
        method = bot.send_photo if attachment.get('isImage') else bot.send_document
        argument = 'photo' if attachment.get('isImage') else 'document'
        try:
            if local_path and os.path.isfile(local_path):
                with open(local_path, 'rb') as stream:
                    result = method(**{argument: stream}, **kwargs)
            elif url and (headers or cookies):
                with _download_attachment(url, headers, cookies, name) as stream:
                    result = method(**{argument: stream}, **kwargs)
            elif url:
                result = method(**{argument: url}, **kwargs)
            else:
                if raise_errors:
                    raise FileNotFoundError('Attachment source unavailable')
                continue
            sent += 1
            delivery_log(log, 'attachment_delivered', delivery_id=delivery_id,
                         chat_id=str(user_id), topic_id=message_thread_id,
                         attachment_index=index, message_id=result.message_id)
            completed.append(original_index)
            progress.setdefault('attachment_message_ids', []).append(result.message_id)
            if checkpoint:
                checkpoint(progress)
        except Exception as error:
            delivery_log(log, 'attachment_delivery_failed', delivery_id=delivery_id,
                         chat_id=str(user_id), topic_id=message_thread_id,
                         attachment_index=index, **error_details(error, (bot.token,)))
            if raise_errors:
                raise
    return sent


def send_telegram_message(
    bot_token: str,
    user_id: str,
    title: str,
    body: str,
    attachments: list = None,
    attachment_headers: dict = None,
    attachment_cookies: dict = None,
    message_thread_id: int = None,
    deep_link_url: str = None,
    notification_type: str = None,
    notification_data: dict = None,
    analysis_data: dict = None,
    require_complete: bool = False,
    reply_markup_data=None,
    durable: bool = False,
    progress=None,
    checkpoint=None,
    raise_errors=False,
    delivery_id=None,
) -> bool:
    if deep_link_url is None:
        deep_link_url = notification_open_url(notification_type, notification_data)
    if durable:
        from .telegram_outbox import enqueue_telegram_message
        return enqueue_telegram_message(
            bot_token, user_id, title, body, attachments=attachments,
            attachment_headers=attachment_headers, attachment_cookies=attachment_cookies,
            message_thread_id=message_thread_id, deep_link_url=deep_link_url,
            notification_type=notification_type, notification_data=notification_data,
            analysis_data=analysis_data, require_complete=True, reply_markup_data=reply_markup_data)
    delivery_id = delivery_id or secrets.token_hex(8)
    progress = progress if progress is not None else {}
    resuming_card = bool(progress.get('card_complete'))
    data = notification_data if isinstance(notification_data, dict) else {}
    context = {'delivery_id': delivery_id, 'chat_id': str(user_id), 'topic_id': message_thread_id,
               'notification_type': notification_type, 'source_id': data.get('id'),
               'homework_id': data.get('id') if notification_type == 'homework' else None,
               'analysis_id': data.get('analysisId')}
    if not bot_token or not user_id:
        delivery_log(log, 'notification_skipped', **context, reason='missing_bot_or_chat')
        return False
    started = time.monotonic()
    stage = 'prepare'
    try:
        bot = TeleBot(bot_token)
        card = presentation.notification(title, body, notification_type, notification_data, analysis_data)
        items = [item for item in (attachments or []) if isinstance(item, dict)]
        delivery_log(log, 'notification_started', **context, attachment_count=len(items),
                     local_count=sum(bool(i.get('path') or i.get('local_path')) for i in items),
                     url_count=sum(bool(i.get('url')) for i in items))
        with ExitStack() as stack:
            media, files, blocks, prepared, failed = _rich_attachments(
                [] if progress.get('card_complete') else items, stack, attachment_headers, attachment_cookies, delivery_id)
            if failed and raise_errors:
                raise OSError('Attachment preparation failed; inspect attachment_preparation_failed events')
            if blocks:
                # медиа держим одним блоком в конце, чтобы все ссылки и загрузки попали на одну страницу
                card.parts.insert(-1, ('\n\n'.join(blocks), '📎 ' + ', '.join(
                    presentation.label(item.get('name') or 'Вложение', 80) for item in prepared)))
            if failed:
                card.text('📎 Не удалось загрузить: ' + ', '.join(failed) + '. Вложения доступны в reSchool.')
            stage = 'send_card'
            delivery = send_card(bot, user_id, card, message_thread_id=message_thread_id,
                                 reply_markup=InlineKeyboardMarkup.de_json(reply_markup_data) if reply_markup_data else _button_markup(deep_link_url),
                                 media=media, files=files,
                                 delivery_id=delivery_id, progress=progress, checkpoint=checkpoint)
        if delivery.media_sent:
            done = progress.setdefault('attachments_done', [])
            for index in range(min(20, len(items))):
                if index not in done:
                    done.append(index)
            if checkpoint:
                checkpoint(progress)
        remaining_indices = [index for index in range(len(items))
                             if index not in progress.get('attachments_done', [])
                             and (raise_errors or resuming_card or index >= 20 or items[index] in prepared)]
        remaining = [items[index] for index in remaining_indices]
        stage = 'send_remaining_attachments'
        sent_remaining = _send_remaining_attachments(
            bot, user_id, remaining, attachment_headers, attachment_cookies,
            message_thread_id, delivery_id, progress, checkpoint, remaining_indices,
            raise_errors) if remaining else 0
        complete = not failed and sent_remaining == len(remaining)
        delivery_log(log, 'notification_delivered' if complete else 'notification_partial',
                     **context, message_ids=delivery.message_ids, rich=delivery.rich,
                     media_sent=delivery.media_sent, failed_attachments=len(failed) + len(remaining) - sent_remaining,
                     elapsed_ms=round((time.monotonic() - started) * 1000))
        # старым вызовам достаточно доставить текст, а очереди своих дз
        # нужно ещё подтверждение всех вложений
        return complete or not require_complete
    except Exception as error:
        delivery_log(log, 'notification_failed', **context, stage=stage,
                     elapsed_ms=round((time.monotonic() - started) * 1000),
                     **error_details(error, (bot_token,)))
        if raise_errors:
            raise
        return False


def _handle_start_command(message: Message, registration_id: str):
    """отвечаем на команду запуска бота"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return

        bot = TeleBot(bot_token)
        _send_text(bot, message.chat.id, presentation.welcome(), reply_markup=_menu_keyboard())
    except Exception as e:
        log(f"[Telegram] Error handling /start command: {type(e).__name__}")


def _perform_retry_session(bot: TeleBot, chat_id, registration_id: str):
    """восстанавливаем вход по сохранённым данным и сообщаем результат в чат"""
    from .routes.notifications import login_and_get_data
    from .keep_alive import update_session

    conn = get_db_connection()
    if not conn:
        _send_text(bot, chat_id, "❌ Ошибка подключения к базе данных")
        return

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT username, password_encrypted FROM cf3_registrations WHERE id = %s
        """, (registration_id,))
        reg = cursor.fetchone()
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"[Telegram] retry DB error: {type(e).__name__}")
        _send_text(bot, chat_id, "❌ Ошибка базы данных")
        return

    if not reg:
        _send_text(bot, chat_id, "❌ Регистрация не найдена")
        return

    init_encryption()
    password = decrypt_password(reg['password_encrypted'])
    if not password:
        _send_text(bot, chat_id, "❌ Не удалось расшифровать пароль")
        return

    username = reg['username']
    hw, grades, notifications_list, name, cookies, prs_id = login_and_get_data(username, password)

    if hw is None:
        _send_text(bot,
            chat_id,
            "❌ Не удалось войти в eSchool. Возможно, пароль был изменён.\n\n"
            "Откройте reSchool → Настройки → Облачные функции и используйте кнопку «Изменить пароль»."
        )
        return

    conn2 = get_db_connection()
    if not conn2:
        _send_text(bot, chat_id, "❌ Не удалось сохранить подключение. Попробуйте снова.")
        return
    try:
        cursor2 = conn2.cursor()
        cursor2.execute("""
            UPDATE cf3_registrations
            SET session_invalid = FALSE,
                session_invalid_reason = NULL,
                session_invalid_at = NULL
            WHERE id = %s
        """, (registration_id,))
        conn2.commit()
        cursor2.close()
    except Exception as e:
        log(f"[Telegram] retry DB update error: {type(e).__name__}")
        _send_text(bot, chat_id, "❌ Не удалось сохранить подключение. Попробуйте снова.")
        return
    finally:
        conn2.close()

    update_session(registration_id, cookies)
    log(f"[Telegram] Session restored via /retry for {registration_id} ({username})")
    _send_text(bot, chat_id, "✅ Подключение восстановлено! Мониторинг возобновлён.")


def _handle_changepassword_command(message: Message, registration_id: str):
    """просим новый школьный пароль"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return
        bot = TeleBot(bot_token)
        with _pending_password_changes_lock:
            _pending_password_changes[registration_id] = {
                'expires_at': datetime.now() + timedelta(minutes=3),
            }
        _reply_text(bot,
            message,
            "🔑 Введите новый пароль eSchool следующим сообщением.\n\n"
            "⚠️ Пароль будет передан серверу и зашифрован. Ожидание 3 минуты.\n"
            "Для отмены отправьте /cancel"
        )
    except Exception as e:
        log(f"[Telegram] Error handling /passwd command: {type(e).__name__}")


def _handle_cancel_command(message: Message, registration_id: str):
    """сбрасываем ожидание пользовательского ввода"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return
        bot = TeleBot(bot_token)
        cancelled = False
        with _pending_password_changes_lock:
            if registration_id in _pending_password_changes:
                del _pending_password_changes[registration_id]
                cancelled = True
        _reply_text(bot, message, "✅ Отменено." if cancelled else "Нечего отменять.")
    except Exception as e:
        log(f"[Telegram] Error handling /cancel command: {type(e).__name__}")


def _handle_retry_command(message: Message, registration_id: str):
    """повторяем вход с сохранёнными данными"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return
        bot = TeleBot(bot_token)
        _reply_text(bot, message, "⏳ Пробую переподключиться к eSchool...")
        _perform_retry_session(bot, message.chat.id, registration_id)
    except Exception as e:
        log(f"[Telegram] Error handling /retry command: {type(e).__name__}")


def _handle_status_command(message: Message, registration_id: str):
    """показываем состояние мониторинга"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return

        bot = TeleBot(bot_token)

        conn = get_db_connection()
        if conn:
            try:
                cursor = conn.cursor(dictionary=True)
                cursor.execute("""
                    SELECT username, check_interval_minutes, check_interval_max_minutes, last_check_at, telegram_enabled,
                           telegram_group_enabled, telegram_group_title, telegram_topic_map,
                           session_invalid, session_invalid_reason, session_invalid_at
                    FROM cf3_registrations WHERE id = %s
                """, (registration_id,))
                reg = cursor.fetchone()
                cursor.close()
                conn.close()

                if reg:
                    topic_count = 0
                    try:
                        parsed_map = json.loads(reg.get('telegram_topic_map') or '{}')
                        if isinstance(parsed_map, dict):
                            topic_count = len(parsed_map)
                    except Exception:
                        topic_count = 0

                    is_invalid = bool(reg.get('session_invalid'))

                    card = presentation.Card('⚠️ Проверка приостановлена' if is_invalid else '✅ Проверка включена')
                    card.fact('Аккаунт', reg['username'])
                    markup = _menu_keyboard()
                    if is_invalid:
                        card.text('Подключение к eSchool истекло. Попробуйте войти снова или обновите пароль в приложении.')
                        if reg.get('session_invalid_at'):
                            card.add('Приостановлено · ' + presentation.moment(reg['session_invalid_at']), str(reg['session_invalid_at']))
                        markup = InlineKeyboardMarkup()
                        markup.add(InlineKeyboardButton('Попробовать снова', callback_data=f'session_retry:{registration_id}', style='primary'))
                        login_url = _login_deep_link()
                        if login_url:
                            markup.add(InlineKeyboardButton('Открыть reSchool', url=login_url))
                    else:
                        card.table(('Настройка', 'Состояние'), [
                            ('Проверка',
                             f'Случайно, {reg["check_interval_minutes"]}-{reg["check_interval_max_minutes"]} мин'
                             if reg.get('check_interval_max_minutes') else f'Каждые {reg["check_interval_minutes"]} мин'),
                            ('Telegram', 'Включён' if reg['telegram_enabled'] else 'Выключен'),
                            ('Группа', reg.get('telegram_group_title') if reg.get('telegram_group_enabled') else 'Не подключена'),
                            ('Настроено тем', topic_count),
                        ])
                        card.add('Последняя проверка · ' + presentation.moment(reg['last_check_at']),
                                 'Последняя проверка: ' + str(reg['last_check_at'] or 'Ещё не было'))
                    _send_text(bot, message.chat.id, card.footer(), reply_markup=markup)
                    return
            except Exception as e:
                log(f"[Telegram] Error getting status: {type(e).__name__}")

        _send_text(bot, message.chat.id, "Не удалось получить статус. Попробуйте позже.")
    except Exception as e:
        log(f"[Telegram] Error handling /status command: {type(e).__name__}")


def _handle_help_command(message: Message, registration_id: str):
    """показываем подсказку по командам бота"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return

        bot = TeleBot(bot_token)
        _send_text(bot, message.chat.id, presentation.welcome(help_page=True), reply_markup=_menu_keyboard())
    except Exception as e:
        log(f"[Telegram] Error handling /help command: {type(e).__name__}")


def _handle_gen_command(message: Message, registration_id: str):
    """код привязки группы создаём только в личной переписке"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return

        bot = TeleBot(bot_token)
        code = _create_group_activation_code(registration_id, ttl_minutes=15)
        card = presentation.Card('🔗 Подключение группы')
        card.text('Код действует 15 минут.').add(
            f'<pre>/activate {html_escape(code)}</pre>', f'/activate {code}')
        card.text('1. Добавьте бота в группу класса.\n2. Отправьте в группе команду с кодом.\n3. В личном чате откройте /l и настройте темы через /t.')
        card.text('Домашние задания и уведомления об оценках поступают в настроенные темы. Значения оценок остаются в личном чате. Пересылка бесед включается отдельно в приложении.')
        markup = InlineKeyboardMarkup()
        markup.add(InlineKeyboardButton('Скопировать команду', copy_text=CopyTextButton('/activate ' + code), style='primary'))
        _send_text(bot, message.chat.id, card, reply_markup=markup)
    except Exception as e:
        log(f"[Telegram] Error handling /gen command: {type(e).__name__}")


def _handle_activate_command(message: Message, registration_id: str, owner_user_id: str):
    """подключаем доставку в группу по одноразовому коду"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return

        bot = TeleBot(bot_token)
        sender_id = str(message.from_user.id) if message.from_user and message.from_user.id is not None else ""

        # активировать можно только в группе или супергруппе,
        # и в группе отвечаем исключительно владельцу
        if message.chat.type not in ('group', 'supergroup'):
            if str(message.chat.id) == str(owner_user_id):
                _send_text(bot, message.chat.id, "Команду /activate нужно отправлять в группе.")
            return
        if sender_id != str(owner_user_id):
            # остальных участников группы просто не замечаем
            return

        parts = (message.text or "").split(maxsplit=1)
        if len(parts) < 2 or not parts[1].strip():
            _send_text(bot, owner_user_id, "❌ Укажите код: /activate ABCD1234")
            return

        ok, error = _consume_group_activation_code(registration_id, parts[1].strip())
        if not ok:
            _send_text(bot, owner_user_id, f"❌ {error}")
            return

        group_id = str(message.chat.id)
        group_title = message.chat.title or "Группа"
        if not _save_group_chat_for_registration(registration_id, group_id, group_title):
            _send_text(bot, owner_user_id, "❌ Не удалось привязать группу. Попробуйте позже.")
            return

        # отвечаем только в личке, в группе молчим
        _send_text(bot,
            owner_user_id,
            f"✅ Группа «{group_title}» подключена для уведомлений.\n"
            "В группу идут только ДЗ и уведомления о новых оценках (без значения)."
        )
    except Exception as e:
        log(f"[Telegram] Error handling /activate command: {type(e).__name__}")


def send_group_connected_notice(registration_id, group_chat_id, group_title, *, connection=None):
    """с переданным соединением подтверждение владельцу ждёт фиксации настроек"""
    from .notification_delivery import get_telegram_info
    from .telegram_outbox import enqueue_telegram_message
    info = get_telegram_info(registration_id) or {}
    return enqueue_telegram_message(
        info.get('telegram_bot_token'), info.get('telegram_user_id'),
        f'✅ Группа «{group_title or group_chat_id}» подключена для уведомлений.',
        'В группу идут только ДЗ и уведомления о новых оценках (без значения).',
        notification_type='group_connected',
        notification_data={'id': registration_id, 'groupChatId': str(group_chat_id),
                           'revision': secrets.token_hex(16)},
        require_complete=True, connection=connection)


def _handle_list_subjects_command(message: Message, registration_id: str):
    """предметы с идентификаторами показываем в личной переписке"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return
        bot = TeleBot(bot_token)

        from .routes.notifications import get_subjects_for_user
        username, cookies, _, credentials_error = _get_user_session(registration_id)
        if credentials_error:
            _send_text(bot, message.chat.id, f"❌ {credentials_error}")
            return

        subjects, error = get_subjects_for_user(cookies, registration_id)
        if error:
            _send_text(bot, message.chat.id, f"❌ {error}")
            return

        catalog = []
        for item in subjects or []:
            sid = str(item.get('id') or '').strip()
            sname = str(item.get('name') or '').strip()
            if sid and sname:
                catalog.append((sid, sname))

        if not catalog:
            _send_text(bot,
                message.chat.id,
                "Не удалось получить список предметов с ID. Попробуйте позже."
            )
            return

        card = presentation.Card('📚 Предметы и темы').table(('Предмет', 'ID'), [(name, sid) for sid, name in catalog])
        card.text('Привязать предмет к теме группы: /t ID_ПРЕДМЕТА ID_ТЕМЫ')
        _send_text(bot, message.chat.id, card)
    except Exception as e:
        log(f"[Telegram] Error handling /l command: {type(e).__name__}")


def _handle_topic_bind_command(message: Message, registration_id: str, owner_user_id: str):
    """привязываем предмет к топику подключённой группы"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return
        bot = TeleBot(bot_token)

        sender_id = str(message.from_user.id) if message.from_user and message.from_user.id is not None else ""
        if message.chat.type not in ('group', 'supergroup'):
            if str(message.chat.id) == str(owner_user_id):
                _send_text(bot, message.chat.id, "Команду /t нужно отправлять в группе.")
            return
        if sender_id != str(owner_user_id):
            return

        parts = (message.text or "").split()
        if len(parts) < 3:
            _send_text(bot, owner_user_id, "❌ Формат: /t <id_предмета> <id_топика>")
            return

        subject_id = parts[1].strip()
        topic_id_raw = parts[2].strip()
        try:
            topic_id = int(topic_id_raw)
        except ValueError:
            _send_text(bot, owner_user_id, "❌ id топика должен быть числом.")
            return

        conn = get_db_connection()
        if not conn:
            _send_text(bot, owner_user_id, "❌ Ошибка БД.")
            return
        try:
            cursor = conn.cursor(dictionary=True)
            cursor.execute("""
                SELECT telegram_group_enabled, telegram_group_chat_id
                FROM cf3_registrations WHERE id = %s
            """, (registration_id,))
            reg = cursor.fetchone()
            cursor.close()
            conn.close()
        except Exception:
            reg = None
        if not reg or not reg.get('telegram_group_enabled') or str(reg.get('telegram_group_chat_id') or '') != str(message.chat.id):
            _send_text(bot, owner_user_id, "❌ Сначала привяжите эту группу через /activate <код>.")
            return

        topic_map = _load_topic_map(registration_id)
        topic_map[str(subject_id)] = topic_id
        if not _save_topic_map(registration_id, topic_map):
            _send_text(bot, owner_user_id, "❌ Не удалось сохранить настройку топика.")
            return

        _send_text(bot,
            owner_user_id,
            presentation.Card('✅ Тема настроена').fact('Предмет', subject_id).fact('Тема', topic_id),

        )
    except Exception as e:
        log(f"[Telegram] Error handling /t command: {type(e).__name__}")


def _parse_date_arg(arg: str) -> datetime | None:
    """принимаем дату с точками или в формате iso, год можно опустить"""
    arg = arg.strip()
    now = datetime.now(SCHOOL_TIMEZONE)
    for fmt in ("%d.%m.%Y", "%d.%m.%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(arg, fmt)
        except ValueError:
            pass
    # если пришло только число и месяц, год считаем текущим
    try:
        return datetime.strptime(f"{arg}.{now.year}", "%d.%m.%Y")
    except ValueError:
        pass
    return None


def _handle_homework_command(message: Message, registration_id: str):
    """показываем задания на сегодня или выбранную дату с переходами между днями"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return

        bot = TeleBot(bot_token)

        # дата в аргументе необязательна, понимаем и 04.03, и полный формат с годом
        parts = message.text.split(maxsplit=1)
        target_date = None
        if len(parts) > 1:
            target_date = _parse_date_arg(parts[1])
            if target_date is None:
                _reply_text(bot, message, "❌ Неверный формат даты. Используйте: ДД.ММ, ДД.ММ.ГГГГ или ГГГГ-ММ-ДД")
                return

        if target_date is None:
            target_date = datetime.now(SCHOOL_TIMEZONE)

        _reply_text(bot, message, "⏳ Загружаю домашние задания...")

        homework, _, _, _, error = _get_user_data_for_telegram(registration_id)
        if error:
            _send_text(bot, message.chat.id, f"❌ {error}")
            return

        card, markup = _homework_page(homework, target_date)
        _send_text(bot, message.chat.id, card, reply_markup=markup)

    except Exception as e:
        log(f"[Telegram] Error handling /homework command: {type(e).__name__}")


def _handle_grades_command(message: Message, registration_id: str):
    """показываем последние оценки"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return

        bot = TeleBot(bot_token)
        _reply_text(bot, message, "⏳ Загружаю оценки за период...")

        grades, period_name, error = _get_grades_for_period_telegram(registration_id)

        if error:
            _send_text(bot, message.chat.id, f"❌ {error}")
            return

        response_text = _format_grades_message(grades, period_name)
        _send_text(bot, message.chat.id, response_text)

    except Exception as e:
        log(f"[Telegram] Error handling /grades command: {type(e).__name__}")


def _handle_period_command(message: Message, registration_id: str):
    """показываем или меняем период оценок"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return

        bot = TeleBot(bot_token)

        # мог прийти id периода
        parts = message.text.split()
        if len(parts) > 1:
            # значит пользователь хочет конкретный период
            try:
                period_id = int(parts[1])
            except ValueError:
                _reply_text(bot, message, "❌ Неверный формат. Используйте: /period [номер]")
                return

            _reply_text(bot, message, "⏳ Устанавливаю период...")

            # тянем периоды, чтобы проверить id и узнать название
            periods, _, error = _get_periods_for_telegram(registration_id)
            if error:
                _send_text(bot, message.chat.id, f"❌ {error}")
                return

            # ищем период по id
            period_name = None
            school_year = None
            for p in periods:
                if p.get('id') == period_id:
                    period_name = p.get('name', f'Период {period_id}')
                    school_year = p.get('schoolYear')
                    break

            if not period_name:
                _send_text(bot, message.chat.id, f"❌ Период с ID {period_id} не найден. Используйте /period для списка периодов.")
                return

            # к названию периода дописываем учебный год
            display_name = f"{period_name} ({school_year})" if school_year else period_name

            # запоминаем выбор
            if _save_selected_period(registration_id, period_id, display_name):
                _send_text(bot,
                    message.chat.id,
                    presentation.Card('✅ Период выбран').text(display_name).text('Откройте /grades, чтобы посмотреть оценки.'),
                )
            else:
                _send_text(bot, message.chat.id, "❌ Не удалось сохранить период")

        else:
            # показываем, что вообще есть
            _reply_text(bot, message, "⏳ Загружаю список периодов...")

            periods, selected_id, error = _get_periods_for_telegram(registration_id)

            if error:
                _send_text(bot, message.chat.id, f"❌ {error}")
                return

            response_text = _format_periods_message(periods, selected_id)
            _send_text(bot, message.chat.id, response_text, reply_markup=_period_keyboard(periods, selected_id))

    except Exception as e:
        log(f"[Telegram] Error handling /period command: {type(e).__name__}")


def _handle_messages_command(message: Message, registration_id: str):
    """беседы показываем по страницам, чтобы список оставался читаемым на телефоне"""
    try:
        bot_token = _get_bot_token_for_registration(registration_id)
        if not bot_token:
            return

        bot = TeleBot(bot_token)
        _reply_text(bot, message, "⏳ Загружаю сообщения...")

        messages, error = _get_messages_for_telegram(registration_id)

        if error:
            _send_text(bot, message.chat.id, f"❌ {error}")
            return

        card, markup = _messages_page(messages)
        _send_text(bot, message.chat.id, card, reply_markup=markup)

    except Exception as e:
        log(f"[Telegram] Error handling /messages command: {type(e).__name__}")


def _get_bot_token_for_registration(registration_id: str) -> str | None:
    """общий бот хранится отдельно от личных настроек"""
    from .notification_delivery import get_telegram_info
    return (get_telegram_info(registration_id) or {}).get('telegram_bot_token')


def _generate_group_activation_code(length: int = 8) -> str:
    """создаём короткий код активации заглавными буквами"""
    alphabet = string.ascii_uppercase + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def _create_group_activation_code(registration_id: str, ttl_minutes: int = 15) -> str:
    """сохраняем код активации для регистрации"""
    code = _generate_group_activation_code()
    expires_at = datetime.now() + timedelta(minutes=ttl_minutes)
    with _activation_codes_lock:
        _activation_codes[registration_id] = {
            'code': code,
            'expires_at': expires_at,
        }
    return code


def create_group_activation_code(registration_id: str, ttl_minutes: int = 15) -> str:
    """даём обработчикам http доступ к созданию кода активации"""
    from .cloud_access import account_primary
    registration_id = account_primary(registration_id)
    return _create_group_activation_code(registration_id, ttl_minutes)


def _consume_group_activation_code(registration_id: str, code: str) -> tuple[bool, str]:
    """успешная проверка сразу погашает код активации"""
    normalized = (code or "").strip().upper()
    with _activation_codes_lock:
        payload = _activation_codes.get(registration_id)
        if not payload:
            return False, "Код не сгенерирован. Сначала отправьте /gen в личном чате с ботом."
        if payload['expires_at'] < datetime.now():
            _activation_codes.pop(registration_id, None)
            return False, "Код просрочен. Сгенерируйте новый через /gen."
        if payload['code'] != normalized:
            return False, "Неверный код активации."
        _activation_codes.pop(registration_id, None)
    return True, ""


def _save_group_chat_for_registration(registration_id: str, chat_id: str, chat_title: str | None) -> bool:
    """сохраняем группу для доставки уведомлений"""
    conn = get_db_connection()
    if not conn:
        return False

    try:
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE cf3_registrations
            SET telegram_group_enabled = %s,
                telegram_group_chat_id = %s,
                telegram_group_title = %s
            WHERE id = %s
        """, (True, str(chat_id), chat_title or "Группа", registration_id))
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        log(f"[Telegram] Error saving group chat for {registration_id}: {type(e).__name__}")
        return False


def _load_topic_map(registration_id: str) -> dict:
    """читаем привязки предметов к топикам"""
    conn = get_db_connection()
    if not conn:
        return {}

    try:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT telegram_topic_map FROM cf3_registrations WHERE id = %s
        """, (registration_id,))
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        if not row or not row[0]:
            return {}
        parsed = json.loads(row[0])
        if not isinstance(parsed, dict):
            return {}
        result = {}
        for k, v in parsed.items():
            key = str(k)
            try:
                result[key] = int(v)
            except (ValueError, TypeError):
                continue
        return result
    except Exception as e:
        log(f"[Telegram] Error loading topic map for {registration_id}: {type(e).__name__}")
        return {}


def _save_topic_map(registration_id: str, topic_map: dict) -> bool:
    """сохраняем привязки предметов к топикам"""
    conn = get_db_connection()
    if not conn:
        return False

    try:
        payload = json.dumps({str(k): int(v) for k, v in topic_map.items()})
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE cf3_registrations
            SET telegram_topic_map = %s
            WHERE id = %s
        """, (payload, registration_id))
        conn.commit()
        cursor.close()
        conn.close()
        return True
    except Exception as e:
        log(f"[Telegram] Error saving topic map for {registration_id}: {type(e).__name__}")
        return False


def _build_subject_catalog(homework_list: list, grades_list: list) -> list[tuple[str, str]]:
    """сортируем предметы вместе с идентификаторами"""
    catalog = {}

    for item in homework_list or []:
        if not isinstance(item, dict):
            continue
        subject_id = item.get('subjectId')
        subject_name = item.get('subject') or 'Предмет'
        if subject_id is None:
            continue
        catalog[str(subject_id)] = subject_name

    for item in grades_list or []:
        if not isinstance(item, dict):
            continue
        subject_id = item.get('subjectId')
        subject_name = item.get('subject') or 'Предмет'
        if subject_id is None:
            continue
        catalog[str(subject_id)] = subject_name

    items = [(sid, name) for sid, name in catalog.items()]
    items.sort(key=lambda x: x[1].lower())
    return items


def _bot_polling_loop(registration_id: str, bot_token: str, user_id: str):
    """отдельный цикл опроса для каждого бота"""
    global _bot_running

    try:
        bot = TeleBot(bot_token)
        _active_bots[registration_id] = bot
        access_error = object()

        def resolve_message(message, action):
            try:
                target = _resolve_bot_registration(message, registration_id, user_id, bot_token)
            except Exception as error:
                delivery_log(log, 'bot_access_error', chat_id=message.chat.id,
                             action=action, **error_details(error, (bot_token,)))
                return access_error
            delivery_log(log, 'bot_access_allowed' if target else 'bot_access_denied',
                         chat_id=message.chat.id, action=action, registration_id=target)
            return target

        def resolve_callback(call):
            if getattr(call, 'message', None) is None:
                return None
            # сообщение с кнопкой отправил бот, пользователя берём из call.from_user
            message = SimpleNamespace(chat=call.message.chat, from_user=call.from_user)
            target = resolve_message(message, (call.data or '').split(':', 1)[0])
            if target is access_error:
                bot.answer_callback_query(call.id, 'Не удалось проверить доступ. Попробуйте позже.')
                return None
            if not target:
                bot.answer_callback_query(call.id, 'Аккаунт не подключён к этому боту. Проверьте Telegram ID в reSchool.')
            return target

        personal_commands = {
            'passwd': _handle_changepassword_command, 'changepassword': _handle_changepassword_command,
            'cancel': _handle_cancel_command, 'retry': _handle_retry_command,
            'start': _handle_start_command, 'status': _handle_status_command, 'help': _handle_help_command,
            'homework': _handle_homework_command, 'dz': _handle_homework_command,
            'grades': _handle_grades_command, 'marks': _handle_grades_command, 'ocenki': _handle_grades_command,
            'messages': _handle_messages_command, 'msg': _handle_messages_command, 'period': _handle_period_command,
        }

        @bot.message_handler(commands=list(personal_commands))
        def personal_handler(message: Message):
            if message.chat.type != 'private':
                return
            action = message.text.split()[0][1:].split('@', 1)[0].lower()
            target = resolve_message(message, action)
            if target is access_error:
                _send_text(bot, message.chat.id, 'Не удалось проверить доступ. Попробуйте позже.')
            elif target:
                personal_commands[action](message, target)
            else:
                _send_text(bot, message.chat.id, presentation.Card('reSchool').fact('Ваш Telegram ID', str(message.from_user.id)).text('Введите его в reSchool, чтобы подключить аккаунт к боту.'))

        @bot.message_handler(commands=['gen', 'l'])
        def group_settings_handler(message: Message):
            if message.chat.type != 'private':
                return
            if not _owner_callback(SimpleNamespace(message=message, from_user=message.from_user), user_id):
                delivery_log(log, 'bot_access_denied', chat_id=message.chat.id, action='group_settings',
                             reason='owner_required')
                _send_text(bot, message.chat.id, 'Группу настраивает администратор сервера. Личный дневник доступен через /start.')
                return
            action = message.text.split()[0][1:].split('@', 1)[0].lower()
            (_handle_gen_command if action == 'gen' else _handle_list_subjects_command)(message, registration_id)

        @bot.message_handler(commands=['activate'])
        def activate_handler(message: Message):
            _handle_activate_command(message, registration_id, str(user_id))

        @bot.message_handler(commands=['t'])
        def topic_bind_handler(message: Message):
            _handle_topic_bind_command(message, registration_id, str(user_id))

        @bot.callback_query_handler(func=lambda call: (call.data or '').startswith('preview:'))
        def preview_handler(call):
            if resolve_callback(call):
                bot.answer_callback_query(call.id, 'Это тестовая карточка. Настройки не изменены.')

        @bot.callback_query_handler(func=lambda call: (call.data or '').startswith('menu:'))
        def menu_handler(call):
            target_registration_id = resolve_callback(call)
            if not target_registration_id:
                return
            action = call.data.split(':', 1)[1]
            handlers = {
                'start': _handle_start_command,
                'homework': _handle_homework_command, 'grades': _handle_grades_command,
                'messages': _handle_messages_command, 'period': _handle_period_command,
                'status': _handle_status_command, 'help': _handle_help_command,
            }
            if action not in handlers:
                bot.answer_callback_query(call.id, 'Эта кнопка устарела')
                return
            bot.answer_callback_query(call.id)
            message = SimpleNamespace(chat=call.message.chat, from_user=call.from_user,
                                      message_id=call.message.message_id, text='/' + action,
                                      message_thread_id=getattr(call.message, 'message_thread_id', None))
            handlers[action](message, target_registration_id)

        @bot.callback_query_handler(func=lambda call: (call.data or '').startswith('messages_page:'))
        def messages_nav_handler(call):
            target_registration_id = resolve_callback(call)
            if not target_registration_id:
                return
            value = call.data.split(':', 1)[1]
            if not value.isascii() or not value.isdigit() or len(value) > 6:
                bot.answer_callback_query(call.id, 'Неверная страница')
                return
            bot.answer_callback_query(call.id)
            try:
                messages, error = _get_messages_for_telegram(target_registration_id)
                if error:
                    _send_text(bot, call.message.chat.id, f'❌ {error}')
                    return
                card, markup = _messages_page(messages, int(value))
                edit_card(bot, chat_id=call.message.chat.id, message_id=call.message.message_id,
                          content=card, reply_markup=markup)
            except Exception as error:
                log(f'[Telegram] Conversation navigation failed: {type(error).__name__}')

        @bot.callback_query_handler(func=lambda call: (call.data or '').startswith('period:'))
        def period_select_handler(call):
            target_registration_id = resolve_callback(call)
            if not target_registration_id:
                return
            value = call.data.split(':', 1)[1]
            if not value.isascii() or not value.isdigit():
                bot.answer_callback_query(call.id, 'Неверный период')
                return
            bot.answer_callback_query(call.id)
            message = SimpleNamespace(chat=call.message.chat, from_user=call.from_user,
                                      message_id=call.message.message_id, text='/period ' + value,
                                      message_thread_id=getattr(call.message, 'message_thread_id', None))
            _handle_period_command(message, target_registration_id)

        @bot.callback_query_handler(func=lambda call: (call.data or '').startswith(('hw_date:', 'hw_page:')))
        def homework_nav_handler(call):
            target_registration_id = resolve_callback(call)
            if not target_registration_id:
                return
            parts = call.data.split(':')
            try:
                target_date = datetime.strptime(parts[1], '%Y-%m-%d')
                page = int(parts[2]) if len(parts) == 3 else 0
            except (ValueError, IndexError):
                bot.answer_callback_query(call.id, 'Неверная дата')
                return
            bot.answer_callback_query(call.id)
            homework, _, _, _, error = _get_user_data_for_telegram(target_registration_id)
            if error:
                _send_text(bot, call.message.chat.id, 'Не удалось загрузить домашние задания. Попробуйте ещё раз.')
                return
            card, markup = _homework_page(homework, target_date, page)
            try:
                edit_card(bot, chat_id=call.message.chat.id, message_id=call.message.message_id,
                          content=card, reply_markup=markup)
            except Exception as error:
                log(f'[Telegram] Homework navigation failed: {type(error).__name__}')

        @bot.callback_query_handler(func=lambda call: (call.data or '').startswith('session_stop:'))
        def session_stop_handler(call):
            target_registration_id = resolve_callback(call)
            if not target_registration_id:
                return
            callback_registration_id = call.data.split(':', 1)[1]
            if callback_registration_id != target_registration_id:
                delivery_log(log, 'bot_access_denied', chat_id=call.message.chat.id,
                             action='session_stop', reason='different_account')
                bot.answer_callback_query(call.id, "Неверная кнопка")
                return
            _handle_session_stop_action(bot, call, target_registration_id)

        @bot.callback_query_handler(func=lambda call: (call.data or '').startswith('session_login:'))
        def session_login_handler(call):
            target_registration_id = resolve_callback(call)
            if not target_registration_id:
                return
            callback_registration_id = call.data.split(':', 1)[1]
            if callback_registration_id != target_registration_id:
                delivery_log(log, 'bot_access_denied', chat_id=call.message.chat.id,
                             action='session_login', reason='different_account')
                bot.answer_callback_query(call.id, "Неверная кнопка")
                return
            _handle_session_login_action(bot, call, target_registration_id)

        @bot.callback_query_handler(func=lambda call: (call.data or '').startswith('session_retry:'))
        def session_retry_handler(call):
            target_registration_id = resolve_callback(call)
            if not target_registration_id:
                return
            callback_registration_id = call.data.split(':', 1)[1]
            if callback_registration_id != target_registration_id:
                delivery_log(log, 'bot_access_denied', chat_id=call.message.chat.id,
                             action='session_retry', reason='different_account')
                bot.answer_callback_query(call.id, "Неверная кнопка")
                return
            bot.answer_callback_query(call.id, "⏳ Подключаюсь...")
            try:
                bot.edit_message_reply_markup(
                    chat_id=call.message.chat.id,
                    message_id=call.message.message_id,
                    reply_markup=None,
                )
            except Exception:
                pass
            _perform_retry_session(bot, call.message.chat.id, target_registration_id)

        @bot.message_handler(func=lambda m: True)
        def echo_handler(message: Message):
            # ждём смену пароля: следующее сообщение в личке считаем новым паролем
            target_registration_id = None
            if message.chat.type == 'private':
                target_registration_id = resolve_message(message, 'text')
                if target_registration_id is access_error:
                    _send_text(bot, message.chat.id, 'Не удалось проверить доступ. Попробуйте позже.')
                    return
            if (target_registration_id
                    and message.chat.type == 'private'
                    and message.text
                    and not message.text.startswith('/')):
                with _pending_password_changes_lock:
                    entry = _pending_password_changes.get(target_registration_id)
                    if entry:
                        if datetime.now() > entry['expires_at']:
                            del _pending_password_changes[target_registration_id]
                            _reply_text(bot, message, "⏰ Время ожидания истекло. Отправьте /passwd снова.")
                            return
                        del _pending_password_changes[target_registration_id]

                if entry and datetime.now() <= entry['expires_at']:
                    new_pw = message.text.strip()
                    _reply_text(bot, message, "⏳ Проверяю пароль...")
                    from .routes.notifications import login_and_get_data
                    from .keep_alive import update_session

                    conn_pw = get_db_connection()
                    username_pw = None
                    if conn_pw:
                        try:
                            cur_pw = conn_pw.cursor(dictionary=True)
                            cur_pw.execute("SELECT username FROM cf3_registrations WHERE id = %s", (target_registration_id,))
                            row_pw = cur_pw.fetchone()
                            cur_pw.close()
                            conn_pw.close()
                            if row_pw:
                                username_pw = row_pw['username']
                        except Exception as e:
                            log(f"[Telegram] passwd DB error: {type(e).__name__}")

                    if not username_pw:
                        _send_text(bot, message.chat.id, "❌ Регистрация не найдена")
                        return

                    hw_pw, _, _, _, cookies_pw, _ = login_and_get_data(username_pw, new_pw)
                    if hw_pw is None:
                        _send_text(bot, message.chat.id, "❌ Неверный пароль. Попробуйте снова: /passwd")
                        return

                    init_encryption()
                    encrypted_pw = encrypt_password(new_pw)
                    if not encrypted_pw:
                        _send_text(bot, message.chat.id, "❌ Ошибка шифрования. Обратитесь к администратору.")
                        return

                    conn_upd = get_db_connection()
                    if not conn_upd:
                        _send_text(bot, message.chat.id, "❌ Не удалось сохранить пароль. Попробуйте снова: /passwd")
                        return
                    try:
                        cur_upd = conn_upd.cursor()
                        cur_upd.execute("""
                            UPDATE cf3_registrations
                            SET password_encrypted = %s,
                                session_invalid = FALSE,
                                session_invalid_reason = NULL,
                                session_invalid_at = NULL
                            WHERE id = %s
                        """, (encrypted_pw, target_registration_id))
                        conn_upd.commit()
                        cur_upd.close()
                    except Exception as e:
                        log(f"[Telegram] passwd update error: {type(e).__name__}")
                        _send_text(bot, message.chat.id, "❌ Не удалось сохранить пароль. Попробуйте снова: /passwd")
                        return
                    finally:
                        conn_upd.close()

                    update_session(target_registration_id, cookies_pw)
                    log(f"[Telegram] Password changed via /passwd for {target_registration_id} ({username_pw})")
                    _send_text(bot, message.chat.id, "✅ Пароль обновлён, мониторинг возобновлён!")
                    return

            # автоопределение топика: пользователь пишет «п» в нужный топик, пока мы ждём
            if (message.text and message.text.strip().lower() == 'п'
                    and message.chat.type in ('group', 'supergroup')
                    and message.message_thread_id is not None):
                with _pending_topic_detects_lock:
                    entry = _pending_topic_detects.get(registration_id)
                pending_active = entry is not None and entry['topic_id'] is None and datetime.now() < entry['expires_at']

                if pending_active:
                    # проверяем, что группа та самая
                    group_matched = False
                    conn = get_db_connection()
                    if conn:
                        try:
                            cursor = conn.cursor(dictionary=True)
                            cursor.execute(
                                "SELECT telegram_group_chat_id FROM cf3_registrations WHERE id = %s",
                                (registration_id,)
                            )
                            reg = cursor.fetchone()
                            cursor.close()
                            conn.close()
                            if reg and str(reg.get('telegram_group_chat_id') or '') == str(message.chat.id):
                                group_matched = True
                        except Exception as e:
                            log(f"[Telegram] Topic detect DB error: {type(e).__name__}")

                    if group_matched:
                        detected = message.message_thread_id
                        with _pending_topic_detects_lock:
                            if registration_id in _pending_topic_detects:
                                _pending_topic_detects[registration_id]['topic_id'] = detected
                        log(f"[Telegram] Topic detected for {registration_id}: {detected}")
                        try:
                            _reply_text(bot, message, f"Топик определён: {detected}")
                        except Exception:
                            pass
                        return

            if target_registration_id:
                _reply_text(bot, message, "Используйте /help для списка команд.")
            else:
                log(f"[Telegram] Ignored message from unauthorized user: {message.chat.id}")

        log(f"[Telegram] Starting bot polling for registration {registration_id}")

        while _bot_running.get(registration_id, False):
            try:
                bot.polling(none_stop=False, interval=1, timeout=20)
            except Exception as e:
                log(f"[Telegram] Bot polling error for {registration_id}: {type(e).__name__}")
                if _bot_running.get(registration_id, False):
                    time.sleep(5)  # ждём перед повтором

    except Exception as e:
        log(f"[Telegram] Bot loop error for {registration_id}: {type(e).__name__}")
    finally:
        _active_bots.pop(registration_id, None)
        _bot_running.pop(registration_id, None)
        log(f"[Telegram] Bot stopped for registration {registration_id}")


def request_topic_detect(registration_id: str) -> None:
    """новый поиск топика сбрасывает предыдущий результат"""
    from .cloud_access import account_primary
    registration_id = account_primary(registration_id)
    with _pending_topic_detects_lock:
        expires = datetime.now() + timedelta(seconds=90)
        _pending_topic_detects[registration_id] = {'topic_id': None, 'expires_at': expires}
    log(f"[Telegram] Topic detect requested for {registration_id}")


def get_and_clear_detected_topic(registration_id: str):
    """найденный топик выдаём один раз, затем очищаем"""
    from .cloud_access import account_primary
    registration_id = account_primary(registration_id)
    with _pending_topic_detects_lock:
        entry = _pending_topic_detects.get(registration_id)
        if not entry:
            return None
        # не протухло ли
        if datetime.now() > entry['expires_at']:
            _pending_topic_detects.pop(registration_id, None)
            return None
        # может, ещё не нашли
        if entry['topic_id'] is None:
            return None
        # нашли, забираем и убираем из ожидания
        _pending_topic_detects.pop(registration_id, None)
        return entry['topic_id']


def start_telegram_bot(registration_id: str, bot_token: str, user_id: str) -> bool:
    """запускаем бота выбранной регистрации"""
    global _bot_threads, _bot_running, _bot_tokens

    # команды бота используют одну стабильную регистрацию аккаунта, даже если
    # настройки сохранены с другого устройства. __server__ не имеет регистрации
    if registration_id != '__server__':
        conn = get_db_connection()
        if not conn:
            return False
        try:
            row = conn.execute('SELECT id FROM cf3_registrations WHERE id = cf3_account_primary(%s)',
                               (registration_id,)).fetchone()
            if row:
                registration_id = row[0]
        finally:
            conn.close()

    if not bot_token or not user_id:
        log(f"[Telegram] Cannot start bot for {registration_id}: missing token or user_id")
        return False

    # вдруг этот токен уже занят другой регистрацией
    for reg_id, token in list(_bot_tokens.items()):
        if token == bot_token and reg_id != registration_id:
            log(f"[Telegram] Token already in use by {reg_id}, stopping it first")
            stop_telegram_bot(reg_id)

    # если бот для этой регистрации уже крутится, гасим
    stop_telegram_bot(registration_id)

    try:
        _bot_running[registration_id] = True
        _bot_tokens[registration_id] = bot_token
        thread = threading.Thread(
            target=_bot_polling_loop,
            args=(registration_id, bot_token, user_id),
            daemon=True
        )
        thread.start()
        _bot_threads[registration_id] = thread
        log(f"[Telegram] Bot started for registration {registration_id}")
        return True
    except Exception as e:
        log(f"[Telegram] Error starting bot for {registration_id}: {type(e).__name__}")
        _bot_running.pop(registration_id, None)
        _bot_tokens.pop(registration_id, None)
        return False


def stop_telegram_bot(registration_id: str):
    """останавливаем бота выбранной регистрации"""
    global _bot_running, _active_bots, _bot_tokens

    if registration_id not in _bot_running and registration_id not in _active_bots:
        return  # гасить нечего

    _bot_running[registration_id] = False

    if registration_id in _active_bots:
        try:
            _active_bots[registration_id].stop_polling()
        except Exception as e:
            log(f"[Telegram] Error stopping bot: {type(e).__name__}")
        _active_bots.pop(registration_id, None)

    # ждём завершения потока, но не вечно
    if registration_id in _bot_threads:
        thread = _bot_threads[registration_id]
        if thread.is_alive():
            log(f"[Telegram] Waiting for bot thread to stop for {registration_id}")
            thread.join(timeout=5)  # больше пяти секунд не ждём
            if thread.is_alive():
                log(f"[Telegram] Bot thread still alive after timeout for {registration_id}")
        _bot_threads.pop(registration_id, None)

    _bot_tokens.pop(registration_id, None)
    log(f"[Telegram] Bot stopped for {registration_id}")


def restart_all_telegram_bots():
    """восстанавливаем ботов по регистрациям в базе"""
    conn = get_db_connection()
    if not conn:
        return

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT id, telegram_bot_token, telegram_user_id
            FROM cf3_registrations
            WHERE telegram_enabled = TRUE
            AND telegram_bot_token IS NOT NULL
            AND telegram_user_id IS NOT NULL
            AND COALESCE(cf3_account_primary(id), id) = id
        """)
        registrations = cursor.fetchall()
        cursor.close()
        conn.close()

        from .cloud_access import server_bot
        shared = server_bot()
        for reg in registrations:
            if shared and reg['telegram_bot_token'] == shared['token']:
                continue
            start_telegram_bot(
                reg['id'],
                reg['telegram_bot_token'],
                reg['telegram_user_id']
            )

        log(f"[Telegram] Restarted {len(registrations)} bots")
    except Exception as e:
        log(f"[Telegram] Error restarting bots: {type(e).__name__}")


def stop_all_telegram_bots():
    """останавливаем всех запущенных ботов"""
    for registration_id in list(_bot_running.keys()):
        stop_telegram_bot(registration_id)
    _bot_tokens.clear()
    log("[Telegram] All bots stopped")
