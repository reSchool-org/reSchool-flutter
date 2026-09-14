import os
import uuid
import json
import requests
from datetime import datetime, timedelta
from html import escape
from pathlib import Path

from flask import Blueprint, jsonify, request, send_file, render_template_string, g as _g
from werkzeug.utils import secure_filename

from .. import cache
from ..school_dates import school_date, SCHOOL_TIMEZONE
from ..database import (
    cache_verified_user,
    get_cached_verified_user,
    get_db_connection,
    homework_version,
    invalidate_homework,
    load_user_session,
)
from ..config import UPLOAD_FOLDER, MAX_FILE_SIZE, MAX_FILES_PER_HOMEWORK, BASE_URL, USER_AGENT, get_public_base_url
from ..rate_limiter import rate_limit
from ..logging_utils import log
from ..utils import allowed_file
from ..eschool_api import server_state
from ..keep_alive import get_session
from .. import analysis
from .notifications import _notify_classmates


bp = Blueprint('homework', __name__)

# логотип должен совпадать с assets/logo.svg в приложении flutter
_APP_LOGO_SVG = (Path(__file__).resolve().parents[1] / 'assets' / 'logo.svg').read_text(encoding='utf-8')
_OPEN_PAGE_JS = (Path(__file__).resolve().parents[1] / 'assets' / 'open.js').read_text(encoding='utf-8')


@bp.route('/open', methods=['GET'])
def open_in_app():
    """страница https открывает ссылку reschool:// по кнопке телеграма"""
    from urllib.parse import quote, unquote, urlencode

    link_type = request.args.get('type', 'diary')

    if link_type == 'link-device':
        server = request.args.get('server', '')
        token = request.args.get('token', '')
        interval = request.args.get('interval', '10')
        deep_link = f"reschool://link-device?server={quote(server, safe='')}&token={quote(token, safe='')}&interval={quote(interval, safe='')}"
        card_html = """
    <div class="info-card">
      <div class="info-card-icon">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M17 1H7C5.9 1 5 1.9 5 3v18c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V3c0-1.1-.9-2-2-2zm-5 20c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1zm5-4H7V4h10v13z"/>
        </svg>
      </div>
      <div class="info-card-text">
        <span class="info-subject">Привязка устройства</span>
        <span class="info-date">Нажмите кнопку ниже, чтобы открыть приложение</span>
      </div>
    </div>"""
        btn_label = "Открыть reSchool"
        return _render_open_page(deep_link, card_html, btn_label)

    if link_type in ('message', 'chat'):
        params = {key: request.args.get(key, '') for key in ('threadId', 'msgNum', 'isGroup')}
        deep_link = 'reschool://message?' + urlencode(params)
        card_html = '<div class="info-card"><div class="info-card-text"><span class="info-subject">Сообщение</span><span class="info-date">Открыть беседу в reSchool</span></div></div>'
        return _render_open_page(deep_link, card_html, 'Открыть сообщение')

    date = request.args.get('date', '')
    subject = request.args.get('subject', '')
    target = 'grade' if link_type == 'grade' else 'diary'
    deep_link = f"reschool://{target}?date={quote(date)}&subject={quote(subject)}"
    if request.args.get('lessonId'):
        deep_link += '&lessonId=' + quote(request.args['lessonId'], safe='')
    display_subject = unquote(subject) or 'Предмет'
    display_date = date or ''

    # дату приводим к человеческому виду, например 27 марта 2026
    try:
        from datetime import datetime as _dt
        _months = ['января','февраля','марта','апреля','мая','июня',
                   'июля','августа','сентября','октября','ноября','декабря']
        _d = _dt.strptime(display_date, '%Y-%m-%d')
        display_date_fmt = f"{_d.day} {_months[_d.month - 1]} {_d.year}"
    except Exception:
        display_date_fmt = display_date

    card_html = f"""
    <div class="info-card">
      <div class="info-card-icon">
        <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
          <path d="M21 5c-1.11-.35-2.33-.5-3.5-.5-1.95 0-4.05.4-5.5 1.5-1.45-1.1-3.55-1.5-5.5-1.5S2.45 4.9 1 6v14.65c0 .25.25.5.5.5.1 0 .15-.05.25-.05C3.1 20.45 5.05 20 6.5 20c1.95 0 4.05.4 5.5 1.5 1.35-.85 3.8-1.5 5.5-1.5 1.65 0 3.35.3 4.75 1.05.1.05.15.05.25.05.25 0 .5-.25.5-.5V6c-.6-.45-1.25-.75-2-1zm0 13.5c-1.1-.35-2.3-.5-3.5-.5-1.7 0-4.15.65-5.5 1.5V8c1.35-.85 3.8-1.5 5.5-1.5 1.2 0 2.4.15 3.5.5v11.5z"/>
        </svg>
      </div>
      <div class="info-card-text">
        <span class="info-subject">{escape(display_subject)}</span>
        <span class="info-date">{escape(display_date_fmt)}</span>
      </div>
    </div>"""
    return _render_open_page(deep_link, card_html, "Открыть приложение")


def _render_open_page(deep_link: str, card_html: str, btn_label: str):
    """показываем страницу перехода в приложение reschool"""
    html = f"""<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Открыть в reSchool</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}

    :root {{
      --primary: #ADC6FF;
      --on-primary: #003380;
      --surface: #1A1C1E;
      --on-surface: #E2E2E6;
      --outline: rgba(226,226,230,0.12);
    }}

    html, body {{
      min-height: 100%;
      font-family: 'Rubik', -apple-system, BlinkMacSystemFont, sans-serif;
      background: var(--surface);
      color: var(--on-surface);
      -webkit-font-smoothing: antialiased;
    }}

    body {{
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100svh;
      padding: 32px 24px;
    }}

    .container {{
      width: 100%;
      max-width: 400px;
      display: flex;
      flex-direction: column;
      align-items: center;
      gap: 0;
    }}

    .logo-icon {{
      width: 100px;
      height: 100px;
      border-radius: 32px;
      background: rgba(173,198,255,0.1);
      border: 1.5px solid rgba(173,198,255,0.2);
      display: flex;
      align-items: center;
      justify-content: center;
      margin-bottom: 24px;
    }}
    .logo-icon svg {{
      width: 100px;
      height: 100px;
      flex-shrink: 0;
    }}
    /* палитра совпадает с тёмным синим логотипом flutter */
    .logo-icon path[fill="#243B7B"] {{ fill: hsl(222.44, 72%, 65%); }}
    .logo-icon path[fill="#69BCE2"] {{ fill: hsl(222.44, 78%, 80%); }}
    .logo-icon path[fill="#D7B34A"] {{ fill: hsl(222.44, 84%, 72%); }}

    .app-title {{
      font-size: 36px;
      font-weight: 600;
      letter-spacing: -1px;
      color: var(--on-surface);
      line-height: 1.1;
      margin-bottom: 8px;
    }}

    .app-subtitle {{
      font-size: 15px;
      font-weight: 400;
      color: var(--on-surface);
      opacity: 0.5;
      margin-bottom: 48px;
    }}

    .info-card {{
      width: 100%;
      background: rgba(173,198,255,0.06);
      border: 1px solid var(--outline);
      border-radius: 14px;
      padding: 16px 20px;
      display: flex;
      align-items: center;
      gap: 16px;
      margin-bottom: 24px;
    }}
    .info-card-icon {{
      width: 40px;
      height: 40px;
      border-radius: 12px;
      background: rgba(173,198,255,0.15);
      display: flex;
      align-items: center;
      justify-content: center;
      flex-shrink: 0;
    }}
    .info-card-icon svg {{
      width: 20px;
      height: 20px;
      fill: var(--primary);
    }}
    .info-card-text {{
      display: flex;
      flex-direction: column;
      gap: 2px;
      text-align: left;
      min-width: 0;
      overflow-wrap: anywhere;
    }}
    .info-subject {{
      font-size: 15px;
      font-weight: 500;
      color: var(--on-surface);
      line-height: 1.3;
    }}
    .info-date {{
      font-size: 13px;
      font-weight: 400;
      color: var(--on-surface);
      opacity: 0.5;
    }}

    .btn {{
      display: flex;
      align-items: center;
      justify-content: center;
      width: 100%;
      height: 56px;
      background: var(--primary);
      color: var(--on-primary);
      text-decoration: none;
      border-radius: 16px;
      font-family: inherit;
      font-size: 16px;
      font-weight: 600;
      letter-spacing: 0.2px;
      border: none;
      cursor: pointer;
      transition: opacity 0.15s ease;
      -webkit-tap-highlight-color: transparent;
    }}
    .btn:hover {{ opacity: 0.92; }}
    .btn:active {{ opacity: 0.80; }}

    .hint {{
      margin-top: 16px;
      font-size: 12px;
      line-height: 1.5;
      color: rgba(226,226,230,0.5);
      text-align: center;
    }}
    .hint:empty {{ display: none; }}
    [hidden] {{ display: none !important; }}
    .fallback {{
      width: 100%;
      margin-top: 24px;
      padding-top: 24px;
      border-top: 1px solid var(--outline);
      text-align: center;
      animation: appear 180ms ease-out;
    }}
    .fallback h2 {{ font-size: 16px; font-weight: 500; }}
    .fallback p {{
      margin: 8px 0 18px;
      font-size: 13px;
      line-height: 1.6;
      color: rgba(226,226,230,0.6);
    }}
    .fallback-actions {{ display: flex; gap: 10px; }}
    .fallback-actions a {{
      display: flex;
      align-items: center;
      justify-content: center;
      flex: 1;
      min-height: 48px;
      padding: 12px;
      border: 1px solid var(--outline);
      border-radius: 14px;
      color: var(--primary);
      text-decoration: none;
      font-size: 13px;
      font-weight: 500;
      transition: background 150ms ease;
    }}
    .fallback-actions a:hover {{ background: rgba(173,198,255,0.08); }}
    a:focus-visible {{ outline: 2px solid var(--primary); outline-offset: 4px; }}
    @keyframes appear {{
      from {{ opacity: 0; transform: translateY(4px); }}
      to {{ opacity: 1; transform: translateY(0); }}
    }}
    @media (prefers-reduced-motion: reduce) {{
      *, *::before, *::after {{ animation: none !important; transition: none !important; }}
    }}
  </style>
</head>
<body>
  <div class="container">
    <div class="logo-icon">
      {_APP_LOGO_SVG}
    </div>
    <div class="app-title">reSchool</div>
    <div class="app-subtitle">Электронный дневник</div>
    {card_html}
    <a class="btn" id="open-app" href="{deep_link}">{btn_label}</a>
    <div class="hint" id="open-status" role="status">Открывается автоматически…</div>
    <section class="fallback" id="open-fallback" aria-labelledby="fallback-title" aria-live="polite" hidden>
      <h2 id="fallback-title">Не открылось?</h2>
      <p>Попробуйте ещё раз или продолжите в браузере.<br>Если reSchool ещё нет - скачайте приложение.</p>
      <div class="fallback-actions">
        <a id="download-app" href="https://github.com/reSchool-org/reSchool-flutter/releases/latest" rel="noreferrer">Скачать</a>
        <a href="/web/">Открыть веб-версию</a>
      </div>
    </section>
    <noscript>
      <p class="hint">Не открылось? <a href="/web/">Открыть веб-версию</a> · <a href="https://github.com/reSchool-org/reSchool-flutter/releases/latest" rel="noreferrer">Скачать</a></p>
    </noscript>
  </div>
  <script>{_OPEN_PAGE_JS}</script>
</body>
</html>"""
    return html, 200, {'Content-Type': 'text/html; charset=utf-8'}


