import json
import re
import uuid
import time
import threading
import requests
import hashlib
import hmac
import secrets
import os
from datetime import datetime, timedelta, timezone

from flask import Blueprint, jsonify, request

from ..database import (
    get_db_connection,
    invalidate_classmate,
    invalidate_registration,
    json_value,
    remember_classmate_token,
)
from ..config import BASE_URL, USER_AGENT, MIN_CHECK_INTERVAL, DEFAULT_CHECK_INTERVAL
from ..check_schedule import CHECK_IS_DUE_SQL, parse_check_interval, schedule_next_check
from ..domain_manager import current_domain_status, get_domain_job, start_domain_job
from ..ip_blacklist import get_ip_blacklist, set_ip_blacklist
from ..tls_manager import tls_status
from ..rate_limiter import rate_limit
from ..logging_utils import log
from ..utils import sha256_hash, generate_random_string, get_random_device_model
from .verification import (find_verified_sender, get_verified_name,
                           issue_verification_token, normalize_grade_class)
from ..notification_delivery import (
    save_notification_history,
    send_notification_with_telegram,
    send_telegram_relogin_notice,
    get_telegram_info,
)
from .. import analysis
from ..school_dates import school_date, school_datetime
from .. import chat_notifications
from ..telegram_bot import start_telegram_bot, stop_telegram_bot, restart_all_telegram_bots, send_telegram_message, request_topic_detect, get_and_clear_detected_topic, create_group_activation_code
from ..encryption import init_encryption, encrypt_password, decrypt_password
from ..keep_alive import update_session, get_session, mark_account_session_invalid


bp = Blueprint('notifications', __name__)

# поток, который следит за обновлениями
_monitor_thread = None
_monitor_running = False

_PUBLIC_HOST = "https://app.eschool.center"
_IMAGE_EXTENSIONS = (
    ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg", ".heic", ".heif"
)
_MAX_TELEGRAM_HOMEWORK_ATTACHMENTS = 8


def _hash_registration_secret(secret):
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()


def _registration_secret_from_request(data=None):
    data = data or {}
    return (
        data.get('registrationSecret')
        or data.get('registration_secret')
        or request.headers.get('X-Registration-Secret')
    )


def _require_registration_owner(registration_id, data=None):
    """операции владельца требуют отдельного секрета регистрации"""
    from flask import g
    if getattr(g, 'cloud_role', 'admin') != 'admin' and registration_id != getattr(g, 'cloud_registration_id', None):
        return jsonify(error='Нет доступа к чужому аккаунту'), 403
    secret = _registration_secret_from_request(data)
    if not secret:
        return jsonify({"error": "Registration secret required"}), 401

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT registration_secret_hash FROM cf3_registrations WHERE id = %s",
            (registration_id,)
        )
        reg = cursor.fetchone()
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"[Notify] Registration owner check error: {e}")
        return jsonify({"error": "Database error"}), 500

    if not reg:
        return jsonify({"error": "Registration not found"}), 404

    stored_hash = reg.get('registration_secret_hash')
    if not stored_hash:
        return jsonify({"error": "Registration must be re-created to enable secure device management"}), 409

    provided_hash = _hash_registration_secret(secret)
    if not hmac.compare_digest(stored_hash, provided_hash):
        return jsonify({"error": "Forbidden"}), 403

    return None


def _normalize_key(value):
    """числовые и строковые идентификаторы приводим к одному ключу"""
    if value is None:
        return None
    try:
        return int(value)
    except (ValueError, TypeError):
        return str(value)


def _compute_homework_hash(hw):
    """хеш задания учитывает текст и ссылки на вложения"""
    content = {
        'text': hw.get('text', '') or '',
        'files': sorted([a.get('url', '') for a in (hw.get('attachments') or []) if a.get('url')]),
    }
    return sha256_hash(json.dumps(content, sort_keys=True, ensure_ascii=False))


def _compute_grade_hash(grade):
    """хеш оценки учитывает значение, причину и вес"""
    content = {
        'value': str(grade.get('value', '') or ''),
        'reason': str(grade.get('reason', '') or ''),
        'weight': str(grade.get('weight') if grade.get('weight') is not None else ''),
    }
    return sha256_hash(json.dumps(content, sort_keys=True, ensure_ascii=False))


def _load_item_hashes(conn, reg_id, item_type):
    """читаем сохранённые хеши по строковым идентификаторам"""
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT item_id, content_hash FROM cf3_item_hashes WHERE registration_id = %s AND item_type = %s",
            (reg_id, item_type)
        )
        result = {row[0]: row[1] for row in cursor.fetchall()}
        cursor.close()
        return result
    except Exception as e:
        log(f"[Notify] Error loading hashes for {item_type}: {e}")
        return {}


def _save_item_hashes(conn, reg_id, item_type, id_hash_map):
    """добавляем новые хеши и обновляем существующие"""
    if not id_hash_map:
        return
    try:
        cursor = conn.cursor()
        cursor.executemany("""
            INSERT INTO cf3_item_hashes (registration_id, item_type, item_id, content_hash)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (registration_id, item_type, item_id) DO UPDATE
            SET content_hash = EXCLUDED.content_hash,
                updated_at = (now() AT TIME ZONE 'utc')
        """, [
            (reg_id, item_type, str(item_id), content_hash)
            for item_id, content_hash in id_hash_map.items()
        ])
        cursor.close()
    except Exception as e:
        log(f"[Notify] Error saving hashes for {item_type}: {e}")


def _format_notify_date(date_ms):
    """дату уведомления получаем из миллисекунд unix"""
    if date_ms is None:
        return "неизвестна"
    try:
        return school_datetime(date_ms).strftime("%d.%m.%Y")
    except Exception:
        return "неизвестна"


def _format_notify_weight(weight):
    """приводим вес оценки к виду для уведомления"""
    if weight is None:
        return "-"
    try:
        value = float(weight)
        if value.is_integer():
            return str(int(value))
        return f"{value:g}".replace(".", ",")
    except (ValueError, TypeError):
        return str(weight)


def _build_api_headers(content_type=None):
    """используем обычные заголовки школьного клиента"""
    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Accept-Language": "ru-RU,en,*",
        "Origin": _PUBLIC_HOST,
        "Referer": f"{_PUBLIC_HOST}/",
    }
    if content_type:
        headers["Content-Type"] = content_type
    return headers


def _normalize_attachment_url(url):
    """приводим ссылки к одному виду и убираем параметры запроса"""
    if not url or not isinstance(url, str):
        return None

    clean = url.strip()
    if not clean:
        return None

    clean = clean.split("?", 1)[0]
    if clean.startswith("//"):
        return f"https:{clean}"
    if clean.startswith("http://") or clean.startswith("https://"):
        return clean
    if clean.startswith("/"):
        return f"{_PUBLIC_HOST}{clean}"
    return f"{_PUBLIC_HOST}/{clean.lstrip('/')}"


def _is_image_attachment(file_name, url):
    """определяем, похоже ли вложение на изображение"""
    candidate = (file_name or url or "").lower()
    return any(candidate.endswith(ext) for ext in _IMAGE_EXTENSIONS)


def _dedupe_attachments(attachments):
    """одинаковые ссылки на вложения оставляем один раз"""
    seen = set()
    result = []
    for attachment in attachments:
        if not isinstance(attachment, dict):
            continue
        url = attachment.get("url")
        if not url or url in seen:
            continue
        seen.add(url)
        result.append(attachment)
    return result


def _extract_inline_image_attachments(raw_html):
    """извлекаем ссылки на картинки из разметки задания"""
    if not isinstance(raw_html, str) or not raw_html:
        return []

    attachments = []
    for idx, match in enumerate(re.finditer(r'<img\b[^>]*\bsrc=["\']([^"\']+)["\']', raw_html, flags=re.IGNORECASE), start=1):
        img_url = _normalize_attachment_url(match.group(1))
        if not img_url:
            continue
        ext = ".jpg"
        lower_url = img_url.lower()
        for candidate_ext in _IMAGE_EXTENSIONS:
            if lower_url.endswith(candidate_ext):
                ext = candidate_ext
                break
        attachments.append({
            "url": img_url,
            "name": f"Изображение {idx}{ext}",
            "isImage": True,
        })

    return _dedupe_attachments(attachments)


def _extract_diary_variant_attachments(variant):
    """к обычным файлам добавляем картинки из текста задания"""
    if not isinstance(variant, dict):
        return []

    attachments = []
    variant_id = variant.get("id")

    files = variant.get("file", [])
    if isinstance(files, list):
        for idx, file_info in enumerate(files, start=1):
            if not isinstance(file_info, dict):
                continue
            file_id = file_info.get("id") or file_info.get("fileId")
            file_name = file_info.get("fileName") or file_info.get("name") or f"Файл {idx}"

            file_url = None
            if variant_id and file_id:
                file_url = f"{BASE_URL}/files/HOMEWORK_VARIANT/{variant_id}/{file_id}"
            elif file_info.get("url"):
                file_url = _normalize_attachment_url(file_info.get("url"))

            if not file_url:
                continue

            attachments.append({
                "url": file_url,
                "name": file_name,
                "isImage": _is_image_attachment(file_name, file_url),
            })

    raw_text = variant.get("text", "") or ""
    attachments.extend(_extract_inline_image_attachments(raw_text))

    return _dedupe_attachments(attachments)


def _fetch_lpart_detail(cookies, prs_id, part_id, headers):
    """запрашиваем подробности нужной части урока"""
    try:
        url = f"{BASE_URL}/student/getLPartPupil?partId={part_id}&prsId={prs_id}"
        resp = requests.get(url, headers=headers, cookies=cookies, timeout=20)
        if resp.status_code != 200:
            log(f"[Notify] LPart detail request failed for partId={part_id}: {resp.status_code}")
            return None
        result = resp.json().get("result", [])
        if not isinstance(result, list) or not result:
            return None
        detail = result[0]
        return detail if isinstance(detail, dict) else None
    except Exception as e:
        log(f"[Notify] _fetch_lpart_detail error for partId={part_id}: {e}")
        return None


def _extract_lpart_attachments(detail):
    """собираем вложения из подробного ответа о части урока"""
    if not isinstance(detail, dict):
        return []

    attachments = []
    var_id = detail.get("varId")

    attach_items = detail.get("attach", [])
    if isinstance(attach_items, list):
        for idx, attach_item in enumerate(attach_items, start=1):
            if not isinstance(attach_item, dict):
                continue
            file_id = attach_item.get("fileId")
            if not file_id or not var_id:
                continue
            file_name = attach_item.get("fileName") or f"Файл {idx}"
            file_url = f"{BASE_URL}/files/HOMEWORK_VARIANT/{var_id}/{file_id}"
            attachments.append({
                "url": file_url,
                "name": file_name,
                "isImage": _is_image_attachment(file_name, file_url),
            })

    task_text = detail.get("taskText", "") or ""
    attachments.extend(_extract_inline_image_attachments(task_text))

    return _dedupe_attachments(attachments)


def _collect_lesson_maps(lessons):
    """метаданные уроков нужны для подробных уведомлений об оценках"""
    lesson_subject_map = {}
    lesson_subject_id_map = {}
    lesson_date_map = {}
    lesson_part_weight_by_id = {}
    lesson_part_weight_by_type = {}
    lesson_default_weight = {}

    for lesson in lessons:
        if not isinstance(lesson, dict):
            continue
        lesson_key = _normalize_key(lesson.get("id"))
        if lesson_key is None:
            continue

        unit = lesson.get("unit")
        subject_name = unit.get("name") if isinstance(unit, dict) else None
        if not subject_name:
            subject_name = lesson.get("subject", "Предмет")
        subject_id = None
        if isinstance(unit, dict):
            subject_id = unit.get("id") or unit.get("unitId")
        if subject_id is None:
            subject_id = lesson.get("unitId")

        lesson_subject_map[lesson_key] = subject_name
        lesson_subject_id_map[lesson_key] = _normalize_key(subject_id)
        lesson_date_map[lesson_key] = lesson.get("date")

        parts = lesson.get("part", [])
        if not isinstance(parts, list):
            continue

        default_weight = None
        for part in parts:
            if not isinstance(part, dict):
                continue

            weight = part.get("mrkWt")
            if default_weight is None and weight is not None:
                default_weight = weight

            part_type = (part.get("cat") or part.get("partType") or "").strip().lower()
            if part_type and weight is not None:
                lesson_part_weight_by_type[(lesson_key, part_type)] = weight

            for id_field in ("id", "partID", "partId", "partid"):
                part_key = _normalize_key(part.get(id_field))
                if part_key is not None and weight is not None:
                    lesson_part_weight_by_id[(lesson_key, part_key)] = weight

        if default_weight is not None:
            lesson_default_weight[lesson_key] = default_weight

    return (
        lesson_subject_map,
        lesson_subject_id_map,
        lesson_date_map,
        lesson_part_weight_by_id,
        lesson_part_weight_by_type,
        lesson_default_weight,
    )


def _resolve_mark_weight(
    lesson_key,
    part_id,
    part_type,
    lesson_part_weight_by_id,
    lesson_part_weight_by_type,
    lesson_default_weight,
):
    """вес оценки берём из метаданных части урока"""
    weight = None
    part_key = _normalize_key(part_id)
    if part_key is not None:
        weight = lesson_part_weight_by_id.get((lesson_key, part_key))
    if weight is None and part_type:
        part_type_key = str(part_type).strip().lower()
        if part_type_key:
            weight = lesson_part_weight_by_type.get((lesson_key, part_type_key))
    if weight is None:
        weight = lesson_default_weight.get(lesson_key)
    return weight


