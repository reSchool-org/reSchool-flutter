import json
from datetime import datetime

from .database import get_db_connection, json_value
from .logging_utils import log


def save_notification_history(registration_id, notification_type, title, body, data=None):
    """сохраняем на выбранном сервере без обращения к внешним службам уведомлений"""
    conn = get_db_connection()
    if not conn:
        return False
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                INSERT INTO cf3_notification_history (registration_id, notification_type, title, body, data)
                VALUES (%s, %s, %s, %s, %s)
            """, (registration_id, notification_type, title, body, json_value(data or None)))
        conn.commit()
        return True
    except Exception as exc:
        conn.rollback()
        log(f"[Notify] Error saving notification history: {type(exc).__name__}")
        return False
    finally:
        conn.close()


def send_notification_with_telegram(
    title,
    body,
    data=None,
    registration_id=None,
    notification_type='message',
    telegram_attachments=None,
    telegram_attachment_headers=None,
    telegram_attachment_cookies=None,
    telegram_analysis=None,
):
    """сохраняем уведомление локально и доставляем через настроенного бота телеграма"""
    history_result = bool(registration_id) and save_notification_history(
        registration_id, notification_type, title, body, data)
    telegram_result = False

    # смотрим, включён ли телеграм у этой регистрации
    if registration_id:
        telegram_info = get_telegram_info(registration_id)
        if (telegram_info and telegram_info.get('telegram_enabled')
                and telegram_info.get('telegram_delivery_primary', True)
                and telegram_info.get('telegram_bot_token')):
            try:
                from .telegram_bot import send_telegram_message

                # кнопка ведёт на страницу /open, она уже перебрасывает в приложение:
                # схему reschool:// телеграм в кнопках не принимает и отбивает
                # всё сообщение целиком
                hw_deep_link = None
                if notification_type == 'homework' and isinstance(data, dict):
                    hw_date = data.get('date')
                    hw_subject = data.get('subject')
                    if hw_date and hw_subject:
                        from urllib.parse import quote
                        hw_deep_link = (f"https://reschool.app/open?date={quote(hw_date)}"
                                        f"&subject={quote(hw_subject)}")

                # доставка в личку, так было и раньше
                if telegram_info.get('telegram_user_id'):
                    telegram_result = send_telegram_message(
                        telegram_info['telegram_bot_token'],
                        telegram_info['telegram_user_id'],
                        title,
                        body,
                        attachments=telegram_attachments,
                        attachment_headers=telegram_attachment_headers,
                        attachment_cookies=telegram_attachment_cookies,
                        deep_link_url=hw_deep_link,
                        notification_type=notification_type,
                        notification_data=data,
                        analysis_data=telegram_analysis,
                    )

                # в группу шлём только домашнее задание и оценки,
                # сообщения туда намеренно не уходят
                group_enabled = bool(telegram_info.get('telegram_group_enabled'))
                group_chat_id = telegram_info.get('telegram_group_chat_id')
                if group_enabled and group_chat_id and notification_type in ('homework', 'grade'):
                    topic_map_raw = telegram_info.get('telegram_topic_map')
                    topic_map = {}
                    if topic_map_raw:
                        try:
                            parsed = json.loads(topic_map_raw) if isinstance(topic_map_raw, str) else topic_map_raw
                            if isinstance(parsed, dict):
                                topic_map = parsed
                        except Exception:
                            topic_map = {}

                    subject_id = None
                    if isinstance(data, dict):
                        subject_id = data.get('subjectId')
                    subject_key = str(subject_id) if subject_id is not None else None
                    thread_id = None
                    if subject_key:
                        mapped_topic = topic_map.get(subject_key)
                        if mapped_topic is not None:
                            try:
                                topic_id = int(mapped_topic)
                                if not isinstance(mapped_topic, bool) and topic_id > 0:
                                    thread_id = topic_id
                            except (ValueError, TypeError):
                                thread_id = None

                    # без привязки отправляем в общий чат, опуская message_thread_id

                    group_title = title
                    group_body = body

                    # саму оценку в группу выносить нельзя
                    if notification_type == 'grade':
                        group_title = "📝 Новая оценка"

                    group_result = send_telegram_message(
                        telegram_info['telegram_bot_token'],
                        group_chat_id,
                        group_title,
                        group_body,
                        attachments=telegram_attachments if notification_type == 'homework' else None,
                        attachment_headers=telegram_attachment_headers,
                        attachment_cookies=telegram_attachment_cookies,
                        message_thread_id=thread_id,
                        deep_link_url=hw_deep_link,
                        notification_type=notification_type,
                        notification_data=data if notification_type == 'homework' else None,
                        analysis_data=telegram_analysis if notification_type == 'homework' else None,
                    )
                    telegram_result = telegram_result or group_result
            except Exception as e:
                log(f"[CF3] Telegram send error: {type(e).__name__}")

    return history_result or telegram_result


def send_telegram_relogin_notice(registration_id, username):
    """об успешном повторном входе сообщаем только в телеграме"""
    if not registration_id:
        return False

    telegram_info = get_telegram_info(registration_id)
    if not telegram_info:
        return False
    if not telegram_info.get('telegram_enabled') or not telegram_info.get('telegram_delivery_primary', True):
        return False
    if not telegram_info.get('telegram_bot_token') or not telegram_info.get('telegram_user_id'):
        return False

    try:
        from .telegram_bot import send_telegram_message
        now_str = datetime.now().strftime("%d.%m.%Y %H:%M:%S")
        return send_telegram_message(
            telegram_info['telegram_bot_token'],
            telegram_info['telegram_user_id'],
            "🔐 Повторный вход выполнен",
            f"Аккаунт: {username}\nВремя: {now_str}",
        )
    except Exception as e:
        log(f"[CF3] Telegram relogin notice error: {e}")
        return False


def get_telegram_info(registration_id):
    """читаем настройки телеграма для регистрации"""
    conn = get_db_connection()
    if not conn:
        return None

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT COALESCE(cf3_account_primary(id), id) = id AS telegram_delivery_primary,
                   cloud_role, telegram_enabled, telegram_bot_token, telegram_user_id,
                   telegram_group_enabled, telegram_group_chat_id, telegram_group_title, telegram_topic_map
            FROM cf3_registrations WHERE id = %s
        """, (registration_id,))
        row = cursor.fetchone()
        cursor.close()
        conn.close()
        from .cloud_access import apply_server_bot
        return apply_server_bot(registration_id, row)
    except Exception as e:
        log(f"[CF3] Error getting Telegram info: {e}")
        return None