def _normalize_full_name(value):
    """лишние пробелы не должны менять полное имя"""
    if not value:
        return None
    parts = [p for p in str(value).strip().split() if p]
    return " ".join(parts) if parts else None


def _normalize_grade_class(value):
    """убираем пробелы вокруг названия класса"""
    if not value:
        return None
    normalized = str(value).strip()
    return normalized or None


def _normalize_subject_for_match(value):
    """сравниваем предметы без учёта регистра"""
    if not value:
        return None
    normalized = " ".join(str(value).strip().lower().replace("ё", "е").split())
    return normalized or None


def _is_image_file_name(file_name):
    """определяем изображение по расширению имени"""
    if not file_name:
        return False
    lower = str(file_name).lower()
    return lower.endswith((".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg", ".heic", ".heif"))


def _full_name_from_profile(profile):
    """собираем полное имя из школьного профиля"""
    if not isinstance(profile, dict):
        return None

    full = _normalize_full_name(profile.get('fio'))
    if full:
        return full

    parts = [
        profile.get('lastName'),
        profile.get('firstName'),
        profile.get('middleName'),
    ]
    full = _normalize_full_name(" ".join([p for p in parts if p]))
    return full


def _parse_lesson_date(value):
    """строку yyyy-mm-dd приводим к date, иначе postgres не сравнит её с колонкой"""
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, str):
        try:
            return datetime.strptime(value.strip()[:10], "%Y-%m-%d").date()
        except ValueError:
            return None
    return value


def _parse_eschool_date(value):
    """eschool передаёт даты строкой iso или меткой unix"""
    if value is None:
        return None
    try:
        if isinstance(value, (int, float)):
            ts = float(value)
            if ts > 10_000_000_000:  # миллисекунды
                ts /= 1000.0
            return datetime.fromtimestamp(ts)
        text = str(value).strip()
        if not text:
            return None
        if text.endswith('Z'):
            text = text[:-1] + '+00:00'
        return datetime.fromisoformat(text)
    except Exception:
        return None


def _pick_grade_class(classes):
    """выбираем подходящее имя класса из ответа eschool"""
    if not isinstance(classes, list) or not classes:
        return None

    now = datetime.now()
    fallback_name = None

    for cls in classes:
        if not isinstance(cls, dict):
            continue
        name = (cls.get('name') or cls.get('groupName') or '').strip()
        if not name:
            continue
        if fallback_name is None:
            fallback_name = name

        date_from = _parse_eschool_date(cls.get('dtFrom') or cls.get('begDate'))
        date_to = _parse_eschool_date(cls.get('dtTo') or cls.get('endDate'))
        if date_from and date_to and date_from <= now <= date_to:
            return name

    # ведём себя как запасная ветка в приложении: если есть, берём последний элемент
    for cls in reversed(classes):
        if isinstance(cls, dict):
            name = (cls.get('name') or cls.get('groupName') or '').strip()
            if name:
                return name

    return fallback_name


def _resolve_identity_from_registration_session(registration_id):
    """определяем ученика, класс и имя через сессию регистрации"""
    cookies = get_session(registration_id) or load_user_session(registration_id)
    if not cookies:
        return None, None, None

    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/",
    }

    try:
        state_resp = requests.get(
            f"{BASE_URL}/state",
            headers=headers,
            cookies=cookies,
            timeout=15,
        )
        if state_resp.status_code != 200:
            return None, None, None

        state = state_resp.json() or {}
        user = state.get('user', {}) if isinstance(state, dict) else {}
        prs_id = user.get('prsId') if isinstance(user, dict) else None
        profile = state.get('profile', {}) if isinstance(state, dict) else {}
        full_name = _full_name_from_profile(profile)

        user_id = state.get('userId')
        if not user_id and isinstance(user, dict):
            user_id = user.get('userId')
        if not user_id:
            return prs_id, None, full_name

        class_resp = requests.get(
            f"{BASE_URL}/usr/getClassByUser?userId={user_id}",
            headers=headers,
            cookies=cookies,
            timeout=15,
        )
        if not full_name and prs_id:
            try:
                profile_resp = requests.get(
                    f"{BASE_URL}/profile/getProfile_new?prsId={prs_id}",
                    headers=headers,
                    cookies=cookies,
                    timeout=15,
                )
                if profile_resp.status_code == 200:
                    profile_data = profile_resp.json() or {}
                    full_name = _normalize_full_name(profile_data.get('fio'))
            except Exception:
                pass

        if class_resp.status_code != 200:
            return prs_id, None, full_name

        grade_class = _pick_grade_class(class_resp.json())
        return prs_id, grade_class, full_name
    except Exception as e:
        log(f"Error resolving identity via session for {registration_id}: {e}")
        return None, None, None


def _persist_grade_class(cursor, prs_id, grade_class):
    """найденный класс сохраняем для всех токенов пользователя"""
    normalized = _normalize_grade_class(grade_class)
    if not prs_id or not normalized:
        return False
    cursor.execute(
        "UPDATE verified_users SET grade_class = %s WHERE prs_id = %s AND (grade_class IS NULL OR grade_class = '')",
        (normalized, prs_id),
    )
    if cursor.rowcount > 0:
        log(f"[Homework] Restored grade_class='{normalized}' for prs_id={prs_id} (updated {cursor.rowcount} rows)")
        return True
    return False