def strip_html(html_string):
    """убираем теги из текста"""
    if not html_string:
        return ""
    # <br> и </p> превращаем в переводы строк
    text = re.sub(r'<br\s*/?>', '\n', html_string, flags=re.IGNORECASE)
    text = re.sub(r'</p>', '\n', text, flags=re.IGNORECASE)
    text = re.sub(r'</div>', '\n', text, flags=re.IGNORECASE)
    # остальные теги просто выкидываем
    text = re.sub(r'<[^>]*>', '', text)
    return text.strip()


def _get_year_id(cookies, prs_id, headers):
    """при ошибке чтения текущего учебного года возвращаем None"""
    try:
        url = f"{BASE_URL}/profile/getProfile_new?prsId={prs_id}"
        resp = requests.get(url, headers=headers, cookies=cookies, timeout=20)
        if resp.status_code != 200:
            return None
        pupils = resp.json().get('pupil', [])
        if not isinstance(pupils, list) or not pupils:
            return None
        max_year_id = max((p.get('yearId', 0) or 0 for p in pupils), default=0)
        return max_year_id if max_year_id > 0 else None
    except Exception as e:
        log(f"[Notify] _get_year_id error: {e}")
        return None


def _fetch_lpart(cookies, prs_id, year_id, d1_ms, d2_ms, headers):
    """читаем исходные задания из частей уроков"""
    try:
        url = (f"{BASE_URL}/student/getLPartListPupil"
               f"?begDate={d1_ms}&endDate={d2_ms}&isOdod=0&prsId={prs_id}&yearId={year_id}")
        lpart_headers = {**headers, "Content-Type": "application/json;charset=UTF-8"}
        resp = requests.put(url, headers=lpart_headers, cookies=cookies, data="[]", timeout=20)
        if resp.status_code != 200:
            log(f"[Notify] LPart request failed: {resp.status_code}")
            return []
        return resp.json().get('result', []) or []
    except Exception as e:
        log(f"[Notify] _fetch_lpart error: {e}")
        return []


def _merge_lpart(homework_list, lpart_items):
    """при объединении дублей сохраняем возможность найти вложения"""
    def content_key(date_ms, subject, text):
        day = school_datetime(date_ms).date()
        normalized = ' '.join(strip_html(text or '').split()).casefold()
        return day, ' '.join(subject.split()).casefold(), normalized

    existing_keys = {}
    for hw in homework_list:
        date_ms = hw.get('date')
        if not date_ms:
            continue
        key = content_key(date_ms, hw.get('subject', ''), hw.get('text', ''))
        existing_keys[key] = hw

    added = 0
    for lpart in lpart_items:
        pass_dt = lpart.get('passDt')
        if not pass_dt:
            continue
        preview = lpart.get('preview', '') or ''
        attach_cnt = lpart.get('attachCnt', 0) or 0
        if not preview and attach_cnt == 0:
            continue

        subject = lpart.get('unitName', 'Предмет') or 'Предмет'
        dedup_key = content_key(pass_dt, subject, preview)

        if dedup_key in existing_keys and dedup_key[2]:
            existing = existing_keys[dedup_key]
            if lpart.get('partId'):
                existing['partId'] = lpart['partId']
            existing['hasFiles'] = bool(existing.get('hasFiles') or attach_cnt)
            continue

        part_id = lpart.get('partId')
        homework_list.append({
            'id': part_id or lpart.get('passlesId'),
            'lessonId': lpart.get('passlesId'),
            'subject': subject,
            'subjectId': _normalize_key(lpart.get('unitId')),
            'text': preview,
            'date': pass_dt,
            'hasFiles': attach_cnt > 0,
            'partId': part_id,
            'attachments': [],
        })
        existing_keys[dedup_key] = homework_list[-1]
        added += 1

    if added:
        log(f"[Notify] LPart added {added} extra homework items")
    return homework_list


def fetch_data_with_session(cookies, username):
    """читаем дневник с существующими куки; только 401 означает истёкшую сессию, прочие сбои не требуют входа"""
    headers = _build_api_headers()

    try:
        state_url = f"{BASE_URL}/state"
        state_resp = requests.get(state_url, headers=headers, cookies=cookies, timeout=30)

        if state_resp.status_code == 401:
            log(f"[Notify] Session expired for {username} (state 401)")
            return None, None, None, None, True, None

        if state_resp.status_code != 200:
            log(f"[Notify] State failed for {username}: {state_resp.status_code}")
            return None, None, None, None, False, None

        state = state_resp.json()
        if not isinstance(state, dict):
            return None, None, None, None, False, None

        user_data = state.get('user')
        if not isinstance(user_data, dict):
            return None, None, None, None, False, None

        prs_id = user_data.get('prsId')
        if not prs_id:
            return None, None, None, None, False, None

        profile = state.get('profile', {}) or {}
        first_name = profile.get('firstName', username) if isinstance(profile, dict) else username

        today = datetime.now()
        d1 = int((today - timedelta(days=14)).timestamp() * 1000)
        d2 = int((today + timedelta(days=14)).timestamp() * 1000)

        diary_url = f"{BASE_URL}/student/getPrsDiary?prsId={prs_id}&d1={d1}&d2={d2}"
        diary_resp = requests.get(diary_url, headers=headers, cookies=cookies, timeout=30)

        if diary_resp.status_code == 401:
            log(f"[Notify] Session expired for {username} (diary 401)")
            return None, None, None, None, True, None

        homework_list = []
        grades_list = []
        lesson_subject_map = {}
        lesson_subject_id_map = {}
        lesson_date_map = {}
        lesson_part_weight_by_id = {}
        lesson_part_weight_by_type = {}
        lesson_default_weight = {}

        if diary_resp.status_code == 200:
            diary_data = diary_resp.json()
            if isinstance(diary_data, dict):
                lessons = diary_data.get('lesson', [])
                (
                    lesson_subject_map,
                    lesson_subject_id_map,
                    lesson_date_map,
                    lesson_part_weight_by_id,
                    lesson_part_weight_by_type,
                    lesson_default_weight,
                ) = _collect_lesson_maps(lessons)
                for lesson in lessons:
                    if not isinstance(lesson, dict):
                        continue
                    lesson_id = lesson.get('id')
                    lesson_key = _normalize_key(lesson_id)
                    lesson_date = lesson.get('date')
                    subject_name = lesson_subject_map.get(lesson_key, 'Предмет')
                    parts = lesson.get('part', [])
                    if not isinstance(parts, list):
                        continue
                    for part in parts:
                        if not isinstance(part, dict) or part.get('cat') != 'DZ':
                            continue
                        variants = part.get('variant', [])
                        if not isinstance(variants, list):
                            continue
                        for variant in variants:
                            if not isinstance(variant, dict):
                                continue
                            variant_id = variant.get('id')
                            raw_text = variant.get('text', '') or ''
                            clean_text = strip_html(raw_text)
                            attachments = _extract_diary_variant_attachments(variant)
                            has_content = bool(clean_text) or bool(attachments)
                            if has_content and variant_id:
                                homework_list.append({
                                    'id': variant_id,
                                    'lessonId': lesson_id,
                                    'subject': subject_name,
                                    'subjectId': lesson_subject_id_map.get(lesson_key),
                                    'text': clean_text if clean_text else '[Файлы]',
                                    'date': lesson_date,
                                    'hasFiles': bool(attachments),
                                    'attachments': attachments,
                                })

                users = diary_data.get('user', [])
                if isinstance(users, list) and len(users) > 0:
                    for mark in users[0].get('mark', []):
                        if not isinstance(mark, dict):
                            continue
                        mark_id = mark.get('id')
                        mark_value = mark.get('value')
                        mark_lesson_key = _normalize_key(mark.get('lessonID'))
                        if mark_id and mark_value:
                            mark_reason = mark.get('partType') or 'Оценка'
                            mark_weight = _resolve_mark_weight(
                                mark_lesson_key,
                                mark.get('partID'),
                                mark_reason,
                                lesson_part_weight_by_id,
                                lesson_part_weight_by_type,
                                lesson_default_weight,
                            )
                            grades_list.append({
                                'id': mark_id,
                                'value': str(mark_value),
                                'subject': lesson_subject_map.get(mark_lesson_key, 'Предмет'),
                                'subjectId': lesson_subject_id_map.get(mark_lesson_key),
                                'lessonId': mark.get('lessonID'),
                                'partType': mark.get('partType'),
                                'partId': mark.get('partID'),
                                'date': lesson_date_map.get(mark_lesson_key),
                                'reason': mark_reason,
                                'weight': mark_weight,
                            })

        # добираем домашнее задание из lpart, это второй источник, как и в приложении
        year_id = _get_year_id(cookies, prs_id, headers)
        if year_id:
            lpart_items = _fetch_lpart(cookies, prs_id, year_id, d1, d2, headers)
            _merge_lpart(homework_list, lpart_items)

        notifications_list, session_expired = _fetch_chat_threads(cookies, headers)
        if session_expired:
            return None, None, None, None, True, prs_id

        log(f"[Notify] Session fetch OK for {username}: HW={len(homework_list)}, Grades={len(grades_list)}, Msgs={len(notifications_list or [])}")
        return homework_list, grades_list, notifications_list, first_name, False, prs_id

    except Exception as e:
        log(f"[Notify] fetch_data_with_session error for {username}: {e}")
        return None, None, None, None, False, None


def get_periods_for_user(username, password):
    """периоды собираем по всем классам и учебным годам, как в приложении"""
    password_hash = sha256_hash(password)
    device_id = generate_random_string(16).lower()
    push_token = generate_random_string(152)
    device_model = get_random_device_model()

    device_payload = {
        "cliType": "mobile",
        "cliVer": "7.4.0",
        "pushToken": push_token,
        "deviceId": device_id,
        "deviceName": "-",
        "deviceModel": device_model,
        "cliOs": "android",
        "cliOsVer": "9"
    }

    body = {
        "username": username,
        "password": password_hash,
        "device": json.dumps(device_payload)
    }

    headers = _build_api_headers("application/x-www-form-urlencoded")

    try:
        # входим
        url = f"{BASE_URL}/login"
        response = requests.post(url, data=body, headers=headers, timeout=30)

        if response.status_code != 200:
            return None, None, "Ошибка входа"

        cookies = response.cookies

        # из state достаём userId
        state_url = f"{BASE_URL}/state"
        state_resp = requests.get(state_url, headers=headers, cookies=cookies, timeout=30)
        if state_resp.status_code != 200:
            return None, None, "Ошибка получения состояния"

        state = state_resp.json()
        user_id = state.get('userId')
        if not user_id:
            return None, None, "UserId не найден"

        # тянем все классы и группы пользователя, каждый класс это учебный год
        class_url = f"{BASE_URL}/usr/getClassByUser?userId={user_id}"
        class_resp = requests.get(class_url, headers=headers, cookies=cookies, timeout=30)
        if class_resp.status_code != 200:
            return None, None, "Ошибка получения класса"

        classes = class_resp.json()
        if not classes or not isinstance(classes, list) or len(classes) == 0:
            return None, None, "Класс не найден"

        # сортируем классы по begDate, свежие сверху, как в приложении
        classes = sorted(classes, key=lambda x: x.get('begDate') or 0, reverse=True)

        def extract_school_year(date1_ms, date2_ms):
            """учебный год определяем по датам периода"""
            if not date1_ms:
                return None
            try:
                # date1 приходит в миллисекундах
                date1 = school_datetime(date1_ms)
                # учебный год начинается в сентябре,
                # если месяц восьмой или дальше, то год текущий и следующий,
                # иначе прошлый и текущий
                if date1.month >= 8:
                    return f"{date1.year}-{date1.year + 1}"
                else:
                    return f"{date1.year - 1}-{date1.year}"
            except Exception:
                return None

        def flatten_periods(items_list, depth=0):
            """вложенные периоды собираем в один список по датам"""
            result = []
            # элементы сортируем по date1
            sorted_items = sorted(items_list, key=lambda x: x.get('date1') or 0)

            for item in sorted_items:
                date1 = item.get('date1')
                date2 = item.get('date2')
                school_year = extract_school_year(date1, date2)
                type_code = item.get('typeCode', '')

                # оставляем только нужные типы периодов: Q четверть, HY полугодие, Y год,
                # каникулы (V) и всё прочее пропускаем
                is_relevant = type_code in ('Q', 'HY', 'Y', '')

                if is_relevant:
                    # период считаем текущим, если сегодня попадает в его диапазон
                    is_current = False
                    if date1 and date2:
                        now_ms = datetime.now().timestamp() * 1000
                        is_current = date1 <= now_ms <= date2

                    result.append({
                        'id': item.get('id'),
                        'name': item.get('name', 'Период'),
                        'isCurrent': is_current or item.get('isCurrent', False),
                        'schoolYear': school_year,
                        'typeCode': type_code,
                        'date1': date1,
                        'depth': depth
                    })

                # вложенные элементы разбираем рекурсивно
                nested = item.get('items', [])
                if nested:
                    result.extend(flatten_periods(nested, depth + 1 if is_relevant else depth))
            return result

        # проходим по всем классам, то есть по всем учебным годам, и собираем периоды
        all_periods = []
        seen_period_ids = set()

        for cls in classes:
            group_id = cls.get('groupId')
            if not group_id:
                continue

            # периоды этого класса или группы
            periods_url = f"{BASE_URL}/dict/periods/0?groupId={group_id}"
            periods_resp = requests.get(periods_url, headers=headers, cookies=cookies, timeout=30)
            if periods_resp.status_code != 200:
                continue

            periods_data = periods_resp.json()
            items = periods_data.get('items', [])
            periods = flatten_periods(items)

            # добавляем, следя за тем, чтобы не задвоить
            for p in periods:
                if p['id'] not in seen_period_ids:
                    seen_period_ids.add(p['id'])
                    all_periods.append(p)

        return all_periods, cookies, None

    except Exception as e:
        log(f"[Notify] Error getting periods: {e}")
        return None, None, f"Ошибка: {e}"


def get_subjects_for_user(username, password):
    """справочник предметов получаем из уроков дневника"""
    password_hash = sha256_hash(password)
    device_id = generate_random_string(16).lower()
    push_token = generate_random_string(152)
    device_model = get_random_device_model()

    device_payload = {
        "cliType": "mobile",
        "cliVer": "7.4.0",
        "pushToken": push_token,
        "deviceId": device_id,
        "deviceName": "-",
        "deviceModel": device_model,
        "cliOs": "android",
        "cliOsVer": "9"
    }

    body = {
        "username": username,
        "password": password_hash,
        "device": json.dumps(device_payload)
    }

    headers = _build_api_headers("application/x-www-form-urlencoded")

    try:
        # входим
        response = requests.post(f"{BASE_URL}/login", data=body, headers=headers, timeout=30)
        if response.status_code != 200:
            return None, "Ошибка входа"

        cookies = response.cookies

        # выясняем prsId
        state_resp = requests.get(f"{BASE_URL}/state", headers=headers, cookies=cookies, timeout=30)
        if state_resp.status_code != 200:
            return None, "Ошибка получения состояния"

        state = state_resp.json()
        user_data = state.get('user', {}) if isinstance(state, dict) else {}
        prs_id = user_data.get('prsId') if isinstance(user_data, dict) else None
        if not prs_id:
            return None, "PrsId не найден"

        # диапазон берём шире, чем для уведомлений, иначе часть предметов выпадет из расписания
        today = datetime.now()
        d1 = int((today - timedelta(days=180)).timestamp() * 1000)
        d2 = int((today + timedelta(days=180)).timestamp() * 1000)

        diary_url = f"{BASE_URL}/student/getPrsDiary?prsId={prs_id}&d1={d1}&d2={d2}"
        diary_resp = requests.get(diary_url, headers=headers, cookies=cookies, timeout=30)
        if diary_resp.status_code != 200:
            return None, f"Ошибка получения дневника: {diary_resp.status_code}"

        diary_data = diary_resp.json()
        lessons = diary_data.get('lesson', []) if isinstance(diary_data, dict) else []
        if not isinstance(lessons, list):
            lessons = []

        subjects = {}
        for lesson in lessons:
            if not isinstance(lesson, dict):
                continue
            unit = lesson.get('unit')
            unit_id = None
            unit_name = None
            if isinstance(unit, dict):
                unit_id = unit.get('id') or unit.get('unitId')
                unit_name = unit.get('name')
            if unit_id is None:
                unit_id = lesson.get('unitId')
            if not unit_name:
                unit_name = lesson.get('subject')

            if unit_id is None or not unit_name:
                continue
            subjects[str(unit_id)] = str(unit_name)

        result = [{'id': sid, 'name': name} for sid, name in sorted(subjects.items(), key=lambda kv: kv[1].lower())]
        return result, None

    except Exception as e:
        log(f"[Notify] Error getting subjects: {e}")
        return None, f"Ошибка: {e}"


def get_grades_for_period(username, password, period_id):
    """итоги берём из getDiaryUnits, отдельные оценки из getDiaryPeriod_, как в приложении"""
    password_hash = sha256_hash(password)
    device_id = generate_random_string(16).lower()
    push_token = generate_random_string(152)
    device_model = get_random_device_model()

    device_payload = {
        "cliType": "mobile",
        "cliVer": "7.4.0",
        "pushToken": push_token,
        "deviceId": device_id,
        "deviceName": "-",
        "deviceModel": device_model,
        "cliOs": "android",
        "cliOsVer": "9"
    }

    body = {
        "username": username,
        "password": password_hash,
        "device": json.dumps(device_payload)
    }

    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Accept-Language": "ru-RU,en,*",
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/",
        "Content-Type": "application/x-www-form-urlencoded"
    }

    try:
        # входим
        url = f"{BASE_URL}/login"
        response = requests.post(url, data=body, headers=headers, timeout=30)

        if response.status_code != 200:
            return None, None, None, "Ошибка входа"

        cookies = response.cookies

        # из state достаём userId
        state_url = f"{BASE_URL}/state"
        state_resp = requests.get(state_url, headers=headers, cookies=cookies, timeout=30)
        if state_resp.status_code != 200:
            return None, None, None, "Ошибка получения состояния"

        state = state_resp.json()
        user_id = state.get('userId')
        if not user_id:
            return None, None, None, "UserId не найден"

        # берём diary units, это сводка по предметам со средними баллами
        # запрос: /student/getDiaryUnits/?userId={userId}&eiId={periodId}
        # ответ: {result: [{unitId, unitName, overMark, totalMark, rating}]}
        units_url = f"{BASE_URL}/student/getDiaryUnits/?userId={user_id}&eiId={period_id}"
        units_resp = requests.get(units_url, headers=headers, cookies=cookies, timeout=30)
        if units_resp.status_code != 200:
            return None, None, None, f"Ошибка получения предметов: {units_resp.status_code}"

        units_data = units_resp.json()
        units_list = units_data.get('result', [])

        # берём diary period, тут уже оценки за конкретные уроки
        # запрос: /student/getDiaryPeriod_/?userId={userId}&eiId={periodId}
        # ответ: {result: [{lessonId, unitId, part: [{mark: [{markValue}], mrkWt}]}]}
        diary_url = f"{BASE_URL}/student/getDiaryPeriod_/?userId={user_id}&eiId={period_id}"
        diary_resp = requests.get(diary_url, headers=headers, cookies=cookies, timeout=30)

        # раскладываем оценки по unitId
        marks_by_unit = {}
        if diary_resp.status_code == 200:
            diary_data = diary_resp.json()
            lessons = diary_data.get('result', [])

            for lesson in lessons:
                unit_id = lesson.get('unitId')
                if unit_id is None:
                    continue

                parts = lesson.get('part', [])
                for part in parts:
                    marks = part.get('mark', [])
                    for mark in marks:
                        mark_value = mark.get('markValue')
                        if mark_value:
                            if unit_id not in marks_by_unit:
                                marks_by_unit[unit_id] = []
                            marks_by_unit[unit_id].append(str(mark_value))

        # собираем итоговый список из предметов и оценок
        grades_list = []
        for unit in units_list:
            unit_id = unit.get('unitId')
            subject_name = unit.get('unitName', 'Предмет')
            over_mark = unit.get('overMark')  # средний балл от api
            total_mark = unit.get('totalMark')  # итоговая, если она уже есть
            rating = unit.get('rating')

            # оценки этого предмета
            grade_values = marks_by_unit.get(unit_id, [])

            # итоговая бывает пустой, числом или строкой, поэтому аккуратно
            final_str = None
            if total_mark is not None and total_mark != '':
                try:
                    # целое показываем без дробной части
                    total_float = float(total_mark)
                    if total_float == int(total_float):
                        final_str = str(int(total_float))
                    else:
                        final_str = str(total_mark)
                except (ValueError, TypeError):
                    final_str = str(total_mark) if total_mark else None

            # предмет берём, если у него есть хоть оценки, хоть средний, хоть итоговая
            if grade_values or over_mark is not None or final_str is not None:
                grades_list.append({
                    'subject': subject_name,
                    'grades': grade_values,
                    'average': over_mark,
                    'final': final_str,
                    'rating': rating
                })

        # название периода вытаскиваем из списка периодов
        class_url = f"{BASE_URL}/usr/getClassByUser?userId={user_id}"
        class_resp = requests.get(class_url, headers=headers, cookies=cookies, timeout=30)
        period_name = f"Период {period_id}"

        def find_period_name(items, target_id):
            """имя периода ищем и во вложенных разделах"""
            for item in items:
                if item.get('id') == target_id:
                    return item.get('name')
                nested = item.get('items', [])
                if nested:
                    result = find_period_name(nested, target_id)
                    if result:
                        return result
            return None

        if class_resp.status_code == 200:
            classes = class_resp.json()
            if classes and len(classes) > 0:
                group_id = classes[0].get('groupId')
                if group_id:
                    periods_url = f"{BASE_URL}/dict/periods/0?groupId={group_id}"
                    periods_resp = requests.get(periods_url, headers=headers, cookies=cookies, timeout=30)
                    if periods_resp.status_code == 200:
                        periods_data = periods_resp.json()
                        found_name = find_period_name(periods_data.get('items', []), period_id)
                        if found_name:
                            period_name = found_name

        return grades_list, period_name, cookies, None

    except Exception as e:
        log(f"[Notify] Error getting grades for period: {e}")
        return None, None, None, f"Ошибка: {e}"