def _persist_full_name(cursor, prs_id, full_name):
    """найденное имя сохраняем для всех токенов пользователя"""
    normalized = _normalize_full_name(full_name)
    if not prs_id or not normalized:
        return False
    cursor.execute(
        "UPDATE verified_users SET full_name = %s WHERE prs_id = %s AND (full_name IS NULL OR full_name = '')",
        (normalized, prs_id),
    )
    if cursor.rowcount > 0:
        log(f"[Homework] Restored full_name='{normalized}' for prs_id={prs_id} (updated {cursor.rowcount} rows)")
        return True
    return False


def _get_registration_full_name(cursor, registration_id):
    """берём имя из кеша регистрации"""
    if not registration_id:
        return None
    cursor.execute("SELECT full_name FROM cf3_registrations WHERE id = %s", (registration_id,))
    row = cursor.fetchone()
    return _normalize_full_name(row[0]) if row and row[0] else None


def _persist_registration_full_name(cursor, registration_id, full_name):
    """сохраняем имя в кеш регистрации"""
    normalized = _normalize_full_name(full_name)
    if not registration_id or not normalized:
        return False
    cursor.execute(
        "UPDATE cf3_registrations SET full_name = %s WHERE id = %s AND (full_name IS NULL OR full_name = '' OR full_name <> %s)",
        (normalized, registration_id, normalized),
    )
    if cursor.rowcount > 0:
        log(f"[Homework] Saved full_name='{normalized}' to cf3_registrations id={registration_id[:8]}...")
        return True
    return False


def _get_registration_grade_class(cursor, registration_id):
    """берём класс из кеша регистрации"""
    if not registration_id:
        return None
    cursor.execute("SELECT grade_class FROM cf3_registrations WHERE id = %s", (registration_id,))
    row = cursor.fetchone()
    return _normalize_grade_class(row[0]) if row and row[0] else None


def _persist_registration_grade_class(cursor, registration_id, grade_class):
    """сохраняем класс в кеш регистрации"""
    normalized = _normalize_grade_class(grade_class)
    if not registration_id or not normalized:
        return False
    cursor.execute(
        "UPDATE cf3_registrations SET grade_class = %s WHERE id = %s AND (grade_class IS NULL OR grade_class = '' OR grade_class <> %s)",
        (normalized, registration_id, normalized),
    )
    if cursor.rowcount > 0:
        log(f"[Homework] Saved grade_class='{normalized}' to cf3_registrations id={registration_id[:8]}...")
        return True
    return False


def _parse_json_map(raw_value):
    """поле json из базы приводим к словарю"""
    if not raw_value:
        return {}
    if isinstance(raw_value, dict):
        return raw_value
    try:
        parsed = json.loads(raw_value)
        return parsed if isinstance(parsed, dict) else {}
    except Exception:
        return {}


def _resolve_topic_id_for_subject(subject_name, topic_map, known_subjects):
    """ищем топик по названию предмета через известные идентификаторы"""
    subject_key = _normalize_subject_for_match(subject_name)
    if not subject_key or not isinstance(topic_map, dict):
        return None

    # основной режим: ключи topic_map это id предметов, а имена лежат в known_subjects
    for subject_id, mapped_topic in topic_map.items():
        mapped_name = known_subjects.get(str(subject_id)) if isinstance(known_subjects, dict) else None
        if _normalize_subject_for_match(mapped_name) == subject_key:
            try:
                return int(mapped_topic)
            except (TypeError, ValueError):
                return None

    # запасной вариант: в карте топиков разрешаем и прямые имена предметов
    direct_topic = topic_map.get(subject_name) or topic_map.get(subject_key)
    if direct_topic is not None:
        try:
            return int(direct_topic)
        except (TypeError, ValueError):
            return None

    return None