def login_and_get_data(username, password):
    """после входа читаем задания из частей DZ, оценки из отметок пользователя в getPrsDiary"""
    password_hash = sha256_hash(password)
    device_id = generate_random_string(16).lower()
    push_token = generate_random_string(152)
    device_model = get_random_device_model()

    device_payload = {
        "cliType": "mobile",
        "cliVer": "7.4.0",
        "pushToken": push_token,
        "deviceId": device_id,
        "deviceName": "-",
        "deviceModel": device_model,
        "cliOs": "android",
        "cliOsVer": "9"
    }

    body = {
        "username": username,
        "password": password_hash,
        "device": json.dumps(device_payload)
    }

    headers = {
        "Accept": "application/json, text/plain, */*",
        "User-Agent": USER_AGENT,
        "Accept-Language": "ru-RU,en,*",
        "Origin": "https://app.eschool.center",
        "Referer": "https://app.eschool.center/",
        "Content-Type": "application/x-www-form-urlencoded"
    }

    try:
        # входим
        url = f"{BASE_URL}/login"
        response = requests.post(url, data=body, headers=headers, timeout=30)

        if response.status_code != 200:
            log(f"[Notify] Login failed for {username}: {response.status_code} - {response.text[:200]}")
            return None, None, None, None, None, None

        cookies = response.cookies

        # из state достаём prsId
        state_url = f"{BASE_URL}/state"
        state_resp = requests.get(state_url, headers=headers, cookies=cookies, timeout=30)
        if state_resp.status_code != 200:
            log(f"[Notify] State failed for {username}: {state_resp.status_code}")
            return None, None, None, None, None, None

        state = state_resp.json()

        if not isinstance(state, dict):
            log(f"[Notify] State is not a dict: {type(state)} - {str(state)[:200]}")
            return None, None, None, None, None, None

        user_data = state.get('user')
        if not isinstance(user_data, dict):
            log(f"[Notify] User data is not a dict: {type(user_data)}")
            return None, None, None, None, None, None

        prs_id = user_data.get('prsId')

        if not prs_id:
            log(f"[Notify] No prsId found for {username}")
            return None, None, None, None, None, None

        # дневник отдаёт и домашнее задание, и оценки одним запросом
        today = datetime.now()
        # d1 и d2 ждут миллисекунды
        d1 = int((today - timedelta(days=14)).timestamp() * 1000)
        d2 = int((today + timedelta(days=14)).timestamp() * 1000)

        diary_url = f"{BASE_URL}/student/getPrsDiary?prsId={prs_id}&d1={d1}&d2={d2}"
        log(f"[Notify] Requesting Diary: {diary_url}")
        diary_resp = requests.get(diary_url, headers=headers, cookies=cookies, timeout=30)

        homework_list = []
        grades_list = []
        lesson_subject_map = {}  # lessonID → название предмета, пригодится для уведомлений об оценках
        lesson_subject_id_map = {}
        lesson_date_map = {}
        lesson_part_weight_by_id = {}
        lesson_part_weight_by_type = {}
        lesson_default_weight = {}

        if diary_resp.status_code == 200:
            diary_data = diary_resp.json()

            if not isinstance(diary_data, dict):
                log(f"[Notify] Diary response is not a dict: {type(diary_data)}")
            else:
                # разбираем уроки: и домашнее задание, и карту lessonID к предмету
                lessons = diary_data.get('lesson', [])
                log(f"[Notify] Found {len(lessons)} lessons in diary")
                (
                    lesson_subject_map,
                    lesson_subject_id_map,
                    lesson_date_map,
                    lesson_part_weight_by_id,
                    lesson_part_weight_by_type,
                    lesson_default_weight,
                ) = _collect_lesson_maps(lessons)

                for lesson in lessons:
                    if not isinstance(lesson, dict):
                        continue

                    lesson_id = lesson.get('id')
                    lesson_key = _normalize_key(lesson_id)
                    lesson_date = lesson.get('date')
                    subject_name = lesson_subject_map.get(lesson_key, 'Предмет')

                    # домашнее задание лежит в part[], где cat равен DZ,
                    # логика та же, что в AssignmentsViewModel
                    parts = lesson.get('part', [])
                    if not isinstance(parts, list):
                        continue

                    for part in parts:
                        if not isinstance(part, dict):
                            continue

                        # это домашнее задание, если cat равен DZ
                        cat = part.get('cat')
                        if cat != 'DZ':
                            continue

                        # варианты с текстом или файлами
                        variants = part.get('variant', [])
                        if not isinstance(variants, list):
                            continue

                        for variant in variants:
                            if not isinstance(variant, dict):
                                continue

                            variant_id = variant.get('id')
                            raw_text = variant.get('text', '') or ''

                            # чистим html из текста
                            clean_text = strip_html(raw_text)
                            attachments = _extract_diary_variant_attachments(variant)

                            # домашнее задание берём, если есть либо текст, либо файлы
                            has_content = bool(clean_text) or bool(attachments)

                            if has_content and variant_id:
                                # за id домашнего задания берём variant_id, он уникален
                                homework_list.append({
                                    'id': variant_id,
                                    'lessonId': lesson_id,
                                    'subject': subject_name,
                                    'subjectId': lesson_subject_id_map.get(lesson_key),
                                    'text': clean_text if clean_text else '[Файлы]',
                                    'date': lesson_date,
                                    'hasFiles': bool(attachments),
                                    'attachments': attachments,
                                })

                log(f"[Notify] Found {len(homework_list)} homework items")

                # оценки лежат в user[0].mark[],
                # структура та же, что в diary_models.dart
                users = diary_data.get('user', [])
                if isinstance(users, list) and len(users) > 0:
                    user_marks = users[0].get('mark', [])
                    if isinstance(user_marks, list):
                        log(f"[Notify] Found {len(user_marks)} marks in diary")

                        for mark in user_marks:
                            if not isinstance(mark, dict):
                                continue

                            mark_id = mark.get('id')
                            mark_value = mark.get('value')
                            mark_lesson_key = _normalize_key(mark.get('lessonID'))

                            if mark_id and mark_value:
                                # название предмета достаём из карты уроков
                                mark_subject = lesson_subject_map.get(mark_lesson_key, 'Предмет')
                                mark_reason = mark.get('partType') or 'Оценка'
                                mark_weight = _resolve_mark_weight(
                                    mark_lesson_key,
                                    mark.get('partID'),
                                    mark_reason,
                                    lesson_part_weight_by_id,
                                    lesson_part_weight_by_type,
                                    lesson_default_weight,
                                )

                                grades_list.append({
                                    'id': mark_id,
                                    'value': str(mark_value),
                                    'subject': mark_subject,
                                    'subjectId': lesson_subject_id_map.get(mark_lesson_key),
                                    'lessonId': mark.get('lessonID'),
                                    'partType': mark.get('partType'),
                                    'partId': mark.get('partID'),
                                    'date': lesson_date_map.get(mark_lesson_key),
                                    'reason': mark_reason,
                                    'weight': mark_weight,
                                })

                        log(f"[Notify] Collected {len(grades_list)} grades")
                    else:
                        log("[Notify] user[0].mark is not a list")
                else:
                    log("[Notify] No user data in diary response")
        else:
            log(f"[Notify] Diary request failed: {diary_resp.status_code} - {diary_resp.text[:100]}")

        # добираем домашнее задание из lpart, это второй источник, как и в приложении
        year_id = _get_year_id(cookies, prs_id, headers)
        if year_id:
            lpart_items = _fetch_lpart(cookies, prs_id, year_id, d1, d2, headers)
            _merge_lpart(homework_list, lpart_items)

        notifications_list, session_expired = _fetch_chat_threads(cookies, headers)
        if session_expired:
            return None, None, None, None, None, None

        profile = state.get('profile', {}) or {}
        first_name = profile.get('firstName', username) if isinstance(profile, dict) else username
        return homework_list, grades_list, notifications_list, first_name, cookies, prs_id

    except Exception as e:
        log(f"[Notify] Error fetching data for {username}: {e}")
        return None, None, None, None, None, None


def _notify_classmates(grade_class, title, body, data=None, exclude_classmate_id=None, exclude_registration_id=None):
    """история доступна одноклассникам и администраторам выбранного класса"""
    if not grade_class:
        return
    conn = get_db_connection()
    if not conn:
        return
    try:
        cursor = conn.cursor(dictionary=True)
        data_json = json_value(data or {})
        notif_type = (data or {}).get('type', 'homework')

        # одноклассники
        cursor.execute(
            "SELECT id FROM classmate_registrations"
            " WHERE grade_class = %s",
            (grade_class,)
        )
        classmate_rows = cursor.fetchall()
        if exclude_classmate_id:
            classmate_rows = [r for r in classmate_rows if r['id'] != exclude_classmate_id]

        for row in classmate_rows:
            try:
                cursor.execute("""
                    INSERT INTO classmate_notification_history
                        (classmate_id, notification_type, title, body, data)
                    VALUES (%s, %s, %s, %s, %s)
                """, (row['id'], notif_type, title, body, data_json))
            except Exception as e:
                log(f"[Classmate] History store error: {e}")

        # админы, они же cf3_registrations
        cursor.execute(
            "SELECT id FROM cf3_registrations"
            " WHERE grade_class = %s",
            (grade_class,)
        )
        admin_rows = cursor.fetchall()
        if exclude_registration_id:
            admin_rows = [r for r in admin_rows if r['id'] != exclude_registration_id]

        for row in admin_rows:
            try:
                cursor.execute("""
                    INSERT INTO cf3_notification_history
                        (registration_id, notification_type, title, body, data)
                    VALUES (%s, %s, %s, %s, %s)
                """, (row['id'], notif_type, title, body, data_json))
            except Exception as e:
                log(f"[Classmate] Admin history store error: {e}")

        conn.commit()
        cursor.close()
        conn.close()

        total = len(classmate_rows) + len(admin_rows)
        if total:
            log(f"[Classmate] Notified {len(classmate_rows)} classmates + {len(admin_rows)} admins in class={grade_class}: {title}")
    except Exception as e:
        log(f"[Classmate] _notify_classmates error: {e}")
    finally:
        conn.close()


def _fetch_chat_threads(cookies, headers):
    try:
        return chat_notifications.fetch_threads(cookies, headers), False
    except chat_notifications.ChatSessionExpired:
        return None, True
    except Exception as exc:
        log(f"[Notify] Chat list unavailable: {type(exc).__name__}")
        return None, False


def _chat_delivery(registration, telegram_info):
    reg_id = registration['id']
    failed = set()
    try:
        raw_map = registration.get('chat_forward_map') or {}
        forward_map = json.loads(raw_map) if isinstance(raw_map, str) else raw_map
        if not isinstance(forward_map, dict):
            forward_map = {}
    except (ValueError, TypeError):
        forward_map = {}

    def deliver(event, completed):
        targets = {'history': lambda: save_notification_history(
            reg_id, 'message', event['title'], event['body'], event['data'])}
        if (telegram_info.get('telegram_enabled') and telegram_info.get('telegram_bot_token')
                and telegram_info.get('telegram_delivery_primary', True)):
            bot_token = telegram_info['telegram_bot_token']
            user_id = telegram_info.get('telegram_user_id')
            if user_id:
                targets[f'telegram:{user_id}'] = lambda: send_telegram_message(
                    bot_token, user_id, event['title'], event['body'],
                    notification_type='message', notification_data=event.get('telegram'),
                )
            group_id = telegram_info.get('telegram_group_chat_id')
            thread_key = event['data']['id']
            if telegram_info.get('telegram_group_enabled') and group_id and thread_key in forward_map:
                raw_topic = forward_map[thread_key]
                topic_id = chat_notifications.positive_id(raw_topic)
                if raw_topic is None or raw_topic == 0 or topic_id is not None:
                    targets[f'telegram:{group_id}:{topic_id or 0}'] = lambda: send_telegram_message(
                        bot_token, group_id, event['title'], event['body'],
                        message_thread_id=topic_id,
                        notification_type='message', notification_data=event.get('telegram'),
                    )
        for key, send in targets.items():
            if key in completed or key in failed:
                continue
            try:
                if send():
                    completed.add(key)
            except Exception as exc:
                log(f"[Notify] Chat delivery failed: {type(exc).__name__}")
            if key not in completed:
                # сбой телеграма не мешает сохранению следующих событий, но порядок внутри канала сохраняем
                failed.add(key)
        return targets.keys() <= completed, completed

    return deliver


def _check_chat_updates(registration, threads, cookies, prs_id):
    reg_id = registration['id']
    last_check = registration.get('last_check_at')
    previous_check_ms = None
    if isinstance(last_check, datetime):
        last_check = last_check if last_check.tzinfo else last_check.replace(tzinfo=timezone.utc)
        previous_check_ms = int(last_check.timestamp() * 1000)
    state = chat_notifications.load_state(
        registration.get('last_notification_ids'), threads or [], previous_check_ms=previous_check_ms,
    )
    conn = get_db_connection()
    if not conn:
        return
    cursor = conn.cursor()

    def persist():
        cursor.execute(
            'UPDATE cf3_registrations SET last_notification_ids = %s WHERE id = %s',
            (json.dumps(state, ensure_ascii=False), reg_id),
        )
        conn.commit()

    try:
        # сохраняем границу перехода со старой версии даже при временном сбое списка бесед
        persist()
        if threads is None:
            return
        telegram_info = get_telegram_info(reg_id)
        if telegram_info is None:
            log('[Notify] Chat delivery settings unavailable, postponing check')
            return
        for thread in threads:
            key = str(thread['id'])
            checkpoint = state['threads'].setdefault(key, {'after_date': state['started_at']})
            latest = chat_notifications.positive_id(thread.get('msgNum'))
            if latest is not None and latest == checkpoint.get('cursor'):
                continue
            deliver = _chat_delivery(registration, telegram_info)
            try:
                chat_notifications.poll_thread(
                    cookies, _build_api_headers(), thread, prs_id, checkpoint,
                    deliver, persist,
                )
            except chat_notifications.ChatSessionExpired:
                mark_account_session_invalid(reg_id, registration['username'], 'session_expired', notify=True)
                return
            except (chat_notifications.ChatFetchError, requests.RequestException) as exc:
                log(f"[Notify] Chat history deferred for thread {key}: {type(exc).__name__}")
    finally:
        try:
            cursor.close()
        finally:
            conn.close()


def check_user_for_updates(registration):
    conn = get_db_connection()
    if not conn:
        return
    cursor = conn.cursor(dictionary=True)
    try:
        # разные процессы сервера не должны одновременно рассылать одну переписку
        cursor.execute(
            'SELECT pg_try_advisory_xact_lock(hashtextextended(%s, 0)) AS locked',
            (f"cf3-check:{registration['id']}",),
        )
        locked = cursor.fetchone()
        if not locked or not locked['locked']:
            return
        cursor.execute(f'''
            SELECT id, username, password_encrypted AS password, 
                   grade_class, check_interval_minutes, last_homework_ids, last_grade_ids,
                   last_notification_ids, chat_forward_map, session_invalid, last_check_at
            FROM cf3_registrations
            WHERE id = %s AND COALESCE(session_invalid, FALSE) = FALSE
              AND {CHECK_IS_DUE_SQL}
        ''', (registration['id'],))
        current = cursor.fetchone()
        if current:
            try:
                _check_user_for_updates(current)
            finally:
                # сохраняем задержку и после временного сбоя: диапазон относится
                # ко всем попыткам, а не только к успешным проверкам
                schedule_next_check(cursor, current['id'])
                conn.commit()
    except Exception as exc:
        log(f"[Notify] User check failed: {type(exc).__name__}")
    finally:
        try:
            cursor.close()
        finally:
            # откат освобождает блокировку перед возвратом соединения в пул
            try:
                conn.rollback()
            finally:
                conn.close()


def _check_user_for_updates(registration):
    """при изменении дневника сохраняем историю и уведомляем телеграм"""
    reg_id = registration['id']
    username = registration['username']
    encrypted_password = registration['password']

    if registration.get('session_invalid'):
        log(f"[Notify] Skipping invalid session for {username}")
        return

    # id из базы приводим к int, иначе сравнение соврёт
    def parse_id_set(json_str):
        """приводим строку json к множеству целых чисел"""
        try:
            ids = json.loads(json_str) if json_str else []
            return {int(i) for i in ids if i is not None}
        except (json.JSONDecodeError, ValueError, TypeError):
            return set()

    last_homework_ids = parse_id_set(registration.get('last_homework_ids'))
    last_grade_ids = parse_id_set(registration.get('last_grade_ids'))

    # хэши контента, по ним ловим изменения
    _conn_hashes = get_db_connection()
    stored_hw_hashes = {}
    stored_grade_hashes = {}
    if _conn_hashes:
        stored_hw_hashes = _load_item_hashes(_conn_hashes, reg_id, 'homework')
        stored_grade_hashes = _load_item_hashes(_conn_hashes, reg_id, 'grade')
        _conn_hashes.close()

    log(f"[Notify] Checking user: {username}")

    cookies = None
    prs_id = None
    homework_list = grades_list = notifications_list = None

    # сначала пробуем переиспользовать сессию, поднятую keep alive
    session_cookies = get_session(reg_id)
    if session_cookies:
        homework_list, grades_list, notifications_list, _, session_expired, prs_id = fetch_data_with_session(session_cookies, username)
        if homework_list is not None:
            cookies = session_cookies
        elif session_expired:
            mark_account_session_invalid(reg_id, username, "session_expired", notify=True)
            return
        elif not session_expired:
            log(f"[Notify] Session fetch failed (non-401) for {username}, skipping check")
            return

    # полный вход делаем, только если переиспользовать было нечего,
    # если сессия протухла, аккаунт выше ставится на паузу и в eSchool
    # мы больше не ходим, пока пользователь заново не войдёт из приложения
    if homework_list is None:
        password = decrypt_password(encrypted_password)
        if not password:
            log(f"[Notify] Failed to decrypt password for {username}")
            return

        log(f"[Notify] Re-logging in for {username}")
        homework_list, grades_list, notifications_list, _, cookies, prs_id = login_and_get_data(username, password)

        if homework_list is None:
            log(f"[Notify] Failed to fetch data for {username}")
            return

        update_session(reg_id, cookies)
        send_telegram_relogin_notice(reg_id, username)

    # ищем новое и изменившееся домашнее задание
    current_hw_ids = {int(hw['id']) for hw in homework_list if hw.get('id') is not None}
    new_hw_ids = current_hw_ids - last_homework_ids

    # считаем свежие хэши и находим домашнее задание, у которого id тот же, а содержимое другое
    current_hw_hashes = {}
    changed_hw = []
    for hw in homework_list:
        if hw.get('id') is None:
            continue
        hw_id_str = str(hw['id'])
        current_hw_hashes[hw_id_str] = _compute_homework_hash(hw)
        if int(hw['id']) not in new_hw_ids and hw_id_str in stored_hw_hashes:
            if stored_hw_hashes[hw_id_str] != current_hw_hashes[hw_id_str]:
                changed_hw.append(hw)

    log(f"[Notify] HW Check: Current={len(current_hw_ids)}, Last={len(last_homework_ids)}, New={len(new_hw_ids)}, Changed={len(changed_hw)}")

    lpart_headers = _build_api_headers() if cookies and prs_id else None
    telegram_attachment_headers = _build_api_headers() if cookies else None
    if hasattr(cookies, "get_dict"):
        telegram_attachment_cookies = cookies.get_dict()
    elif isinstance(cookies, dict):
        telegram_attachment_cookies = cookies
    else:
        telegram_attachment_cookies = None

    def _hw_notification_payload(hw, title_prefix):
        """вложения к домашнему заданию получаем сейчас, пока школьная сессия действует"""
        tg_attachments = hw.get('attachments', [])
        if not isinstance(tg_attachments, list):
            tg_attachments = []
        if not tg_attachments and hw.get('hasFiles') and hw.get('partId') and cookies and prs_id and lpart_headers:
            detail = _fetch_lpart_detail(cookies, prs_id, hw['partId'], lpart_headers)
            if detail:
                tg_attachments = _extract_lpart_attachments(detail)
                hw['attachments'] = tg_attachments
        if tg_attachments:
            tg_attachments = tg_attachments[:_MAX_TELEGRAM_HOMEWORK_ATTACHMENTS]
        hw_date = _format_notify_date(hw.get('date'))
        hw_preview = hw.get('text', '') or ''
        body_lines = [f"Дата: {hw_date}"]
        if hw_preview:
            body_lines.append(f"{hw_preview}{' 📎' if hw.get('hasFiles') else ''}")
        elif hw.get('hasFiles'):
            body_lines.append('[Прикреплены файлы]')
        hw_data = {'type': 'homework', 'id': str(hw['id'])}
        hw_subject_id = _normalize_key(hw.get('subjectId'))
        if hw_subject_id is not None:
            hw_data['subjectId'] = str(hw_subject_id)
        date_ms = hw.get('date')
        if date_ms:
            hw_data['date'] = school_date(date_ms)
        if hw.get('subject'):
            hw_data['subject'] = hw['subject']
        return {
            'title': f"{title_prefix}{hw.get('subject', 'Предмет')}",
            'body': "\n".join(body_lines),
            'data': hw_data,
            'attachments': tg_attachments,
        }

    def _send_hw_notification(hw, title_prefix, notice=None):
        notice = notice or _hw_notification_payload(hw, title_prefix)
        send_notification_with_telegram(

            notice['title'],
            notice['body'],
            notice['data'],
            registration_id=reg_id,
            notification_type='homework',
            telegram_attachments=notice['attachments'],
            telegram_attachment_headers=telegram_attachment_headers,
            telegram_attachment_cookies=telegram_attachment_cookies,

        )

    def _handle_hw(hw, title_prefix):
        """уведомление о домашнем задании ждёт разбор, если он включён"""
        notice = _hw_notification_payload(hw, title_prefix)
        subject = hw.get('subject', 'Предмет')
        hw_text = hw.get('text', '') or ''
        date_ms = hw.get('date')
        date_iso = school_date(date_ms) if date_ms else None
        grade_class = registration.get('grade_class')
        class_data = {'type': 'homework', 'id': str(hw.get('id', '')),
                      'date': date_iso, 'subject': subject}

        analysis_id = None
        if analysis.is_enabled() and hw_text.strip() and grade_class:
            conn = get_db_connection()
            if conn:
                try:
                    analysis_id, is_new = analysis.enqueue(
                        conn, grade_class, subject, date_iso, hw_text, 'teacher', hw.get('id'),
                        attachments=notice['attachments'],
                        attachment_headers=telegram_attachment_headers,
                        # при скачивании для разбора сохраняем домен и путь куки; словарь нужен только для сохранённой отправки в телеграм
                        attachment_cookies=cookies)
                    if analysis_id:
                        analysis.add_pending(
                            conn, analysis_id, 'registration',
                            notice['title'], notice['body'], notice['data'],
                            payload={


                                'notification_type': 'homework',
                                'telegram_attachments': notice['attachments'],
                                'telegram_attachment_headers': telegram_attachment_headers,
                                'telegram_attachment_cookies': telegram_attachment_cookies,
                            },
                            registration_id=reg_id)
                        # одноклассникам шлём один раз на класс, а не от каждой регистрации
                        if is_new:
                            analysis.add_pending(
                                conn, analysis_id, 'class',
                                f"{title_prefix}{subject}", hw_text[:120], class_data,
                                grade_class=grade_class, exclude_registration_id=reg_id)
                        cached = analysis.load(analysis_id)
                        if cached and cached.get('status') in ('done', 'failed'):
                            analysis.flush(analysis_id)
                except Exception as e:
                    log(f"[Notify] Не удалось поставить разбор в очередь: {e}")
                    analysis_id = None
                finally:
                    conn.close()

        if analysis_id:
            return
        _send_hw_notification(hw, title_prefix, notice)
        _notify_classmates(grade_class, f"{title_prefix}{subject}", hw_text[:120], class_data)

    if new_hw_ids:
        log(f"[Notify] New HW IDs: {new_hw_ids}")
        new_hw = [hw for hw in homework_list if hw.get('id') is not None and int(hw['id']) in new_hw_ids]
        for hw in new_hw[:3]:
            _handle_hw(hw, "📚 ДЗ: ")
        log(f"[Notify] Sent {min(len(new_hw), 3)} new homework notifications for {username}")

    if changed_hw:
        log(f"[Notify] Changed HW IDs: {[hw['id'] for hw in changed_hw]}")
        for hw in changed_hw[:3]:
            _handle_hw(hw, "✏️ ДЗ изменено: ")
        log(f"[Notify] Sent {min(len(changed_hw), 3)} changed homework notifications for {username}")

    # ищем новые и изменившиеся оценки
    current_grade_ids = {int(g['id']) for g in grades_list if g.get('id') is not None}
    new_grade_ids = current_grade_ids - last_grade_ids

    # считаем свежие хэши для оценок
    current_grade_hashes = {}
    changed_grades = []
    for g in grades_list:
        if g.get('id') is None:
            continue
        g_id_str = str(g['id'])
        current_grade_hashes[g_id_str] = _compute_grade_hash(g)
        if int(g['id']) not in new_grade_ids and g_id_str in stored_grade_hashes:
            if stored_grade_hashes[g_id_str] != current_grade_hashes[g_id_str]:
                changed_grades.append(g)

    log(f"[Notify] Grade Check: Current={len(current_grade_ids)}, Last={len(last_grade_ids)}, New={len(new_grade_ids)}, Changed={len(changed_grades)}")

    def _send_grade_notification(g, title_prefix):
        grade_value = g.get('value', '?')
        subject = g.get('subject', 'Предмет')
        grade_date = _format_notify_date(g.get('date'))
        grade_reason = g.get('reason') or g.get('partType') or 'Оценка'
        grade_weight = _format_notify_weight(g.get('weight'))
        grade_body = (
            f"{subject}\n"
            f"Дата: {grade_date}\n"
            f"За что: {grade_reason}\n"
            f"Коэффициент: {grade_weight}"
        )
        grade_data = {'type': 'grade', 'id': str(g['id']), 'value': grade_value}
        grade_subject_id = _normalize_key(g.get('subjectId'))
        if grade_subject_id is not None:
            grade_data['subjectId'] = str(grade_subject_id)
        send_notification_with_telegram(

            f"{title_prefix}{grade_value}",
            grade_body,
            grade_data,
            registration_id=reg_id,
            notification_type='grade',

        )

    if new_grade_ids:
        log(f"[Notify] New Grade IDs: {new_grade_ids}")
        new_grades = [g for g in grades_list if g.get('id') is not None and int(g['id']) in new_grade_ids]
        for g in new_grades[:5]:
            _send_grade_notification(g, "📝 Оценка: ")
        log(f"[Notify] Sent {min(len(new_grades), 5)} new grade notifications for {username}")

    if changed_grades:
        log(f"[Notify] Changed Grade IDs: {[g['id'] for g in changed_grades]}")
        for g in changed_grades[:3]:
            _send_grade_notification(g, "✏️ Оценка изменена: ")
        log(f"[Notify] Sent {min(len(changed_grades), 3)} changed grade notifications for {username}")

    _check_chat_updates(registration, notifications_list, cookies, prs_id)

    # карту предметов собираем из текущих данных (id → имя) и мержим с сохранённой
    new_subject_map = {}
    for hw in homework_list:
        sid = _normalize_key(hw.get('subjectId'))
        name = hw.get('subject')
        if sid is not None and name:
            new_subject_map[str(sid)] = name
    for g in grades_list:
        sid = _normalize_key(g.get('subjectId'))
        name = g.get('subject')
        if sid is not None and name:
            new_subject_map[str(sid)] = name

    # состояния сообщений уже сохранены отдельно, здесь обновляем дневник
    conn = get_db_connection()
    if conn:
        try:
            cursor = conn.cursor()
            # свежие предметы подмешиваем к known_subjects
            if new_subject_map:
                cursor.execute("SELECT known_subjects FROM cf3_registrations WHERE id = %s", (reg_id,))
                row = cursor.fetchone()
                existing = {}
                if row and row[0]:
                    try:
                        existing = json.loads(row[0])
                    except Exception:
                        existing = {}
                existing.update(new_subject_map)
                known_subjects_json = json.dumps(existing, ensure_ascii=False)
            else:
                known_subjects_json = None

            if known_subjects_json:
                cursor.execute("""
                    UPDATE cf3_registrations
                    SET last_check_at = NOW(),
                        last_homework_ids = %s,
                        last_grade_ids = %s,
                        known_subjects = %s
                    WHERE id = %s
                """, (
                    json.dumps([int(i) for i in current_hw_ids]),
                    json.dumps([int(i) for i in current_grade_ids]),
                    known_subjects_json,
                    reg_id
                ))
            else:
                cursor.execute("""
                    UPDATE cf3_registrations
                    SET last_check_at = NOW(),
                        last_homework_ids = %s,
                        last_grade_ids = %s
                    WHERE id = %s
                """, (
                    json.dumps([int(i) for i in current_hw_ids]),
                    json.dumps([int(i) for i in current_grade_ids]),
                    reg_id
                ))
            conn.commit()
            # сохраняем хэши, по ним потом ловим изменения
            _save_item_hashes(conn, reg_id, 'homework', current_hw_hashes)
            _save_item_hashes(conn, reg_id, 'grade', current_grade_hashes)
            conn.commit()
            cursor.close()
            conn.close()
            log(f"[Notify] Updated state for {username}: HW={len(current_hw_ids)}, Grades={len(current_grade_ids)}")
        except Exception as e:
            log(f"[Notify] Error updating registration: {e}")


def notification_monitor_loop():
    """проверяем регистрации в фоновом цикле"""
    global _monitor_running
    log("[Notify] Monitor loop started")

    while _monitor_running:
        try:
            conn = get_db_connection()
            if not conn:
                time.sleep(60)
                continue

            cursor = conn.cursor(dictionary=True)

            # выбираем регистрации, которые пора проверить
            cursor.execute(f"""
                SELECT id, username, password_encrypted as password, 
                       grade_class, check_interval_minutes, last_homework_ids, last_grade_ids,
                       last_notification_ids, chat_forward_map, session_invalid
                FROM cf3_registrations
                WHERE COALESCE(session_invalid, FALSE) = FALSE
                  AND {CHECK_IS_DUE_SQL}
                ORDER BY next_check_at NULLS FIRST, last_check_at NULLS FIRST
                LIMIT 10
            """)
            registrations = cursor.fetchall()
            cursor.close()
            conn.close()

            for reg in registrations:
                if not _monitor_running:
                    break
                check_user_for_updates(reg)
                time.sleep(2)

        except Exception as e:
            log(f"[Notify] Monitor loop error: {e}")

        # минуту спим и идём на новый круг
        for _ in range(60):
            if not _monitor_running:
                break
            time.sleep(1)

    log("[Notify] Monitor loop stopped")