def _notify_group_about_custom_homework(
    grade_class,
    subject,
    lesson_date,
    text,
    author_full_name,
    files,
    base_url,
    event_type="created",
    analysis_data=None,
    homework_id=None,
    analysis_id=None,
):
    """отправляем сообщение группы в топик выбранного предмета"""
    normalized_grade = _normalize_grade_class(grade_class)
    if not normalized_grade:
        log(f"[Homework] Group notify failed: homework_id={homework_id}, reason=missing_class")
        return False

    files = files or []
    base_url = str(base_url or "").rstrip("/")

    conn = get_db_connection()
    if not conn:
        log(f"[Homework] Group notify failed: homework_id={homework_id}, reason=no_database")
        return False

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT id, telegram_bot_token, telegram_group_chat_id,
                   telegram_group_enabled, telegram_topic_map, known_subjects
            FROM cf3_registrations
            WHERE grade_class = %s
              AND telegram_group_enabled = TRUE
              AND COALESCE(cf3_account_primary(id), id) = id
              AND telegram_bot_token IS NOT NULL AND telegram_bot_token <> ''
              AND telegram_group_chat_id IS NOT NULL AND telegram_group_chat_id <> ''
        """, (normalized_grade,))
        registrations = cursor.fetchall() or []
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"[Homework] Group notify DB error: {e}")
        return False
    finally:
        conn.close()

    if not registrations:
        log(f"[Homework] Group notify skipped: homework_id={homework_id}, reason=no_configured_group")
        return True

    try:
        from ..telegram_bot import send_telegram_message
    except Exception as e:
        log(f"[Homework] Telegram import error: {e}")
        return False

    sent = 0
    skipped = 0
    subject_title = (subject or "Предмет").strip()
    author_name = (author_full_name or "Неизвестно").strip()
    lesson_date_text = str(lesson_date)
    homework_text = (text or "").strip()

    message_body = homework_text or "Без текста"

    for reg in registrations:
        topic_map = _parse_json_map(reg.get('telegram_topic_map'))
        known_subjects = _parse_json_map(reg.get('known_subjects'))
        topic_id = _resolve_topic_id_for_subject(subject_title, topic_map, known_subjects)
        # пустой topic_id значит, что топик не задан, пишем в общий чат группы

        attachments = []
        for file_info in files:
            if not isinstance(file_info, dict):
                continue
            file_id = file_info.get("id")
            file_name = file_info.get("fileName")
            file_path = file_info.get("storagePath") or file_info.get("storage_path")
            # у вырезок из учебника имя это подпись, а не файл, расширения там нет
            is_image = file_info["isImage"] if "isImage" in file_info \
                else _is_image_file_name(file_name)
            attachment = {
                "name": file_name or f"Файл {file_id}",
                "isImage": bool(is_image),
            }
            if file_path and os.path.exists(file_path):
                attachment["path"] = file_path
            else:
                # телеграм не сможет скачать вложение по ссылке на закрытое апи
                # карточка уйдёт с пометкой о недоступном вложении и частичной доставке
                log(f"[Homework] Attachment unavailable: homework_id={homework_id}, file_id={file_id}")
            attachments.append(attachment)

        title_prefix = "📝 Новое кастомное ДЗ" if event_type == "created" else "✏️ Обновлено кастомное ДЗ"
        open_url = None
        if lesson_date_text and subject_title:
            from urllib.parse import quote as _quote
            open_url = f"https://reschool.app/open?date={lesson_date_text}&subject={_quote(subject_title)}"
        ok = send_telegram_message(
            reg['telegram_bot_token'],
            str(reg['telegram_group_chat_id']),
            f"{title_prefix}: {subject_title}",
            message_body,
            attachments=attachments,
            message_thread_id=topic_id,
            deep_link_url=open_url,
            notification_type='homework',
            notification_data={'subject': subject_title, 'date': lesson_date_text,
                               'author': author_name, 'attachmentCount': len(files),
                               'id': homework_id, 'analysisId': analysis_id},
            analysis_data=analysis_data,
            require_complete=True,
            durable=True,
        )
        if ok:
            sent += 1
        else:
            skipped += 1

    log(
        f"[Homework] Group custom-homework notify ({event_type}): "
        f"homework_id={homework_id}, analysis_id={analysis_id}, "
        f"queued={sent}, failed={skipped}, class='{normalized_grade}', subject='{subject_title}', files={len(files)}"
    )
    return skipped == 0


def _get_registration_id_for_token(cursor, token):
    """принимаем и токен регистрации, и токен подтверждения"""
    cursor.execute("SELECT id FROM cf3_registrations WHERE id = %s", (token,))
    direct = cursor.fetchone()
    if direct:
        return direct[0]

    cursor.execute(
        "SELECT id FROM cf3_registrations WHERE verification_token = %s ORDER BY updated_at DESC LIMIT 1",
        (token,),
    )
    by_verification = cursor.fetchone()
    return by_verification[0] if by_verification else None


def get_user_by_token(token):
    """кеш авторизации поддерживает токен подтверждения и прежний идентификатор регистрации"""
    cached = get_cached_verified_user(token)
    if cached:
        return cached

    prs_id, grade_class = _resolve_user_by_token(token)
    # промахи не кешируем: отозванный токен должен отваливаться сразу
    if prs_id:
        cache_verified_user(token, prs_id, grade_class)
    return prs_id, grade_class


def _resolve_user_by_token(token):
    """разбор токена по базе, без кеша: одна цепочка запасных вариантов на все форматы токенов"""
    conn = get_db_connection()
    if not conn:
        return None, None
    try:
        cursor = conn.cursor()
        registration_id = _get_registration_id_for_token(cursor, token)
        cursor.execute("SELECT prs_id, grade_class FROM verified_users WHERE token = %s", (token,))
        row = cursor.fetchone()
        if row:
            prs_id, grade_class = row[0], row[1]
            if grade_class:
                if registration_id:
                    if _persist_registration_grade_class(cursor, registration_id, grade_class):
                        conn.commit()
                cursor.close()
                conn.close()
                return prs_id, grade_class

            # токен рабочий, но у старых ссылок grade_class может не быть
            cached_registration_grade = _get_registration_grade_class(cursor, registration_id) if registration_id else None
            if cached_registration_grade:
                if _persist_grade_class(cursor, prs_id, cached_registration_grade):
                    conn.commit()
                cursor.close()
                conn.close()
                return prs_id, cached_registration_grade

            if registration_id:
                session_prs_id, inferred_grade, inferred_full_name = _resolve_identity_from_registration_session(registration_id)
                if session_prs_id and not prs_id:
                    prs_id = session_prs_id
                changed = False
                if inferred_full_name:
                    changed = _persist_full_name(cursor, prs_id, inferred_full_name) or changed
                    changed = _persist_registration_full_name(cursor, registration_id, inferred_full_name) or changed
                if inferred_grade:
                    changed = _persist_grade_class(cursor, prs_id, inferred_grade) or changed
                    changed = _persist_registration_grade_class(cursor, registration_id, inferred_grade) or changed
                if changed:
                    conn.commit()
                if inferred_grade:
                    cursor.close()
                    conn.close()
                    return prs_id, inferred_grade

            # последняя попытка, уже только по базе: берём любой grade_class с тем же prs_id
            cursor.execute(
                "SELECT grade_class FROM verified_users WHERE prs_id = %s AND grade_class IS NOT NULL AND grade_class <> '' ORDER BY created_at DESC LIMIT 1",
                (prs_id,),
            )
            row_with_grade = cursor.fetchone()
            if row_with_grade:
                if registration_id:
                    if _persist_registration_grade_class(cursor, registration_id, row_with_grade[0]):
                        conn.commit()
                cursor.close()
                conn.close()
                return prs_id, row_with_grade[0]

            cursor.close()
            conn.close()
            return prs_id, None

        # ради совместимости: клиент может прислать сюда registrationId от cf3
        cursor.execute("SELECT verification_token FROM cf3_registrations WHERE id = %s", (token,))
        reg_row = cursor.fetchone()
        if reg_row and reg_row[0]:
            cursor.execute("SELECT prs_id, grade_class FROM verified_users WHERE token = %s", (reg_row[0],))
            verified_row = cursor.fetchone()
            if verified_row:
                prs_id, grade_class = verified_row[0], verified_row[1]
                if grade_class:
                    if registration_id:
                        if _persist_registration_grade_class(cursor, registration_id, grade_class):
                            conn.commit()
                    cursor.close()
                    conn.close()
                    return prs_id, grade_class

                # grade_class нет, выводим его из сессии этой регистрации
                session_prs_id, inferred_grade, inferred_full_name = _resolve_identity_from_registration_session(token)
                if session_prs_id and not prs_id:
                    prs_id = session_prs_id
                changed = False
                if inferred_full_name:
                    changed = _persist_full_name(cursor, prs_id, inferred_full_name) or changed
                    changed = _persist_registration_full_name(cursor, token, inferred_full_name) or changed
                if inferred_grade:
                    changed = _persist_grade_class(cursor, prs_id, inferred_grade) or changed
                    changed = _persist_registration_grade_class(cursor, token, inferred_grade) or changed
                if changed:
                    conn.commit()
                if inferred_grade:
                    cursor.close()
                    conn.close()
                    return prs_id, inferred_grade

                cursor.close()
                conn.close()
                return prs_id, None

        # запасной путь для регистраций, заведённых до того,
        # как verification_token начали хранить в cf3_registrations
        session_prs_id, inferred_grade, inferred_full_name = _resolve_identity_from_registration_session(token)
        if session_prs_id:
            changed = False
            if inferred_full_name:
                changed = _persist_full_name(cursor, session_prs_id, inferred_full_name) or changed
                changed = _persist_registration_full_name(cursor, token, inferred_full_name) or changed
            if inferred_grade:
                changed = _persist_grade_class(cursor, session_prs_id, inferred_grade) or changed
                changed = _persist_registration_grade_class(cursor, token, inferred_grade) or changed
            if changed:
                conn.commit()
            cursor.close()
            conn.close()
            return session_prs_id, inferred_grade

        cursor.close()
        conn.close()
        return None, None
    except Exception as e:
        log(f"Error getting user by token: {e}")
        try:
            conn.close()
        except Exception:
            pass
        return None, None


def get_homework_files(cursor, homework_id, include_storage_path=False):
    """читаем вложения задания"""
    cursor.execute("""
        SELECT id, file_name, file_size, mime_type, storage_path
        FROM custom_homework_files
        WHERE homework_id = %s
    """, (homework_id,))
    files = []
    for row in cursor.fetchall():
        file_info = {
            "id": row[0],
            "fileName": row[1],
            "fileSize": row[2],
            "mimeType": row[3]
        }
        if include_storage_path:
            file_info["storagePath"] = row[4]
        files.append(file_info)
    return files


def _public_files_payload(files):
    """оставляем только безопасные для ответа api поля файла"""
    result = []
    for file_info in files or []:
        if not isinstance(file_info, dict):
            continue
        result.append({
            "id": file_info.get("id"),
            "fileName": file_info.get("fileName"),
            "fileSize": file_info.get("fileSize"),
            "mimeType": file_info.get("mimeType"),
        })
    return result


def _validate_homework_uploads(files, max_count=MAX_FILES_PER_HOMEWORK):
    """проверяем загружаемые файлы до создания или изменения задания"""
    uploaded_files = [file for file in files if file and file.filename]
    if len(uploaded_files) > max_count:
        return None, [f"Maximum {max_count} files allowed"]

    errors = []
    validated = []
    for index, file in enumerate(uploaded_files, start=1):
        original_name = secure_filename(file.filename)
        label = original_name or f"file #{index}"

        if not original_name:
            errors.append(f"{label}: invalid file name")
            continue
        if not allowed_file(original_name):
            errors.append(f"{label}: file type is not allowed")
            continue

        file.seek(0, 2)
        file_size = file.tell()
        file.seek(0)
        if file_size > MAX_FILE_SIZE:
            errors.append(f"{label}: file is too large")
            continue

        validated.append((file, original_name, file_size))

    return validated, errors


def _request_summary_rebuild(conn, grade_class, subject, lesson_date):
    """состав слота изменился, сводку надо пересобрать"""
    if not analysis.is_enabled():
        return
    try:
        from .. import merge
        date_iso = lesson_date.isoformat() if hasattr(lesson_date, 'isoformat') else lesson_date
        merge.request_rebuild(conn, grade_class, subject, date_iso)
    except Exception as e:
        log(f"[Homework] Не удалось поставить пересборку сводки: {e}")


def _reanalyze_custom_homework(homework_id, grade_class, subject, lesson_date, text):
    """после правки старый разбор относится к прежнему тексту, заводим новый"""
    if not analysis.is_enabled() or not grade_class or not (text or '').strip():
        return
    conn = get_db_connection()
    if not conn:
        return
    try:
        cursor = conn.cursor()
        date_iso = lesson_date.isoformat() if hasattr(lesson_date, 'isoformat') else str(lesson_date)
        # прежний разбор выводим из слота, иначе в сводке останется старая редакция
        cursor.execute("""
            UPDATE homework_analysis SET status = 'rejected', reject_reason = 'edited'
            WHERE source = 'custom' AND source_id = %s AND status <> 'rejected'
        """, (str(homework_id),))
        cursor.execute("""
            UPDATE pending_notifications SET status = 'dropped'
            WHERE status IN ('pending', 'failed') AND analysis_id IN (
                SELECT id FROM homework_analysis WHERE source = 'custom' AND source_id = %s
            )
        """, (str(homework_id),))
        conn.commit()
        cursor.close()
        analysis_id, _ = analysis.enqueue(
            conn, grade_class, subject, date_iso, text, 'custom', homework_id, force_new=True)
        _request_summary_rebuild(conn, grade_class, subject, date_iso)
        return analysis_id
    except Exception as e:
        log(f"[Homework] Перезапуск разбора после правки не удался: {e}")
    finally:
        conn.close()


def _resolve_grade_class_for_request():
    """класс запроса: одноклассник по токену из g, остальные по полю token
    вернёт (grade_class, None) либо (None, готовый ответ с ошибкой)"""
    if getattr(_g, 'is_classmate', False):
        grade_class = _g.classmate_grade_class
        if not grade_class:
            return None, (jsonify({"error": "Classmate has no grade_class"}), 400)
        return grade_class, None

    token = (request.form.get('token') if request.form else None) \
        or ((request.get_json(silent=True) or {}).get('token')) \
        or request.args.get('token')
    if not token:
        return None, (jsonify({"error": "No token provided"}), 401)
    prs_id, grade_class = get_user_by_token(token)
    if not prs_id:
        return None, (jsonify({"error": "Invalid token"}), 401)
    if not grade_class:
        return None, (jsonify({"error": "User has no grade_class"}), 400)
    return grade_class, None


def _send_custom_homework_notifications(homework_id, grade_class, subject, lesson_date, text,
                                        author_full_name, files, base_url,
                                        classmate_id, exclude_reg_id, extra_lines=None,
                                        analysis_id=None, attachments=None, analysis_data=None,
                                        event_type='created'):
    """разослать своё дз: в группу телеграма и пушем одноклассникам"""
    # очередь хранит только публичные метаданные, поэтому путь берём из базы
    # это нужно и для записей, которые уже были в очереди
    files = files or []
    if files:
        conn = get_db_connection()
        if not conn:
            log(f"[Homework] Attachment lookup failed: homework_id={homework_id}, reason=no_database")
            return False
        try:
            cursor = conn.cursor()
            stored = {str(f['id']): f for f in get_homework_files(cursor, homework_id, include_storage_path=True)}
            files = [stored.get(str(f.get('id')), f) for f in files]
            cursor.close()
        finally:
            conn.close()
    # вырезки из учебника приводим к тому же виду, что и обычные вложения
    crops = [{"fileName": a.get("name") or "Задание", "storagePath": a.get("path"),
              "isImage": True}
             for a in (attachments or []) if a.get("path")]
    try:
        group_result = _notify_group_about_custom_homework(
            grade_class=grade_class,
            subject=subject,
            lesson_date=lesson_date,
            text=text,
            author_full_name=author_full_name,
            files=(files or []) + crops,
            base_url=base_url,
            event_type=event_type,
            analysis_data=analysis_data,
            homework_id=homework_id,
            analysis_id=analysis_id,
        )
    except Exception as notify_error:
        log(f"[Homework] Group custom-homework notify error: {notify_error}")
        group_result = False
    try:
        date_iso = lesson_date.isoformat() if hasattr(lesson_date, 'isoformat') else str(lesson_date)
        body = "\n".join([(text or '')[:120]] + list(extra_lines or []))
        data = {'type': 'homework', 'id': str(homework_id), 'date': date_iso, 'subject': subject}
        if analysis_id:
            data['analysisId'] = str(analysis_id)
        history_result = _notify_classmates(
            grade_class,
            (f"✏️ ДЗ изменено от {author_full_name}: {subject}" if event_type == 'updated'
             else f"📝 ДЗ от {author_full_name}: {subject}"),
            body,
            data,
            exclude_classmate_id=classmate_id,
            exclude_registration_id=exclude_reg_id,
        )
    except Exception as notify_error:
        log(f"[Homework] Classmate history notify error: {notify_error}")
        history_result = False
    return group_result is not False and history_result is not False


def _dispatch_custom_homework(homework_id, grade_class, subject, lesson_date, text,
                              author_full_name, files, base_url, classmate_id, exclude_reg_id,
                              event_type='created'):
    """задание от одноклассника отправляем после проверки на повторы и разбора"""
    date_iso = lesson_date.isoformat() if hasattr(lesson_date, 'isoformat') else str(lesson_date)

    if analysis.is_enabled() and grade_class and (text or '').strip():
        updated_analysis_id = None
        if event_type == 'updated':
            updated_analysis_id = _reanalyze_custom_homework(
                homework_id, grade_class, subject, lesson_date, text)
            if not updated_analysis_id:
                return  # непроверенную правку нельзя отправлять в группу
        conn = get_db_connection()
        if conn:
            try:
                if event_type == 'updated':
                    analysis_id = updated_analysis_id
                else:
                    analysis_id, _ = analysis.enqueue(
                        conn, grade_class, subject, date_iso, text, 'custom', homework_id)
                if analysis_id:
                    analysis.add_pending(
                        conn, analysis_id, 'class',
                        (f"✏️ ДЗ изменено от {author_full_name}: {subject}" if event_type == 'updated'
                         else f"📝 ДЗ от {author_full_name}: {subject}"), text or '',
                        {'type': 'homework', 'id': str(homework_id),
                         'date': date_iso, 'subject': subject},
                        payload={
                            'custom_homework_id': homework_id,
                            'author_full_name': author_full_name,
                            'lesson_date': date_iso,
                            'files': _public_files_payload(files or []),
                            'base_url': base_url,
                            'event_type': event_type,
                        },
                        grade_class=grade_class,
                        exclude_classmate_id=classmate_id,
                        exclude_registration_id=exclude_reg_id)
                    log(f"[Homework] Notification queued: homework_id={homework_id}, analysis_id={analysis_id}, files={len(files or [])}")
                    return
            except Exception as e:
                log(f"[Homework] Не удалось поставить домашнее задание на проверку: {e}")
            finally:
                conn.close()
        if event_type == 'updated':
            return

    _send_custom_homework_notifications(
        homework_id, grade_class, subject, lesson_date, text, author_full_name,
        files, base_url, classmate_id, exclude_reg_id, event_type=event_type)


@bp.route('/custom-homework/create', methods=['POST'])
@rate_limit('default')
def create_custom_homework():
    """создаём своё задание вместе с необязательными вложениями"""
    subject = request.form.get('subject')
    lesson_date = _parse_lesson_date(request.form.get('lesson_date'))
    text = request.form.get('text')

    if not subject or not lesson_date or not text:
        return jsonify({"error": "Missing required fields"}), 400

    validated_files, file_errors = _validate_homework_uploads(
        request.files.getlist('files')
    )
    if file_errors:
        return jsonify({"error": "Invalid file attachments", "fileErrors": file_errors}), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor()

        # выясняем, кто пришёл: одноклассник по токену из g или админ по полю формы
        classmate_id = None
        exclude_reg_id = None
        if getattr(_g, 'is_classmate', False):
            grade_class = _g.classmate_grade_class
            author_full_name = _g.classmate_display_name or 'Одноклассник'
            classmate_id = _g.classmate_id
            prs_id = 0
            if not grade_class:
                cursor.close(); conn.close()
                return jsonify({"error": "Classmate has no grade_class"}), 400
            cursor.execute("""
                INSERT INTO custom_homework
                    (author_prs_id, author_full_name, grade_class, subject, lesson_date, text, author_classmate_id)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING id
            """, (prs_id, author_full_name, grade_class, subject, lesson_date, text, classmate_id))
        else:
            token = request.form.get('token')
            if not token:
                cursor.close(); conn.close()
                return jsonify({"error": "No token provided"}), 401
            prs_id, grade_class = get_user_by_token(token)
            if not prs_id:
                cursor.close(); conn.close()
                return jsonify({"error": "Invalid token"}), 401
            if not grade_class:
                cursor.close(); conn.close()
                return jsonify({"error": "User has no grade_class"}), 400

            reg_id = _get_registration_id_for_token(cursor, token)
            exclude_reg_id = reg_id
            author_full_name = _get_registration_full_name(cursor, reg_id) if reg_id else None
            cursor.execute("SELECT full_name FROM verified_users WHERE token = %s", (token,))
            row = cursor.fetchone()
            author_full_name = author_full_name or (_normalize_full_name(row[0]) if row else None)
            if not author_full_name:
                cursor.execute(
                    "SELECT full_name FROM verified_users WHERE prs_id = %s AND full_name IS NOT NULL AND full_name <> '' ORDER BY created_at DESC LIMIT 1",
                    (prs_id,),
                )
                row = cursor.fetchone()
                author_full_name = _normalize_full_name(row[0]) if row else None
            if author_full_name and reg_id:
                if _persist_registration_full_name(cursor, reg_id, author_full_name):
                    conn.commit()
            if not author_full_name and reg_id:
                session_prs_id, _, inferred_full_name = _resolve_identity_from_registration_session(reg_id)
                target_prs_id = prs_id or session_prs_id
                if inferred_full_name and target_prs_id:
                    changed = _persist_registration_full_name(cursor, reg_id, inferred_full_name)
                    changed = _persist_full_name(cursor, target_prs_id, inferred_full_name) or changed
                    if changed:
                        conn.commit()
                    author_full_name = _normalize_full_name(inferred_full_name)
            if not author_full_name:
                author_full_name = "Unknown"
            classmate_id = None
            cursor.execute("""
                INSERT INTO custom_homework
                    (author_prs_id, author_full_name, grade_class, subject, lesson_date, text)
                VALUES (%s, %s, %s, %s, %s, %s)
                RETURNING id
            """, (prs_id, author_full_name, grade_class, subject, lesson_date, text))

        homework_id = cursor.fetchone()[0]
        conn.commit()

        saved_files = []

        homework_folder = os.path.join(UPLOAD_FOLDER, grade_class, str(homework_id))
        os.makedirs(homework_folder, exist_ok=True)

        for file, original_name, file_size in validated_files or []:
            unique_name = f"{uuid.uuid4().hex[:8]}_{original_name}"
            file_path = os.path.join(homework_folder, unique_name)
            file.save(file_path)
            mime_type = file.content_type or 'application/octet-stream'
            cursor.execute("""
                INSERT INTO custom_homework_files (homework_id, file_name, file_size, mime_type, storage_path)
                VALUES (%s, %s, %s, %s, %s)
                RETURNING id
            """, (homework_id, original_name, file_size, mime_type, file_path))
            saved_files.append({
                "id": cursor.fetchone()[0],
                "fileName": original_name,
                "fileSize": file_size,
                "mimeType": mime_type,
                "storagePath": file_path
            })

        conn.commit()

        cursor.execute("""
            SELECT id, subject, lesson_date, text, author_full_name, created_at
            FROM custom_homework WHERE id = %s
        """, (homework_id,))
        hw = cursor.fetchone()
        cursor.close()
        conn.close()
        invalidate_homework(grade_class)

        log(f"Custom homework created: {homework_id} by {author_full_name} for {grade_class}")
        _dispatch_custom_homework(
            homework_id=homework_id,
            grade_class=grade_class,
            subject=subject,
            lesson_date=lesson_date,
            text=text,
            author_full_name=author_full_name,
            files=saved_files,
            base_url=get_public_base_url() or request.url_root,
            classmate_id=classmate_id,
            exclude_reg_id=exclude_reg_id,
        )

        return jsonify({
            "success": True,
            "homework": {
                "id": hw[0],
                "subject": hw[1],
                "lessonDate": hw[2].isoformat() if hw[2] else None,
                "text": hw[3],
                "authorFullName": hw[4],
                "authorPrsId": prs_id,
                "isMine": True,
                "files": _public_files_payload(saved_files),
                "createdAt": hw[5].isoformat() if hw[5] else None
            }
        })

    except Exception as e:
        log(f"Error creating homework: {e}")
        return jsonify({"error": "Database error"}), 500
    finally:
        conn.close()


@bp.route('/custom-homework/list', methods=['POST'])
@rate_limit('default')
def list_custom_homework():
    """показываем задания только класса пользователя за выбранные даты"""
    data = request.json or {}
    date_from = data.get('date_from')
    date_to = data.get('date_to')

    # выясняем, кто пришёл
    if getattr(_g, 'is_classmate', False):
        grade_class = _g.classmate_grade_class
        classmate_id = _g.classmate_id
        prs_id = None
        if not grade_class:
            return jsonify({"error": "Classmate has no grade_class"}), 400
    else:
        token = data.get('token')
        if not token:
            return jsonify({"error": "No token provided"}), 401
        prs_id, grade_class = get_user_by_token(token)
        if not prs_id:
            return jsonify({"error": "Invalid token"}), 401
        if not grade_class:
            return jsonify({"error": "User has no grade_class"}), 400
        classmate_id = None

    # ключ кеша с версией класса: любая правка домашнего задания двигает версию, и старые ответы отваливаются
    cache_key = f"homework:{grade_class}:{homework_version(grade_class)}:{date_from or ''}:{date_to or ''}"
    items = cache.get(cache_key)

    if items is cache.MISS:
        conn = get_db_connection()
        if not conn:
            return jsonify({"error": "Database connection failed"}), 500

        try:
            cursor = conn.cursor()

            query = """
                SELECT id, author_prs_id, author_full_name, subject, lesson_date, text, created_at, updated_at,
                       author_classmate_id
                FROM custom_homework
                WHERE grade_class = %s
            """
            params = [grade_class]

            parsed_from = _parse_lesson_date(date_from) if date_from else None
            parsed_to = _parse_lesson_date(date_to) if date_to else None
            if parsed_from:
                query += " AND lesson_date >= %s"
                params.append(parsed_from)
            if parsed_to:
                query += " AND lesson_date <= %s"
                params.append(parsed_to)

            query += " ORDER BY lesson_date DESC, created_at DESC"

            cursor.execute(query, tuple(params))
            rows = cursor.fetchall()

            items = []
            for row in rows:
                items.append({
                    "id": row[0],
                    "authorPrsId": row[1],
                    "authorFullName": row[2],
                    "subject": row[3],
                    "lessonDate": row[4].isoformat() if row[4] else None,
                    "text": row[5],
                    "files": get_homework_files(cursor, row[0]),
                    "createdAt": row[6].isoformat() if row[6] else None,
                    "updatedAt": row[7].isoformat() if row[7] else None,
                    "authorClassmateId": row[8],
                })

            cursor.close()
            conn.close()
            cache.set(cache_key, items)

        except Exception as e:
            log(f"Error listing homework: {e}")
            return jsonify({"error": "Database error"}), 500

    # isMine зависит от того, кто спрашивает, поэтому считаем его уже после кеша
    homework_list = []
    for item in items:
        row_classmate_id = item.pop("authorClassmateId", None)
        if classmate_id:
            item["isMine"] = (row_classmate_id == classmate_id)
        else:
            item["isMine"] = (item["authorPrsId"] == prs_id)
        homework_list.append(item)

    return jsonify({"homework": homework_list})


@bp.route('/custom-homework/update', methods=['POST'])
@rate_limit('default')
def update_custom_homework():
    """изменять задание может только автор"""
    homework_id = request.form.get('homework_id')
    text = request.form.get('text')
    delete_file_ids = request.form.get('delete_file_ids')

    if not homework_id:
        return jsonify({"error": "No homework_id provided"}), 400

    # выясняем, кто пришёл
    if getattr(_g, 'is_classmate', False):
        classmate_id = _g.classmate_id
        prs_id = None
    else:
        token = request.form.get('token')
        if not token:
            return jsonify({"error": "No token provided"}), 401
        prs_id, _ = get_user_by_token(token)
        if not prs_id:
            return jsonify({"error": "Invalid token"}), 401
        classmate_id = None

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor()

        # находим id регистрации, чтобы не слать уведомление самому автору
        exclude_reg_id = None
        if not getattr(_g, 'is_classmate', False):
            _token = request.form.get('token', '')
            if _token:
                exclude_reg_id = _get_registration_id_for_token(cursor, _token)

        # проверяем, что это его домашнее задание
        cursor.execute(
            "SELECT author_prs_id, grade_class, author_classmate_id, subject, lesson_date"
            " FROM custom_homework WHERE id = %s",
            (homework_id,)
        )
        row = cursor.fetchone()
        if not row:
            cursor.close()
            conn.close()
            return jsonify({"error": "Homework not found"}), 404
        if classmate_id:
            if row[2] != classmate_id:
                cursor.close()
                conn.close()
                return jsonify({"error": "Not authorized to edit this homework"}), 403
        else:
            if row[0] != prs_id:
                cursor.close()
                conn.close()
                return jsonify({"error": "Not authorized to edit this homework"}), 403

        hw_grade_class = row[1]

        # текст меняем, если он пришёл
        if text:
            cursor.execute("UPDATE custom_homework SET text = %s WHERE id = %s", (text, homework_id))

        # удаляем файлы, которые попросили
        if delete_file_ids:
            try:
                ids_to_delete = json.loads(delete_file_ids)
                for file_id in ids_to_delete:
                    # путь до файла
                    cursor.execute("SELECT storage_path FROM custom_homework_files WHERE id = %s AND homework_id = %s", (file_id, homework_id))
                    file_row = cursor.fetchone()
                    if file_row:
                        # убираем файл с диска
                        if os.path.exists(file_row[0]):
                            os.remove(file_row[0])
                        # и из базы
                        cursor.execute("DELETE FROM custom_homework_files WHERE id = %s", (file_id,))
            except json.JSONDecodeError:
                pass

        # принимаем новые файлы
        files = request.files.getlist('files')

        # считаем, сколько уже есть
        cursor.execute("SELECT COUNT(*) FROM custom_homework_files WHERE homework_id = %s", (homework_id,))
        existing_count = cursor.fetchone()[0]

        homework_folder = os.path.join(UPLOAD_FOLDER, hw_grade_class, str(homework_id))
        os.makedirs(homework_folder, exist_ok=True)

        saved_files = []
        for file in files:
            if existing_count + len(saved_files) >= MAX_FILES_PER_HOMEWORK:
                break

            if file and file.filename:
                if not allowed_file(file.filename):
                    continue

                file.seek(0, 2)
                file_size = file.tell()
                file.seek(0)

                if file_size > MAX_FILE_SIZE:
                    continue

                original_name = secure_filename(file.filename)
                unique_name = f"{uuid.uuid4().hex[:8]}_{original_name}"
                file_path = os.path.join(homework_folder, unique_name)
                file.save(file_path)

                mime_type = file.content_type or 'application/octet-stream'

                cursor.execute("""
                    INSERT INTO custom_homework_files (homework_id, file_name, file_size, mime_type, storage_path)
                    VALUES (%s, %s, %s, %s, %s)
                    RETURNING id
                """, (homework_id, original_name, file_size, mime_type, file_path))

                saved_files.append({
                    "id": cursor.fetchone()[0],
                    "fileName": original_name,
                    "fileSize": file_size,
                    "mimeType": mime_type
                })

        conn.commit()

        # отдаём обновлённое домашнее задание
        cursor.execute("""
            SELECT id, subject, lesson_date, text, author_full_name, author_prs_id, created_at, updated_at
            FROM custom_homework WHERE id = %s
        """, (homework_id,))
        hw = cursor.fetchone()
        all_files = get_homework_files(cursor, homework_id, include_storage_path=True)
        public_files = _public_files_payload(all_files)

        cursor.close()
        conn.close()
        invalidate_homework(hw_grade_class)

        log(f"Custom homework updated: {homework_id}")
        _dispatch_custom_homework(
            homework_id=homework_id,
            grade_class=hw_grade_class,
            subject=hw[1],
            lesson_date=hw[2],
            text=hw[3],
            author_full_name=hw[4],
            files=all_files,
            base_url=get_public_base_url() or request.url_root,
            classmate_id=classmate_id,
            exclude_reg_id=exclude_reg_id,
            event_type='updated',
        )

        return jsonify({
            "success": True,
            "homework": {
                "id": hw[0],
                "subject": hw[1],
                "lessonDate": hw[2].isoformat() if hw[2] else None,
                "text": hw[3],
                "authorFullName": hw[4],
                "authorPrsId": hw[5],
                "isMine": True,
                "files": public_files,
                "createdAt": hw[6].isoformat() if hw[6] else None,
                "updatedAt": hw[7].isoformat() if hw[7] else None
            }
        })

    except Exception as e:
        log(f"Error updating homework: {e}")
        return jsonify({"error": "Database error"}), 500
    finally:
        conn.close()


@bp.route('/custom-homework/delete', methods=['POST'])
@rate_limit('default')
def delete_custom_homework():
    """удалять задание может только автор"""
    data = request.json or {}
    homework_id = data.get('homework_id')

    if not homework_id:
        return jsonify({"error": "No homework_id provided"}), 400

    # выясняем, кто пришёл
    if getattr(_g, 'is_classmate', False):
        classmate_id = _g.classmate_id
        prs_id = None
    else:
        token = data.get('token')
        if not token:
            return jsonify({"error": "No token provided"}), 401
        prs_id, _ = get_user_by_token(token)
        if not prs_id:
            return jsonify({"error": "Invalid token"}), 401
        classmate_id = None

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor()

        # проверяем, что это его домашнее задание
        cursor.execute(
            "SELECT author_prs_id, grade_class, author_classmate_id, subject, lesson_date"
            " FROM custom_homework WHERE id = %s",
            (homework_id,)
        )
        row = cursor.fetchone()
        if not row:
            cursor.close()
            conn.close()
            return jsonify({"error": "Homework not found"}), 404
        if classmate_id:
            if row[2] != classmate_id:
                cursor.close()
                conn.close()
                return jsonify({"error": "Not authorized to delete this homework"}), 403
        else:
            if row[0] != prs_id:
                cursor.close()
                conn.close()
                return jsonify({"error": "Not authorized to delete this homework"}), 403

        grade_class = row[1]

        # собираем пути всех файлов
        cursor.execute("SELECT storage_path FROM custom_homework_files WHERE homework_id = %s", (homework_id,))
        files = cursor.fetchall()

        # чистим файлы с диска
        for file_row in files:
            if file_row[0] and os.path.exists(file_row[0]):
                os.remove(file_row[0])

        # если папка опустела, убираем и её
        homework_folder = os.path.join(UPLOAD_FOLDER, grade_class, str(homework_id))
        if os.path.exists(homework_folder) and not os.listdir(homework_folder):
            os.rmdir(homework_folder)

        # из базы удаляем саму запись, файлы уедут каскадом
        cursor.execute("DELETE FROM custom_homework WHERE id = %s", (homework_id,))
        conn.commit()

        # разбор удалённой записи больше не должен попадать в сводку
        cursor.execute("""
            UPDATE homework_analysis SET status = 'rejected', reject_reason = 'deleted'
            WHERE source = 'custom' AND source_id = %s AND status <> 'rejected'
        """, (str(homework_id),))
        conn.commit()

        cursor.close()
        invalidate_homework(grade_class)
        _request_summary_rebuild(conn, grade_class, row[3], row[4])
        conn.close()

        log(f"Custom homework deleted: {homework_id}")

        return jsonify({"success": True})

    except Exception as e:
        log(f"Error deleting homework: {e}")
        return jsonify({"error": "Database error"}), 500
    finally:
        conn.close()


@bp.route('/custom-homework/file/<int:file_id>', methods=['GET'])
@rate_limit('default')
def download_custom_homework_file(file_id):
    """отдаём файл пользовательского задания"""
    # одноклассник уже прошёл проверку в middleware по заголовку с токеном
    if getattr(_g, 'is_classmate', False):
        grade_class = _g.classmate_grade_class
        if not grade_class:
            return jsonify({"error": "Classmate has no grade_class"}), 400
    else:
        token = request.args.get('token')
        if not token:
            return jsonify({"error": "No token provided"}), 401
        prs_id, grade_class = get_user_by_token(token)
        if not prs_id:
            # запасной путь: ищем по токену в classmate_registrations
            conn_check = get_db_connection()
            if conn_check:
                try:
                    cur = conn_check.cursor()
                    cur.execute(
                        "SELECT grade_class FROM classmate_registrations WHERE classmate_token = %s",
                        (token,)
                    )
                    row = cur.fetchone()
                    cur.close()
                    conn_check.close()
                    if row:
                        grade_class = row[0]
                    else:
                        return jsonify({"error": "Invalid token"}), 401
                except Exception:
                    conn_check.close()
                    return jsonify({"error": "Invalid token"}), 401
            else:
                return jsonify({"error": "Invalid token"}), 401

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor()

        # берём инфу о файле и заодно проверяем доступ по grade_class
        cursor.execute("""
            SELECT f.storage_path, f.file_name, f.mime_type, h.grade_class
            FROM custom_homework_files f
            JOIN custom_homework h ON f.homework_id = h.id
            WHERE f.id = %s
        """, (file_id,))
        row = cursor.fetchone()

        cursor.close()
        conn.close()

        if not row:
            return jsonify({"error": "File not found"}), 404

        file_path, file_name, mime_type, hw_grade_class = row

        # смотрим, из того же ли пользователь класса
        if hw_grade_class != grade_class:
            return jsonify({"error": "Not authorized to download this file"}), 403

        if not os.path.exists(file_path):
            return jsonify({"error": "File not found on server"}), 404

        return send_file(
            file_path,
            mimetype=mime_type or 'application/octet-stream',
            as_attachment=True,
            download_name=file_name
        )

    except Exception as e:
        log(f"Error downloading file: {e}")
        return jsonify({"error": "Server error"}), 500


HOMEWORK_PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Домашние задания</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background: #f0f2f5; color: #1a1a2e; min-height: 100vh; }
  header { background: linear-gradient(135deg, #6a11cb, #2575fc);
           color: white; padding: 18px 24px; display: flex;
           align-items: center; justify-content: space-between; gap: 12px; }
  header h1 { font-size: 1.1rem; font-weight: 600; white-space: nowrap; }
  .nav { display: flex; align-items: center; gap: 10px; }
  .nav a { background: rgba(255,255,255,0.2); color: white; text-decoration: none;
            border-radius: 8px; padding: 6px 14px; font-size: 1.1rem;
            transition: background 0.2s; user-select: none; }
  .nav a:hover { background: rgba(255,255,255,0.35); }
  .date-label { font-size: 1rem; font-weight: 600; min-width: 140px; text-align: center; }
  .today-btn { background: rgba(255,255,255,0.15); color: white; text-decoration: none;
               border-radius: 8px; padding: 5px 12px; font-size: 0.8rem; border: 1px solid rgba(255,255,255,0.4); }
  .today-btn:hover { background: rgba(255,255,255,0.3); }
  main { max-width: 720px; margin: 28px auto; padding: 0 16px 40px; }
  .empty { text-align: center; color: #888; margin-top: 60px; font-size: 1rem; }
  .empty .icon { font-size: 3rem; margin-bottom: 12px; }
  .card { background: white; border-radius: 14px; padding: 18px 20px; margin-bottom: 14px;
          box-shadow: 0 2px 8px rgba(0,0,0,0.07); border-left: 4px solid #6a11cb; }
  .card .subject { font-weight: 700; color: #6a11cb; font-size: 0.9rem;
                   text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 8px; }
  .card .text { font-size: 0.97rem; line-height: 1.55; color: #333; white-space: pre-wrap; }
  .card .files { margin-top: 10px; font-size: 0.82rem; color: #888; }
  .error { background: #fee; border-left-color: #e55; padding: 14px 18px;
           border-radius: 10px; margin-bottom: 14px; font-size: 0.9rem; }
</style>
</head>
<body>
<header>
  <h1>📚 ДЗ</h1>
  <div class="nav">
    <a href="/homework?date={{ prev_date }}" title="Предыдущий день">&#8592;</a>
    <span class="date-label">{{ date_display }}</span>
    <a href="/homework?date={{ next_date }}" title="Следующий день">&#8594;</a>
  </div>
  {% if not is_today %}
  <a class="today-btn" href="/homework">Сегодня</a>
  {% endif %}
</header>
<main>
  {% if error %}
    <div class="card error">{{ error }}</div>
  {% elif not items %}
    <div class="empty">
      <div class="icon">✅</div>
      <div>Домашних заданий на этот день нет</div>
    </div>
  {% else %}
    {% for item in items %}
    <div class="card">
      <div class="subject">{{ item.subject }}</div>
      <div class="text">{{ item.text }}</div>
      {% if item.has_files %}
      <div class="files">📎 Есть прикреплённые файлы</div>
      {% endif %}
    </div>
    {% endfor %}
  {% endif %}
</main>
</body>
</html>"""