def start_notification_monitor():
    """запускаем поток мониторинга"""
    global _monitor_thread, _monitor_running

    if _monitor_thread and _monitor_thread.is_alive():
        log("[Notify] Monitor already running")
        return

    _monitor_running = True
    _monitor_thread = threading.Thread(target=notification_monitor_loop, daemon=True)
    _monitor_thread.start()
    log("[Notify] Monitor thread started")

    # поднимаем всех телеграм ботов
    restart_all_telegram_bots()
    from ..cloud_access import restart_server_bot
    restart_server_bot()


def stop_notification_monitor():
    """останавливаем поток мониторинга"""
    global _monitor_running
    _monitor_running = False
    log("[Notify] Monitor stop requested")


@bp.route('/config', methods=['GET'])
def cf3_config():
    """отдаём настройки мониторинга"""
    return jsonify({
        "minCheckIntervalMinutes": MIN_CHECK_INTERVAL,
        "defaultCheckIntervalMinutes": DEFAULT_CHECK_INTERVAL,
        "cloudProtocolVersion": 2,
        **current_domain_status(),
        **tls_status(),
    })


@bp.route('/server-domain', methods=['GET', 'POST'])
def cf3_server_domain():
    """читаем или меняем публичный домен https сервера"""
    if request.method == 'GET':
        return jsonify(current_domain_status())

    data = request.json or {}
    domain = data.get('domain')
    job = start_domain_job(
        domain,
        admin_url=os.getenv("CADDY_ADMIN_URL", "http://caddy:2019"),
    )
    return jsonify(job), 202


@bp.route('/server-domain/status/<job_id>', methods=['GET'])
def cf3_server_domain_job(job_id):
    """показываем текущее состояние настройки домена https"""
    job = get_domain_job(job_id)
    if not job:
        return jsonify({"error": "Domain setup job not found"}), 404
    return jsonify(job)


@bp.route('/ip-blacklist', methods=['GET', 'POST'])
def cf3_ip_blacklist():
    """читаем или заменяем список заблокированных адресов и подсетей"""
    if request.method == 'GET':
        return jsonify({"entries": get_ip_blacklist()})

    data = request.json or {}
    entries = data.get('entries')
    if entries is None:
        entries = []
    if not isinstance(entries, list):
        return jsonify({"error": "entries must be a list"}), 400

    updated, error = set_ip_blacklist(entries)
    if error:
        return jsonify({"error": error}), 400
    return jsonify({"entries": updated})


@bp.route('/register', methods=['POST'])
@rate_limit('notification_register')
def cf3_register():
    """подтверждаем пользователя кодом или прежним токеном, затем сверяем prs_id при входе по паролю"""
    data = request.json or {}

    token = data.get('token')
    verification_code = data.get('verificationCode') or data.get('code')
    verification_thread_id = data.get('verificationThreadId') or data.get('threadId')
    device_name = data.get('deviceName', 'Unknown device')
    username = data.get('username')
    password = data.get('password')
    check_interval = data.get('checkIntervalMinutes', DEFAULT_CHECK_INTERVAL)

    if not username or not password:
        return jsonify({"error": "Missing required fields"}), 400

    if check_interval < MIN_CHECK_INTERVAL:
        check_interval = MIN_CHECK_INTERVAL

    verified_prs_id = None
    verification_token = token

    # шаг 1: сперва пробуем код, присланный прямо в запросе
    if verification_code:
        log("[Notify] Checking inline verification")
        verified_prs_id, verification_error = find_verified_sender(verification_code, verification_thread_id)

        if verification_error == "Server not authenticated":
            return jsonify({"error": verification_error}), 503

        if not verified_prs_id:
            return jsonify({"error": verification_error or "Verification failed"}), 401

        log(f"[Notify] Message verification succeeded for prs_id: {verified_prs_id}")

    # шаг 2: кода нет, значит смотрим на сохранённый токен подтверждения
    if not verified_prs_id and not verification_token:
        return jsonify({"error": "Verification token required"}), 401

    if not verified_prs_id:
        conn = get_db_connection()
        if not conn:
            return jsonify({"error": "Database connection failed"}), 500

        try:
            cursor = conn.cursor()
            cursor.execute("SELECT prs_id FROM verified_users WHERE token = %s", (verification_token,))
            row = cursor.fetchone()
            cursor.close()
            conn.close()

            if not row:
                log("[Notify] Invalid verification token")
                return jsonify({"error": "Invalid or expired verification token"}), 401

            verified_prs_id = row[0]
            log(f"[Notify] Token verified for prs_id: {verified_prs_id}")

        except Exception as e:
            log(f"[Notify] Token verification error: {type(e).__name__}")
            return jsonify({"error": "Database error"}), 500

    # шаг 3: поднимаем шифрование
    if not init_encryption():
        return jsonify({"error": "Encryption not available"}), 500

    # шаг 4: проверяем креды настоящим входом в eSchool
    hw, grades, notifications, name, cookies, login_prs_id = login_and_get_data(username, password)
    if hw is None:
        return jsonify({"error": "Invalid credentials or login failed"}), 401

    # шаг 5: сверяем, что prs_id вошедшего совпадает с подтверждённым
    if type(login_prs_id) is not int or login_prs_id <= 0 or login_prs_id != verified_prs_id:
        log(f"[Notify] prs_id mismatch! Verified: {verified_prs_id}, Login: {login_prs_id}")
        return jsonify({"error": "Account does not match verified user"}), 403

    # имя спрашиваем у eSchool, а класс присылает клиент: чужой класс по prsId не отдают
    normalized_full_name = get_verified_name(login_prs_id, cookies)
    normalized_grade_class = normalize_grade_class(data.get('gradeClass'))
    if not normalized_full_name:
        return jsonify({"error": "Authenticated account profile unavailable"}), 503

    # пароль перед сохранением шифруем
    encrypted_password = encrypt_password(password)
    if not encrypted_password:
        return jsonify({"error": "Encryption failed"}), 500

    if verification_code:
        # запрос профиля выше не трогает подтверждение, живущее в контексте запроса flask,
        # гасим его только после того, как прошли и креды, и профиль
        verification_token, save_error = issue_verification_token(
            verified_prs_id, device_name, None, normalized_grade_class
        )
        if not verification_token:
            return jsonify({"error": save_error or "Verification storage failed"}), 500

    registration_id = str(uuid.uuid4())
    registration_secret = secrets.token_urlsafe(32)
    registration_secret_hash = _hash_registration_secret(registration_secret)

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor()

        initial_notification_state = chat_notifications.initial_state(notifications or [])

        # заводим регистрацию с зашифрованным паролем,
        # id домашнего задания и оценок кладём списками чисел, уведомления словарём
        cursor.execute("""
	            INSERT INTO cf3_registrations (
	                id, username, full_name, grade_class, password_encrypted, check_interval_minutes,
	                verification_token, registration_secret_hash, last_homework_ids, last_grade_ids,
	                last_notification_ids
	            )
	            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
	        """, (
	            registration_id,
	            username,
	            normalized_full_name,
	            normalized_grade_class,
	            encrypted_password,

	            check_interval,
	            verification_token,
	            registration_secret_hash,
	            json.dumps([int(hw_item['id']) for hw_item in (hw or []) if hw_item.get('id') is not None]),
	            json.dumps([int(g['id']) for g in (grades or []) if g.get('id') is not None]),
	            json.dumps(initial_notification_state)
        ))
        # этот токен тоже освежаем: авторизация домашнего задания читает его закэшированную область
        cursor.execute("""
            UPDATE verified_users SET full_name = %s, grade_class = %s
            WHERE token = %s AND prs_id = %s
        """, (normalized_full_name, normalized_grade_class, verification_token, login_prs_id))
        conn.commit()

        # сразу сохраняем хэши, иначе первая же проверка решит, что всё поменялось
        initial_hw_hashes = {
            str(hw_item['id']): _compute_homework_hash(hw_item)
            for hw_item in (hw or []) if hw_item.get('id') is not None
        }
        initial_grade_hashes = {
            str(g['id']): _compute_grade_hash(g)
            for g in (grades or []) if g.get('id') is not None
        }
        _save_item_hashes(conn, registration_id, 'homework', initial_hw_hashes)
        _save_item_hashes(conn, registration_id, 'grade', initial_grade_hashes)
        conn.commit()

        cursor.close()
        conn.close()

        hw_count = len([h for h in (hw or []) if h.get('id') is not None])
        grades_count = len([g for g in (grades or []) if g.get('id') is not None])
        msg_count = len(initial_notification_state['threads'])
        log(f"[Notify] Registered user: {username} (interval: {check_interval}min, HW={hw_count}, Grades={grades_count}, Msgs={msg_count})")

        # обновляем сессию keep alive
        update_session(registration_id, cookies)

        return jsonify({
            "success": True,
            "registrationId": registration_id,
            "registrationSecret": registration_secret
        })

    except Exception as e:
        log(f"[Notify] Registration error: {type(e).__name__}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/unregister', methods=['POST'])
@rate_limit('devices')
def cf3_unregister():
    """отключаем регистрацию от фонового мониторинга"""
    data = request.json
    registration_id = data.get('registrationId')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("DELETE FROM cf3_registrations WHERE id = %s", (registration_id,))
        rows_affected = cursor.rowcount
        conn.commit()
        cursor.close()
        conn.close()
        invalidate_registration(registration_id)

        if rows_affected > 0:
            log(f"[Notify] Unregistered: {registration_id}")
            return jsonify({"success": True})
        else:
            return jsonify({"success": True, "message": "Registration not found"})

    except Exception as e:
        log(f"[Notify] Unregister error: {e}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/update-interval', methods=['POST'])
@rate_limit('devices')
def cf3_update_interval():
    """меняем интервал проверок регистрации"""
    data = request.get_json(silent=True)
    if not isinstance(data, dict) or not data.get('registrationId'):
        return jsonify(error='Не указана регистрация'), 400
    registration_id = data['registrationId']
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error
    try:
        check_interval, maximum = parse_check_interval(data, MIN_CHECK_INTERVAL)
    except ValueError as exc:
        return jsonify(error=str(exc)), 400

    conn = get_db_connection()
    if not conn:
        return jsonify(error='База данных недоступна'), 503
    cursor = conn.cursor()
    try:
        cursor.execute("""
            UPDATE cf3_registrations
            SET check_interval_minutes = %s, check_interval_max_minutes = %s
            WHERE id = %s
        """, (check_interval, maximum, registration_id))
        if cursor.rowcount == 0:
            return jsonify(error='Регистрация не найдена'), 404
        schedule_next_check(cursor, registration_id)
        conn.commit()
        return jsonify(success=True, checkIntervalMinutes=check_interval,
                       checkIntervalMaxMinutes=maximum)
    except Exception as exc:
        conn.rollback()
        log(f"[Notify] Update interval error: {type(exc).__name__}")
        return jsonify(error='Не удалось сохранить интервал'), 500
    finally:
        cursor.close()
        conn.close()


@bp.route('/notification-history', methods=['POST'])
@rate_limit('devices')
def cf3_notification_history():
    """отдаём историю регистрации или одноклассника"""
    from flask import g as _g
    data = request.json or {}
    try:
        limit = max(1, min(200, int(data.get('limit', 50))))
        offset = max(0, int(data.get('offset', 0)))
    except (TypeError, ValueError):
        return jsonify({"error": "Invalid limit or offset"}), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)

        # одноклассник: смотрим classmate_notification_history по classmate_id из авторизации
        if getattr(_g, 'is_classmate', False) and not getattr(_g, 'cloud_registration_id', None):
            classmate_id = _g.classmate_id
            cursor.execute("""
                SELECT id, notification_type, title, body, data, sent_at
                FROM classmate_notification_history
                WHERE classmate_id = %s
                ORDER BY sent_at DESC
                LIMIT %s OFFSET %s
            """, (classmate_id, limit, offset))
            notifications = []
            for row in cursor.fetchall():
                notifications.append({
                    "id": row['id'],
                    "type": row['notification_type'],
                    "title": row['title'],
                    "body": row['body'],
                    "data": row['data'],
                    "sentAt": row['sent_at'].isoformat() if row['sent_at'] else None
                })
            cursor.execute(
                "SELECT COUNT(*) as total FROM classmate_notification_history WHERE classmate_id = %s",
                (classmate_id,)
            )
            total = cursor.fetchone()['total']
            cursor.close()
            conn.close()
            return jsonify({"notifications": notifications, "total": total, "limit": limit, "offset": offset})

        # админ: смотрим cf3_notification_history по registrationId
        registration_id = data.get('registrationId')
        if not registration_id:
            cursor.close(); conn.close()
            return jsonify({"error": "No registrationId provided"}), 400
        owner_error = _require_registration_owner(registration_id, data)
        if owner_error:
            cursor.close(); conn.close()
            return owner_error

        cursor.execute("SELECT id FROM cf3_registrations WHERE id = %s", (registration_id,))
        if not cursor.fetchone():
            cursor.close()
            conn.close()
            return jsonify({"error": "Registration not found"}), 404

        cursor.execute("""
            SELECT id, notification_type, title, body, data, sent_at
            FROM cf3_notification_history
            WHERE registration_id = %s
            ORDER BY sent_at DESC
            LIMIT %s OFFSET %s
        """, (registration_id, limit, offset))

        notifications = []
        for row in cursor.fetchall():
            notifications.append({
                "id": row['id'],
                "type": row['notification_type'],
                "title": row['title'],
                "body": row['body'],
                "data": row['data'],
                "sentAt": row['sent_at'].isoformat() if row['sent_at'] else None
            })

        cursor.execute("""
            SELECT COUNT(*) as total FROM cf3_notification_history WHERE registration_id = %s
        """, (registration_id,))
        total = cursor.fetchone()['total']

        cursor.close()
        conn.close()

        return jsonify({
            "notifications": notifications,
            "total": total,
            "limit": limit,
            "offset": offset
        })

    except Exception as e:
        log(f"[Notify] Notification history error: {e}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/update-telegram', methods=['POST'])
@rate_limit('devices')
def cf3_update_telegram():
    """сохраняем настройки телеграма для регистрации"""
    data = request.json
    registration_id = data.get('registrationId')
    telegram_enabled = data.get('telegramEnabled', False)
    telegram_bot_token = data.get('telegramBotToken')
    telegram_user_id = data.get('telegramUserId')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)

        # текущая регистрация
        cursor.execute("""
            SELECT id, telegram_bot_token FROM cf3_registrations WHERE id = %s
        """, (registration_id,))
        reg = cursor.fetchone()

        if not reg:
            cursor.close()
            conn.close()
            return jsonify({"error": "Registration not found"}), 404

        stored_bot_token = reg.get('telegram_bot_token')
        final_bot_token = (telegram_bot_token or stored_bot_token) if telegram_enabled else None
        final_user_id = telegram_user_id if telegram_enabled else None

        if telegram_enabled:
            if not final_bot_token or not final_user_id:
                cursor.close()
                conn.close()
                return jsonify({"error": "Telegram bot token and user ID are required when Telegram is enabled"}), 400
            if ':' not in final_bot_token:
                cursor.close()
                conn.close()
                return jsonify({"error": "Invalid Telegram bot token format"}), 400

        # обновляем настройки телеграма, токен бота только на запись: если его не прислали, оставляем сохранённый
        cursor.execute("""
            UPDATE cf3_registrations
            SET telegram_enabled = %s,
                telegram_bot_token = %s,
                telegram_user_id = %s
            WHERE id = %s
        """, (telegram_enabled, final_bot_token, final_user_id, registration_id))
        conn.commit()
        cursor.close()
        conn.close()

        # поднимаем или гасим бота
        if telegram_enabled and final_bot_token and final_user_id:
            start_telegram_bot(registration_id, final_bot_token, final_user_id)
            log(f"[Notify] Telegram enabled for {registration_id}")
        else:
            from ..cloud_access import account_primary
            stop_telegram_bot(account_primary(registration_id))
            log(f"[Notify] Telegram disabled for {registration_id}")

        return jsonify({"success": True})

    except Exception as e:
        log(f"[Notify] Update Telegram error: {e}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/test-telegram', methods=['POST'])
@rate_limit('devices')
def cf3_test_telegram():
    """отправляем проверочное сообщение в телеграм"""
    data = request.json
    telegram_bot_token = data.get('telegramBotToken')
    telegram_user_id = data.get('telegramUserId')

    if not telegram_bot_token or not telegram_user_id:
        return jsonify({"error": "Bot token and user ID are required"}), 400

    try:
        success = send_telegram_message(
            telegram_bot_token,
            telegram_user_id,
            "Тестовое сообщение",
            "Telegram уведомления работают! Это тестовое сообщение от reSchool."
        )

        if success:
            return jsonify({"success": True})
        else:
            return jsonify({"error": "Failed to send Telegram message"}), 500
    except Exception as e:
        log(f"[Notify] Test Telegram error: {e}")
        return jsonify({"error": str(e)}), 500


@bp.route('/get-telegram-status', methods=['POST'])
@rate_limit('devices')
def cf3_get_telegram_status():
    """показываем состояние подключения телеграма"""
    data = request.json
    registration_id = data.get('registrationId')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT telegram_enabled, telegram_bot_token, telegram_user_id,
                   telegram_group_enabled, telegram_group_chat_id, telegram_group_title,
                   telegram_topic_map
            FROM cf3_registrations WHERE id = %s
        """, (registration_id,))
        reg = cursor.fetchone()
        cursor.close()
        conn.close()

        if not reg:
            return jsonify({"error": "Registration not found"}), 404

        return jsonify({
            "telegramEnabled": bool(reg['telegram_enabled']),
            "telegramBotConfigured": bool(reg['telegram_bot_token']),
            "telegramBotToken": '',
            "telegramUserId": reg['telegram_user_id'] or '',
            "telegramGroupEnabled": bool(reg.get('telegram_group_enabled')),
            "telegramGroupChatId": reg.get('telegram_group_chat_id') or '',
            "telegramGroupTitle": reg.get('telegram_group_title') or '',
            "telegramTopicMap": reg.get('telegram_topic_map') or '{}',
        })

    except Exception as e:
        log(f"[Notify] Get Telegram status error: {e}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/update-telegram-group', methods=['POST'])
@rate_limit('devices')
def cf3_update_telegram_group():
    """меняем группу и привязки её топиков"""
    data = request.json or {}
    registration_id = data.get('registrationId')
    group_enabled = data.get('telegramGroupEnabled', False)
    group_chat_id = data.get('telegramGroupChatId') or None
    group_title = data.get('telegramGroupTitle') or None
    topic_map_raw = data.get('telegramTopicMap')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    # topic_map приводим к строке json
    topic_map_str = None
    if topic_map_raw is not None:
        if isinstance(topic_map_raw, dict):
            try:
                topic_map_str = json.dumps({str(k): int(v) for k, v in topic_map_raw.items()})
            except (ValueError, TypeError) as e:
                return jsonify({"error": f"Invalid topicMap values: {e}"}), 400
        elif isinstance(topic_map_raw, str):
            try:
                parsed = json.loads(topic_map_raw)
                topic_map_str = json.dumps({str(k): int(v) for k, v in parsed.items()})
            except Exception:
                return jsonify({"error": "Invalid topicMap JSON"}), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT id FROM cf3_registrations WHERE id = %s", (registration_id,))
        if not cursor.fetchone():
            cursor.close()
            conn.close()
            return jsonify({"error": "Registration not found"}), 404

        if topic_map_str is not None:
            cursor.execute("""
                UPDATE cf3_registrations
                SET telegram_group_enabled = %s,
                    telegram_group_chat_id = %s,
                    telegram_group_title = %s,
                    telegram_topic_map = %s
                WHERE id = %s
            """, (group_enabled, group_chat_id, group_title, topic_map_str, registration_id))
        else:
            cursor.execute("""
                UPDATE cf3_registrations
                SET telegram_group_enabled = %s,
                    telegram_group_chat_id = %s,
                    telegram_group_title = %s
                WHERE id = %s
            """, (group_enabled, group_chat_id, group_title, registration_id))

        conn.commit()
        cursor.close()
        conn.close()

        log(f"[Notify] Telegram group updated for {registration_id}: enabled={group_enabled}, chatId={group_chat_id}")
        return jsonify({"success": True})

    except Exception as e:
        log(f"[Notify] Update Telegram group error: {e}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/get-group-info', methods=['POST'])
@rate_limit('devices')
def cf3_get_group_info():
    """дополняем сохранённые предметы свежими данными api"""
    data = request.get_json(silent=True, force=True) or {}
    registration_id = data.get('registrationId')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT telegram_group_enabled, telegram_group_chat_id, telegram_group_title,
                   telegram_topic_map, known_subjects,
                   username, password_encrypted
            FROM cf3_registrations WHERE id = %s
        """, (registration_id,))
        reg = cursor.fetchone()
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"[Notify] get-group-info DB error: {e}")
        return jsonify({"error": "Database error"}), 500

    if not reg:
        return jsonify({"error": "Registration not found"}), 404

    topic_map = {}
    if reg.get('telegram_topic_map'):
        try:
            topic_map = json.loads(reg['telegram_topic_map'])
        except Exception:
            pass

    # начинаем с того, что уже сохранено
    subjects = {}
    if reg.get('known_subjects'):
        try:
            subjects = json.loads(reg['known_subjects'])
        except Exception:
            pass

    # дополняем полным списком предметов из api, диапазон дневника берём шире
    try:
        from ..encryption import decrypt_password
        password = decrypt_password(reg['password_encrypted'])
        if password:
            api_subjects, _ = get_subjects_for_user(reg['username'], password)
            if api_subjects:
                for item in api_subjects:
                    sid = str(item.get('id') or '').strip()
                    name = str(item.get('name') or '').strip()
                    if sid and name:
                        subjects[sid] = name
                # обогащённую карту кладём обратно в базу
                conn2 = get_db_connection()
                if conn2:
                    try:
                        cur2 = conn2.cursor()
                        cur2.execute(
                            "UPDATE cf3_registrations SET known_subjects = %s WHERE id = %s",
                            (json.dumps(subjects, ensure_ascii=False), registration_id)
                        )
                        conn2.commit()
                        cur2.close()
                        conn2.close()
                    except Exception:
                        pass
    except Exception as e:
        log(f"[Notify] get-group-info subject enrich error: {e}")

    return jsonify({
        "groupEnabled": bool(reg.get('telegram_group_enabled')),
        "groupChatId": reg.get('telegram_group_chat_id') or '',
        "groupTitle": reg.get('telegram_group_title') or '',
        "topicMap": topic_map,
        "subjects": subjects,
    })


@bp.route('/get-subjects', methods=['POST'])
@rate_limit('devices')
def cf3_get_subjects():
    """отдаём предметы, накопленные мониторингом"""
    data = request.json or {}
    registration_id = data.get('registrationId')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT known_subjects FROM cf3_registrations WHERE id = %s", (registration_id,))
        reg = cursor.fetchone()
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"[Notify] get-subjects DB error: {e}")
        return jsonify({"error": "Database error"}), 500

    if not reg:
        return jsonify({"error": "Registration not found"}), 404

    subjects = {}
    raw = reg.get('known_subjects')
    if raw:
        try:
            subjects = json.loads(raw)
        except Exception:
            subjects = {}

    # subjects это {subjectId: subjectName}
    subject_list = [{"id": k, "name": v} for k, v in subjects.items()]
    subject_list.sort(key=lambda x: x['name'])
    return jsonify({"subjects": subject_list})


@bp.route('/get-chat-forward', methods=['POST'])
@rate_limit('devices')
def cf3_get_chat_forward():
    """читаем привязки бесед к топикам регистрации"""
    data = request.get_json(silent=True, force=True) or {}
    registration_id = data.get('registrationId')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT chat_forward_map FROM cf3_registrations WHERE id = %s", (registration_id,))
        reg = cursor.fetchone()
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"[Notify] get-chat-forward DB error: {e}")
        return jsonify({"error": "Database error"}), 500

    if not reg:
        return jsonify({"error": "Registration not found"}), 404

    chat_forward_map = {}
    raw = reg.get('chat_forward_map')
    if raw:
        try:
            chat_forward_map = json.loads(raw)
        except Exception:
            pass

    return jsonify({"chatForwardMap": chat_forward_map})


@bp.route('/update-chat-forward', methods=['POST'])
@rate_limit('devices')
def cf3_update_chat_forward():
    """сохраняем привязки бесед к топикам, null означает общий чат"""
    data = request.get_json(silent=True, force=True) or {}
    registration_id = data.get('registrationId')
    raw_map = data.get('chatForwardMap')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    if raw_map is None:
        return jsonify({"error": "No chatForwardMap provided"}), 400

    if not isinstance(raw_map, dict):
        return jsonify({"error": "chatForwardMap must be an object"}), 400

    # проверяем и приводим к виду: ключи это строковые threadId, значения целые topicId или пусто
    try:
        normalised = {}
        for k, v in raw_map.items():
            normalised[str(int(k))] = int(v) if v is not None else None
    except (ValueError, TypeError) as e:
        return jsonify({"error": f"Invalid chatForwardMap values: {e}"}), 400

    map_json = json.dumps(normalised)

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT id FROM cf3_registrations WHERE id = %s", (registration_id,))
        if not cursor.fetchone():
            cursor.close()
            conn.close()
            return jsonify({"error": "Registration not found"}), 404

        cursor.execute(
            "UPDATE cf3_registrations SET chat_forward_map = %s WHERE id = %s",
            (map_json, registration_id)
        )
        conn.commit()
        cursor.close()
        conn.close()
        log(f"[Notify] chat_forward_map updated for {registration_id}: {len(normalised)} entries")
        return jsonify({"success": True})
    except Exception as e:
        log(f"[Notify] update-chat-forward DB error: {e}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/request-topic-detect', methods=['POST'])
@rate_limit('devices')
def cf3_request_topic_detect():
    """ждём сообщение п в нужном топике для его определения"""
    data = request.get_json(silent=True, force=True) or {}
    registration_id = data.get('registrationId')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT telegram_group_chat_id FROM cf3_registrations WHERE id = %s",
            (registration_id,)
        )
        reg = cursor.fetchone()
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"[Notify] request-topic-detect DB error: {e}")
        return jsonify({"error": "Database error"}), 500

    if not reg:
        return jsonify({"error": "Registration not found"}), 404

    group_chat_id = reg.get('telegram_group_chat_id') or ''
    if not group_chat_id:
        return jsonify({"error": "No Telegram group connected. Connect a group first."}), 400

    request_topic_detect(registration_id)
    log(f"[Notify] Topic detect started for {registration_id}, group={group_chat_id}")
    return jsonify({"success": True, "groupChatId": group_chat_id})