def _strip_html(html_string):
    import re
    if not html_string:
        return ""
    text = re.sub(r'<br\s*/?>', '\n', html_string, flags=re.IGNORECASE)
    text = re.sub(r'</p>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'</div>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'<[^>]*>', '', text)
    return text.strip()


def _fetch_homework_for_date(target_date):
    """читаем задания на выбранную дату через сессию сервера"""
    cookies = server_state.cookies
    prs_id = server_state.prs_id

    if not cookies or not prs_id:
        return [], "Сервер не авторизован в eSchool."

    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/"
    }

    d1 = int((target_date - timedelta(days=1)).timestamp() * 1000)
    d2 = int((target_date + timedelta(days=1)).timestamp() * 1000)

    try:
        url = f"{BASE_URL}/student/getPrsDiary?prsId={prs_id}&d1={d1}&d2={d2}"
        resp = requests.get(url, headers=headers, cookies=cookies, timeout=20)
        if resp.status_code == 401:
            return [], "Сессия истекла. Подождите, пока сервер переавторизуется."
        if resp.status_code != 200:
            return [], f"Ошибка API: {resp.status_code}"

        diary = resp.json()
        if not isinstance(diary, dict):
            return [], "Некорректный ответ от API."

        target_date_str = target_date.strftime("%Y-%m-%d")
        items = []

        for lesson in diary.get('lesson', []):
            if not isinstance(lesson, dict):
                continue

            # lesson.date это метка времени в миллисекундах, пустую дату пропускаем, как и приложение
            lesson_ts = lesson.get('date')
            if not lesson_ts:
                continue
            lesson_date_str = school_date(lesson_ts)
            if lesson_date_str != target_date_str:
                continue

            unit = lesson.get('unit')
            subject = unit.get('name') if isinstance(unit, dict) else None
            if not subject:
                subject = lesson.get('subject', 'Предмет')

            for part in lesson.get('part', []):
                if not isinstance(part, dict) or part.get('cat') != 'DZ':
                    continue
                for variant in part.get('variant', []):
                    if not isinstance(variant, dict):
                        continue
                    raw_text = variant.get('text', '')
                    files = variant.get('file', [])
                    clean_text = _strip_html(raw_text)
                    has_files = isinstance(files, list) and len(files) > 0
                    if clean_text or has_files:
                        items.append({
                            'subject': subject,
                            'text': clean_text or '',
                            'has_files': has_files
                        })

        return items, None

    except Exception as e:
        log(f"[Homework page] Error: {e}")
        return [], f"Ошибка запроса: {e}"


WEEKDAYS_RU = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс']
MONTHS_RU = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
             'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря']


@bp.route('/homework')
def homework_page():
    """страница заданий позволяет переходить к соседним дням"""
    date_str = request.args.get('date')
    today = datetime.now(SCHOOL_TIMEZONE).date()

    if date_str:
        try:
            target = datetime.strptime(date_str, "%Y-%m-%d").date()
        except ValueError:
            target = today
    else:
        target = today

    items, error = _fetch_homework_for_date(datetime.combine(target, datetime.min.time()))

    wd = WEEKDAYS_RU[target.weekday()]
    date_display = f"{wd}, {target.day} {MONTHS_RU[target.month - 1]}"

    prev_date = (target - timedelta(days=1)).strftime("%Y-%m-%d")
    next_date = (target + timedelta(days=1)).strftime("%Y-%m-%d")

    return render_template_string(
        HOMEWORK_PAGE_TEMPLATE,
        items=items,
        error=error,
        date_display=date_display,
        prev_date=prev_date,
        next_date=next_date,
        is_today=(target == today)
    )