@bp.route('/poll-detected-topic', methods=['POST'])
@rate_limit('devices')
def cf3_poll_detected_topic():
    """возвращаем найденный топик или null, пока сообщения нет"""
    data = request.get_json(silent=True, force=True) or {}
    registration_id = data.get('registrationId')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    topic_id = get_and_clear_detected_topic(registration_id)
    return jsonify({"topicId": topic_id})


@bp.route('/generate-group-code', methods=['POST'])
@rate_limit('devices')
def cf3_generate_group_code():
    """код активации группы действует пятнадцать минут"""
    data = request.get_json(silent=True, force=True) or {}
    registration_id = data.get('registrationId')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("SELECT id FROM cf3_registrations WHERE id = %s", (registration_id,))
        if not cursor.fetchone():
            cursor.close()
            conn.close()
            return jsonify({"error": "Registration not found"}), 404
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"[Notify] generate-group-code DB error: {e}")
        return jsonify({"error": "Database error"}), 500

    code = create_group_activation_code(registration_id, ttl_minutes=15)
    log(f"[Notify] Generated group activation code for {registration_id}: {code}")
    return jsonify({"code": code, "command": f"/activate {code}", "expiresInMinutes": 15})


# приглашения для одноклассников

@bp.route('/generate-classmate-invite', methods=['POST'])
@rate_limit('devices')
def cf3_generate_classmate_invite():
    """одноразовое приглашение одноклассника создаёт только администратор"""
    from datetime import datetime, timedelta, timezone
    import secrets

    data = request.get_json(silent=True, force=True) or {}
    registration_id = data.get('registrationId')

    if not registration_id:
        return jsonify({"error": "registrationId required"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT id, grade_class FROM cf3_registrations WHERE id = %s AND is_classmate = FALSE",
            (registration_id,)
        )
        row = cursor.fetchone()
        if not row:
            cursor.close()
            conn.close()
            return jsonify({"error": "Registration not found or not an admin account"}), 404

        grade_class = row['grade_class']

        # сперва гасим все ещё живые токены этой регистрации
        cursor.execute(
            "DELETE FROM classmate_invite_tokens WHERE created_by_registration_id = %s AND used_at IS NULL",
            (registration_id,)
        )

        # выпускаем новый токен, 256 бит в hex
        invite_token = secrets.token_hex(32)
        expires_minutes = 60
        expires_at = datetime.now() + timedelta(minutes=expires_minutes)

        cursor.execute(
            """INSERT INTO classmate_invite_tokens
               (token, created_by_registration_id, grade_class, expires_at)
               VALUES (%s, %s, %s, %s)""",
            (invite_token, registration_id, grade_class, expires_at)
        )
        conn.commit()
        cursor.close()
        conn.close()

        log(f"[Classmate] Invite token generated by {registration_id}, class={grade_class}")
        return jsonify({"inviteToken": invite_token, "expiresInMinutes": expires_minutes})

    except Exception as e:
        log(f"[Classmate] generate-classmate-invite error: {e}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/classmate-join', methods=['POST'])
@rate_limit('notification_register')
def cf3_classmate_join():
    """однокласснику достаточно одноразового приглашения, школьный пароль для общих заданий не нужен"""
    import secrets
    from datetime import datetime

    data = request.get_json(silent=True, force=True) or {}

    invite_token = data.get('inviteToken', '').strip()
    device_name = (data.get('deviceName') or 'Unknown device').strip()
    # приложение шлёт fullName, displayName оставлен ради совместимости
    display_name = (data.get('fullName') or data.get('displayName') or '').strip() or None
    verification_token = (data.get('verificationToken') or '').strip() or None

    if not invite_token:
        return jsonify({"error": "inviteToken required"}), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)

        # если имя не прислали, ищем его в verified_users по verificationToken
        if not display_name and verification_token:
            cursor.execute(
                "SELECT full_name FROM verified_users WHERE token = %s",
                (verification_token,)
            )
            row = cursor.fetchone()
            if row and row['full_name']:
                display_name = row['full_name'].strip() or None

        # проверяем токен приглашения
        cursor.execute(
            "SELECT token, grade_class, expires_at, used_at FROM classmate_invite_tokens WHERE token = %s FOR UPDATE",
            (invite_token,)
        )
        inv = cursor.fetchone()

        if not inv:
            cursor.close(); conn.close()
            return jsonify({"error": "Invalid invite token"}), 401
        if inv['used_at'] is not None:
            cursor.close(); conn.close()
            return jsonify({"error": "Invite token already used"}), 401
        if inv['expires_at'] < datetime.now():
            cursor.close(); conn.close()
            return jsonify({"error": "Invite token expired"}), 401

        grade_class = inv['grade_class'] or ''

        classmate_id = str(uuid.uuid4())
        classmate_token = secrets.token_hex(32)

        cursor2 = conn.cursor()
        cursor2.execute("""
            INSERT INTO classmate_registrations
                (id, display_name, grade_class, device_name, classmate_token)
            VALUES (%s, %s, %s, %s, %s)
        """, (classmate_id, display_name, grade_class, device_name, classmate_token))

        # помечаем приглашение использованным
        cursor2.execute(
            "UPDATE classmate_invite_tokens SET used_at = NOW() WHERE token = %s",
            (invite_token,)
        )
        conn.commit()
        cursor.close(); cursor2.close(); conn.close()

        # кладём свежего одноклассника в кеш авторизации, первый же его запрос попадёт в него
        remember_classmate_token(classmate_id, classmate_token, {
            'id': classmate_id,
            'grade_class': grade_class,
            'display_name': display_name,
        })

        log(f"[Classmate] Joined: name={display_name}, class={grade_class}, id={classmate_id}")
        return jsonify({"success": True, "classmateId": classmate_id, "classmateToken": classmate_token})

    except Exception as e:
        log(f"[Classmate] join error: {e}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/classmate-leave', methods=['POST'])
@rate_limit('devices')
def cf3_classmate_leave():
    """идентификатор удаляемого одноклассника берём из токена авторизации"""
    from flask import g as _g
    classmate_id = getattr(_g, 'classmate_id', None)

    if not classmate_id:
        return jsonify({"error": "Unauthorized"}), 401

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("DELETE FROM classmate_registrations WHERE id = %s", (classmate_id,))
        conn.commit(); cursor.close(); conn.close()
        invalidate_classmate(classmate_id)

        return jsonify({"success": True})
    except Exception as e:
        log(f"[Classmate] leave error: {e}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/send-topic-labels', methods=['POST'])
@rate_limit('devices')
def cf3_send_topic_labels():
    """отправляем название предмета в привязанный к нему топик"""
    data = request.get_json(silent=True, force=True) or {}
    registration_id = data.get('registrationId')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT telegram_bot_token, telegram_group_chat_id,
                   telegram_topic_map, known_subjects
            FROM cf3_registrations WHERE id = %s
        """, (registration_id,))
        reg = cursor.fetchone()
        cursor.close()
        conn.close()
    except Exception as e:
        log(f"[Notify] send-topic-labels DB error: {e}")
        return jsonify({"error": "Database error"}), 500

    if not reg:
        return jsonify({"error": "Registration not found"}), 404

    telegram_info = get_telegram_info(registration_id) or {}
    bot_token = telegram_info.get('telegram_bot_token') or ''
    group_chat_id = reg.get('telegram_group_chat_id') or ''
    if not bot_token or not group_chat_id:
        return jsonify({"error": "Telegram bot or group not configured"}), 400

    topic_map = {}
    if reg.get('telegram_topic_map'):
        try:
            topic_map = json.loads(reg['telegram_topic_map'])
        except Exception:
            pass

    if not topic_map:
        return jsonify({"error": "No topic bindings configured"}), 400

    subjects = {}
    if reg.get('known_subjects'):
        try:
            subjects = json.loads(reg['known_subjects'])
        except Exception:
            pass

    sent = 0
    errors = 0
    for subject_id, topic_id in topic_map.items():
        subject_name = subjects.get(str(subject_id)) or f"Предмет {subject_id}"
        try:
            topic_id_int = int(topic_id) if topic_id is not None else None
            ok = send_telegram_message(
                bot_token,
                group_chat_id,
                subject_name,
                "",
                message_thread_id=topic_id_int,
            )
            if ok:
                sent += 1
            else:
                errors += 1
        except Exception as e:
            log(f"[Notify] send-topic-labels error for {subject_id}: {e}")
            errors += 1

    log(f"[Notify] send-topic-labels: sent={sent}, errors={errors} for {registration_id}")
    return jsonify({"success": True, "sent": sent, "errors": errors})


@bp.route('/get-account-status', methods=['POST'])
@rate_limit('devices')
def get_account_status():
    """показываем, недействительна ли сессия регистрации"""
    data = request.get_json() or {}
    registration_id = data.get('registrationId')
    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT session_invalid, session_invalid_reason, session_invalid_at
            FROM cf3_registrations WHERE id = COALESCE(cf3_account_primary(%s), %s)
        """, (registration_id, registration_id))
        reg = cursor.fetchone()
        cursor.close()
        conn.close()

        if not reg:
            return jsonify({"error": "Registration not found"}), 404

        return jsonify({
            "sessionInvalid": bool(reg.get('session_invalid')),
            "reason": reg.get('session_invalid_reason'),
            "invalidAt": str(reg.get('session_invalid_at')) if reg.get('session_invalid_at') else None,
        })
    except Exception as e:
        log(f"[Notify] get-account-status error: {e}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/retry-session', methods=['POST'])
@rate_limit('notification_register')
def retry_session():
    """восстанавливаем сессию после успешного входа с сохранёнными данными"""
    data = request.get_json() or {}
    registration_id = data.get('registrationId')
    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT id, username, password_encrypted FROM cf3_registrations
            WHERE id = COALESCE(cf3_account_primary(%s), %s)
        """, (registration_id, registration_id))
        reg = cursor.fetchone()
        cursor.close()
        conn.close()

        if not reg:
            return jsonify({"error": "Registration not found"}), 404

        registration_id = reg['id']
        init_encryption()
        password = decrypt_password(reg['password_encrypted'])
        if not password:
            return jsonify({"error": "Failed to decrypt credentials"}), 500

        username = reg['username']
        hw, grades, notifications_list, name, cookies, prs_id = login_and_get_data(username, password)

        if hw is None:
            return jsonify({"error": "Login failed"}), 401

        conn2 = get_db_connection()
        if not conn2:
            return jsonify({"error": "Database connection failed"}), 503
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
        finally:
            conn2.close()

        update_session(registration_id, cookies)
        log(f"[Notify] Session restored via retry for {registration_id} ({username})")
        return jsonify({"success": True})
    except Exception as e:
        log(f"[Notify] retry-session error: {e}")
        return jsonify({"error": "Server error"}), 500


@bp.route('/update-password', methods=['POST'])
@rate_limit('notification_register')
def update_password():
    """сохраняем новый пароль и восстанавливаем сессию после успешного входа"""
    data = request.get_json() or {}
    registration_id = data.get('registrationId')
    new_password = data.get('password')

    if not registration_id:
        return jsonify({"error": "No registrationId provided"}), 400
    if not new_password:
        return jsonify({"error": "No password provided"}), 400
    owner_error = _require_registration_owner(registration_id, data)
    if owner_error:
        return owner_error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""SELECT id, username FROM cf3_registrations
            WHERE id = COALESCE(cf3_account_primary(%s), %s)""",
            (registration_id, registration_id))
        reg = cursor.fetchone()
        cursor.close()
        conn.close()

        if not reg:
            return jsonify({"error": "Registration not found"}), 404

        registration_id = reg['id']
        username = reg['username']
        hw, grades, notifications_list, name, cookies, prs_id = login_and_get_data(username, new_password)

        if hw is None:
            return jsonify({"error": "Login failed"}), 401

        init_encryption()
        encrypted = encrypt_password(new_password)
        if not encrypted:
            return jsonify({"error": "Encryption failed"}), 500

        conn2 = get_db_connection()
        if not conn2:
            return jsonify({"error": "Database connection failed"}), 503
        try:
            cursor2 = conn2.cursor()
            cursor2.execute("""
                UPDATE cf3_registrations
                SET password_encrypted = %s,
                    session_invalid = FALSE,
                    session_invalid_reason = NULL,
                    session_invalid_at = NULL
                WHERE id = %s
            """, (encrypted, registration_id))
            conn2.commit()
            cursor2.close()
        finally:
            conn2.close()

        update_session(registration_id, cookies)
        log(f"[Notify] Password updated and session restored for {registration_id} ({username})")
        return jsonify({"success": True})
    except Exception as e:
        log(f"[Notify] update-password error: {e}")
        return jsonify({"error": "Server error"}), 500
