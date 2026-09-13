"""уведомление ждёт разбора задания, но при недоступной модели уходит без него"""

import hashlib
import json
import os
import re
from datetime import datetime, timedelta

from . import ai_prompts, analysis_sources, gemini_client, textbook
from .config import ANALYSIS_ENABLED, ANALYSIS_NOTIFICATION_TIMEOUT_SECONDS
from .database import get_db_connection, json_value
from .logging_utils import log

# больше целей в одно домашнее задание не берём: обычно это разбор кривой записи,
# а не реальный список заданий
MAX_TARGETS = 8
MAX_ATTEMPTS = 3
# ждём задание учителя за тот же урок, чтобы не отправить классу дубль
CUSTOM_MODERATION_DELAY_SECONDS = int(os.environ.get("CUSTOM_MODERATION_DELAY_SECONDS", "40"))


def is_enabled():
    return ANALYSIS_ENABLED and gemini_client.is_configured()


def _normalize(text):
    """для дедупа: регистр, пробелы и пунктуация роли не играют"""
    return re.sub(r"[^0-9a-zа-яё]+", " ", (text or "").lower()).strip()


def dedup_hash(grade_class, subject, lesson_date, text):
    raw = f"{grade_class}|{subject}|{lesson_date}|{_normalize(text)}"
    return hashlib.sha256(raw.encode()).hexdigest()


def enqueue(conn, grade_class, subject, lesson_date, text, source, source_id,
            attachments=None, attachment_headers=None, attachment_cookies=None):
    """разбор общий для класса, иначе одно задание считалось бы для каждого ученика"""
    if not text or not str(text).strip():
        return None, False
    digest = dedup_hash(grade_class, subject, lesson_date, text)
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO homework_analysis
                (dedup_hash, grade_class, subject, lesson_date, source, source_id, raw_text)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (dedup_hash) DO NOTHING
            RETURNING id
        """, (digest, grade_class, subject, lesson_date, source,
              str(source_id) if source_id is not None else None, text))
        row = cursor.fetchone()
        if row:
            analysis_id, is_new = row[0], True
        else:
            cursor.execute("SELECT id FROM homework_analysis WHERE dedup_hash = %s", (digest,))
            analysis_id, is_new = cursor.fetchone()[0], False

        if is_new:
            # вложения тянем прямо сейчас: в воркере куки eSchool могут протухнуть
            saved = analysis_sources.fetch_teacher_attachments(
                analysis_id, attachments, attachment_headers, attachment_cookies)
            if saved:
                cursor.execute(
                    "UPDATE homework_analysis SET attachments = %s WHERE id = %s",
                    (json_value(saved), analysis_id))
            # задание учителя могло прийти секундой позже
            # без паузы дубль ушёл бы классу
            delay = CUSTOM_MODERATION_DELAY_SECONDS if source == "custom" else 0
            cursor.execute("""
                INSERT INTO ai_jobs (kind, dedup_key, payload, run_after)
                VALUES ('analyze_homework', %s, %s,
                        (now() AT TIME ZONE 'utc') + %s * INTERVAL '1 second')
                ON CONFLICT DO NOTHING
            """, (f"analysis:{analysis_id}", json_value({"analysis_id": analysis_id}), delay))
        conn.commit()
        return analysis_id, is_new
    finally:
        cursor.close()


def add_pending(conn, analysis_id, audience, title, body, data=None, payload=None,
                registration_id=None, grade_class=None,
                exclude_classmate_id=None, exclude_registration_id=None):
    """отложить пуш до готовности разбора"""
    cursor = conn.cursor()
    try:
        # разные идентификаторы eschool могут вести к одному разбору; проверку и вставку блокируем между процессами
        key = f"pending:{analysis_id}:{audience}:{registration_id}:{grade_class}:{title[:256]}"
        cursor.execute("SELECT pg_advisory_xact_lock(hashtextextended(%s, 0))", (key,))
        cursor.execute("""
            SELECT id FROM pending_notifications
            WHERE analysis_id = %s AND audience = %s
              AND registration_id IS NOT DISTINCT FROM %s
              AND grade_class IS NOT DISTINCT FROM %s AND title = %s
            LIMIT 1
        """, (analysis_id, audience, registration_id, grade_class, title[:256]))
        if cursor.fetchone():
            conn.commit()
            return
        cursor.execute("""
            INSERT INTO pending_notifications
                (analysis_id, audience, registration_id, grade_class, title, body, data, payload,
                 exclude_classmate_id, exclude_registration_id)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        """, (analysis_id, audience, registration_id, grade_class, title[:256], body,
              json_value(data or {}), json_value(payload or {}),
              exclude_classmate_id, exclude_registration_id))
        conn.commit()
    finally:
        cursor.close()


def run(analysis_id):
    """полный конвейер по одному разбору"""
    conn = get_db_connection()
    if not conn:
        raise RuntimeError("нет соединения с базой")
    cursor = conn.cursor()
    try:
        cursor.execute("""
            SELECT grade_class, subject, lesson_date, source, source_id, raw_text, status,
                   attempts, attachments
            FROM homework_analysis WHERE id = %s
        """, (analysis_id,))
        row = cursor.fetchone()
        if not row:
            return
        (grade_class, subject, lesson_date, source, source_id, raw_text, status,
         attempts, attachments) = row
        if status in ("done", "rejected"):
            return

        cursor.execute(
            "UPDATE homework_analysis SET status = 'processing', attempts = attempts + 1 WHERE id = %s",
            (analysis_id,))
        conn.commit()

        # своё домашнее задание сначала проходит модерацию, бред и дубли до класса не доводим
        if source == "custom":
            verdict = _moderate(cursor, conn, analysis_id, grade_class, subject,
                                lesson_date, raw_text)
            if verdict and verdict["verdict"] != "ok":
                _reject(conn, cursor, analysis_id, verdict)
                return

        result = _analyze(cursor, conn, analysis_id, grade_class, subject, lesson_date,
                          raw_text, source, source_id, attachments or [])
        cursor.execute("""
            UPDATE homework_analysis SET status = 'done', targets = %s, items = %s,
                total_minutes = %s, range_min = %s, range_max = %s, hardest = %s, why = %s,
                textbook_id = %s, estimable = %s, unestimable_reason = %s, sources = %s,
                last_error = NULL
            WHERE id = %s
        """, (json_value(result["targets"]), json_value(result["items"]),
              result.get("total_minutes"), result.get("range_min"), result.get("range_max"),
              (result.get("hardest") or "")[:128], result.get("why"),
              result.get("textbook_id"), result.get("estimable", True),
              result.get("unestimable_reason"), json_value(result.get("sources") or []),
              analysis_id))
        conn.commit()
        flush(analysis_id)
        _request_merge(conn, grade_class, subject, lesson_date)
    except Exception as e:
        log(f"[Analysis] {analysis_id} упал: {e}")
        cursor.execute(
            "UPDATE homework_analysis SET status = 'pending', last_error = %s WHERE id = %s",
            (str(e)[:500], analysis_id))
        conn.commit()
        cursor.execute("SELECT attempts FROM homework_analysis WHERE id = %s", (analysis_id,))
        row = cursor.fetchone()
        if row and row[0] >= MAX_ATTEMPTS:
            # дальше пытаться бессмысленно, пусть уходит обычный пуш
            cursor.execute(
                "UPDATE homework_analysis SET status = 'failed' WHERE id = %s", (analysis_id,))
            conn.commit()
            flush(analysis_id)
        raise
    finally:
        cursor.close()
        conn.close()


def _request_merge(conn, grade_class, subject, lesson_date):
    """состав слота изменился, сводку надо пересобрать"""
    try:
        from . import merge
        merge.request_rebuild(conn, grade_class, subject, lesson_date)
    except Exception as e:
        log(f"[Analysis] Не удалось поставить пересборку сводки: {e}")


def _reject(conn, cursor, analysis_id, verdict):
    cursor.execute("""
        UPDATE homework_analysis SET status = 'rejected', reject_reason = %s,
            reject_detail = %s, duplicate_of = %s WHERE id = %s
    """, (verdict["verdict"][:16], verdict.get("reason", "")[:500],
          verdict.get("duplicate_of"), analysis_id))
    cursor.execute(
        "UPDATE pending_notifications SET status = 'dropped' WHERE analysis_id = %s AND status = 'pending'",
        (analysis_id,))
    conn.commit()
    log(f"[Analysis] {analysis_id} отклонён: {verdict['verdict']} ({verdict.get('reason')})")


def _slot_lock_key(grade_class, subject, lesson_date):
    """ключ блокировки на связку класс, предмет, дата урока"""
    raw = f"{grade_class}|{subject}|{lesson_date}".encode()
    # postgres берёт знаковый bigint, поэтому режем до 63 бит
    return int.from_bytes(hashlib.sha256(raw).digest()[:8], "big") % (2 ** 63)


def _moderate(cursor, conn, analysis_id, grade_class, subject, lesson_date, text):
    """бред это или дубль уже заданного
    проверка идёт под блокировкой на связку класс + предмет + дата: без неё два
    задания, поданные почти одновременно, посмотрели бы друг на друга и оба
    ушли бы в дубли, а класс не получил бы ничего"""
    lock_key = _slot_lock_key(grade_class, subject, lesson_date)
    cursor.execute("SELECT pg_advisory_lock(%s)", (lock_key,))
    conn.commit()
    try:
        return _moderate_locked(cursor, analysis_id, grade_class, subject, lesson_date, text)
    finally:
        cursor.execute("SELECT pg_advisory_unlock(%s)", (lock_key,))
        conn.commit()


def _moderate_locked(cursor, analysis_id, grade_class, subject, lesson_date, text):
    # дублем считаем только то, что появилось раньше: учительское в любом случае,
    # а среди своих то, у которого id меньше. так из двух одновременных
    # одинаковых записей отваливается ровно одна
    cursor.execute("""
        SELECT id, source, raw_text FROM homework_analysis
        WHERE grade_class = %s AND subject = %s AND lesson_date = %s
          AND id <> %s AND status IN ('done', 'pending', 'processing', 'failed')
          AND (source = 'teacher' OR id < %s)
        ORDER BY (source = 'teacher') DESC, id
        LIMIT 12
    """, (grade_class, subject, lesson_date, analysis_id, analysis_id))
    existing = cursor.fetchall()
    allowed_ids = {row[0] for row in existing}

    lines = [f"Класс: {grade_class}. Предмет: {subject}. Дата урока: {lesson_date}.",
             f"Проверяемая запись: {text}", ""]
    if existing:
        lines.append("Уже задано на этот день по этому предмету:")
        for row in existing:
            who = "учитель" if row[1] == "teacher" else "одноклассник"
            lines.append(f"- id={row[0]} ({who}): {row[2]}")
    else:
        lines.append("На этот день по этому предмету пока ничего не задано.")

    verdict, stats = gemini_client.generate(
        [{"text": "\n".join(lines)}], schema=ai_prompts.MODERATE_SCHEMA,
        system=ai_prompts.MODERATE_SYSTEM, media_resolution=None)
    log(f"[Analysis] Модерация {analysis_id}: {verdict.get('verdict')} "
        f"({verdict.get('confidence')}) {stats['sec']}с")

    # на грани оставляем задание в покое, ложное отклонение хуже лишнего пуша
    if verdict.get("verdict") != "ok" and float(verdict.get("confidence") or 0) < 0.6:
        log(f"[Analysis] Модерация {analysis_id}: уверенность низкая, пропускаем")
        return {"verdict": "ok", "reason": ""}

    if verdict.get("verdict") == "duplicate":
        target = verdict.get("duplicate_of")
        # модель могла показать на запись, которой в списке не было
        if target not in allowed_ids:
            if not allowed_ids:
                log(f"[Analysis] Модерация {analysis_id}: дубль без оригинала, пропускаем")
                return {"verdict": "ok", "reason": ""}
            verdict["duplicate_of"] = sorted(allowed_ids)[0]

    return verdict


def _analyze(cursor, conn, analysis_id, grade_class, subject, lesson_date, text,
             source, source_id, attachments):
    """собрать всё, что относится к заданию, и оценить это целиком"""
    parsed, stats = gemini_client.generate(
        [{"text": text}], schema=ai_prompts.PARSE_SCHEMA, system=ai_prompts.PARSE_SYSTEM,
        media_resolution=None)
    targets = (parsed.get("targets") or [])[:MAX_TARGETS]
    log(f"[Analysis] {analysis_id}: целей {len(targets)}, ссылок наружу "
        f"{len(parsed.get('external_refs') or [])}, {stats['sec']}с")

    book_kind = parsed.get("book_hint") if parsed.get("book_hint") in ("textbook", "workbook") else "textbook"
    book = textbook.find_textbook(cursor, grade_class, subject, book_kind)
    if not book and targets:
        # без книги вырезок не будет, а раньше это было видно только по пустой карточке
        log(f"[Analysis] {analysis_id}: учебник по предмету «{subject}» для {grade_class} не найден")

    # вырезки из учебника
    images = []
    # рабочую тетрадь нельзя заменять учебником, у смешанного задания номера относятся к разным книгам
    mixed_books = bool(re.search(r'учебник', text, re.I) and
                       re.search(r'рабоч\w*\s+тетрад', text, re.I))
    if book and targets and not mixed_books:
        doc = None
        try:
            doc = textbook.open_document(book["pdf_path"])
            images = _collect_images(cursor, conn, doc, book, analysis_id, targets)
        except Exception as e:
            log(f"[Analysis] {analysis_id}: нарезка не удалась: {e}")
        finally:
            if doc:
                doc.close()

    # фотографии: от учителя и от одноклассника, приложившего листочек
    materials = list(attachments or [])
    if source == "custom":
        materials += analysis_sources.custom_homework_files(cursor, source_id)

    # своё дз оцениваем вместе с учительским за тот же урок, иначе непонятно,
    # это отдельное задание или уточнение к уже заданному
    teacher_context = None
    if source == "custom":
        teacher_context = _teacher_context(cursor, analysis_id, grade_class, subject, lesson_date)

    assessment = _assess(grade_class, subject, text, targets, images, book,
                         materials, parsed, teacher_context)

    _store_images(cursor, conn, analysis_id, images)

    estimable = assessment.get("estimable") is True
    range_minutes = assessment.get("range_minutes") or [None, None]
    sources = ([{"kind": "textbook", "label": i["label"]} for i in images]
               + [{"kind": m.get("origin", "file"), "name": m.get("name")} for m in materials])

    return {
        "targets": targets,
        "items": assessment.get("items") or [] if estimable else [],
        "total_minutes": assessment.get("total_minutes") if estimable else None,
        "range_min": range_minutes[0] if estimable and len(range_minutes) > 0 else None,
        "range_max": range_minutes[1] if estimable and len(range_minutes) > 1 else None,
        "hardest": assessment.get("hardest") if estimable else None,
        "why": assessment.get("why") if estimable else None,
        "textbook_id": book["id"] if book else None,
        "estimable": estimable,
        "unestimable_reason": None if estimable else (
            assessment.get("unestimable_reason")
            or "Задания нет ни в учебнике, ни во вложениях"),
        "sources": sources,
    }


def _teacher_context(cursor, analysis_id, grade_class, subject, lesson_date):
    """что задал учитель на этот же урок"""
    cursor.execute("""
        SELECT raw_text FROM homework_analysis
        WHERE grade_class = %s AND subject = %s AND lesson_date = %s
          AND source = 'teacher' AND id <> %s
        ORDER BY id LIMIT 3
    """, (grade_class, subject, lesson_date, analysis_id))
    rows = [r[0] for r in cursor.fetchall() if r[0]]
    return "\n".join(rows) if rows else None


def _collect_images(cursor, conn, doc, book, analysis_id, targets):
    images = []
    for target in targets:
        kind = target.get("type")
        label = str(target.get("label") or "").strip()
        if not label:
            continue
        try:
            if kind == "exercise":
                pdf_index = textbook.exercise_page(cursor, book["id"], label)
                if pdf_index is None:
                    continue
                box = textbook.get_box(cursor, doc, book["id"], label, pdf_index)
                conn.commit()
                if not box:
                    continue
                for subitem in target.get("subitems") or [None]:
                    path = textbook.analysis_image_path(analysis_id, label, subitem)
                    textbook.crop_exercise(doc, box, path, subitem)
                    images.append({
                        "label": label, "subitem": subitem or "", "target_type": "exercise",
                        "mode": target.get("mode"), "path": path,
                        "printed_page": textbook.printed_page(cursor, book["id"], box["pdf_index"]),
                    })
            elif kind == "paragraph":
                pages = textbook.paragraph_pages(cursor, book["id"], label)
                if not pages:
                    continue
                # параграф это несколько страниц теории, каждая идёт отдельной картинкой:
                # склеенный столбик в ленте вырезок уже не прочитать
                for pdf_index in pages:
                    printed = textbook.printed_page(cursor, book["id"], pdf_index)
                    path = textbook.analysis_image_path(analysis_id, label, page=printed or pdf_index)
                    textbook.render_page(doc, pdf_index, path)
                    images.append({
                        "label": label, "subitem": "", "target_type": "paragraph",
                        "mode": target.get("mode"), "path": path,
                        "printed_page": printed,
                    })
        except Exception as e:
            log(f"[Analysis] {analysis_id}: цель {kind} {label} не вырезалась: {e}")
    return images


def _image_mime(path):
    return "image/jpeg" if path.lower().endswith((".jpg", ".jpeg")) else "image/png"


def _unestimable(reason):
    return {"estimable": False, "unestimable_reason": reason, "items": [],
            "total_minutes": 0, "range_minutes": [0, 0], "hardest": "", "why": ""}


def _requires_source(text, targets, parsed):
    # старый разбор мог поставить needs_material=false для ссылки на учебник, но номер страницы не заменяет содержимое
    return bool(any(t.get('type') in ('exercise', 'paragraph', 'page', 'rule') for t in targets)
                or parsed.get("needs_material") or parsed.get("external_refs")
                or re.search(r'учебник|тетрад|параграф|§|упр(?:ажнен\w*|\.)|'
                             r'стр(?:аниц\w*|\.)|\b(?:ex|pp?|st\.b)\.', text, re.I))


def _assess(grade_class, subject, text, targets, images, book, materials,
            parsed, teacher_context):
    """оценка по всему, что удалось собрать: текст, вырезки, фотографии"""
    grade = re.match(r"\d+", str(grade_class or ""))
    header = [f"Класс: {grade.group(0) if grade else grade_class}. Предмет: {subject}."]
    if book and book.get("title"):
        header.append(f"Учебник: {book['title']}.")
    header.append(f"Запись в дневнике: {text}")
    if teacher_context:
        header.append(f"На этот же урок учитель задал: {teacher_context}")
        header.append("Оцени только проверяемую запись, учительское дано для контекста.")

    refs = parsed.get("external_refs") or []
    if refs:
        header.append("Запись ссылается на: " + ", ".join(str(r) for r in refs) + ".")
    header.append("Номера страниц и упражнений не раскрывают их содержание. "
                  "Не восстанавливай учебник по памяти. Оценивай только предоставленные условия.")

    parts = [{"text": "\n".join(header)}]
    supplied_targets = set()
    supplied_material = False

    for image in images:
        label = image["label"]
        caption = (f"\nИз учебника: {image['target_type']} {label}"
                   f"{' пункт ' + image['subitem'] if image['subitem'] else ''}"
                   f", режим {image.get('mode')}"
                   f"{', стр. ' + str(image['printed_page']) if image.get('printed_page') else ''}.")
        if image["subitem"]:
            caption += " В кадре приглушено всё кроме нужного пункта."
        parts.append({"text": caption})
        if image.get("path") and os.path.exists(image["path"]):
            with open(image["path"], "rb") as f:
                parts.append(gemini_client.image_part(f.read(), _image_mime(image["path"])))
            supplied_targets.add((image['target_type'], str(label), image.get('subitem') or ''))

    for material in materials:
        path = material.get("path")
        if not path or not os.path.exists(path):
            continue
        who = "учитель" if material.get("origin") == "teacher" else "одноклассник"
        material_parts = analysis_sources.material_parts(material)
        if material_parts:
            parts.append({"text": f"\nВложение ({who}): {material.get('name')}"})
            parts.extend(material_parts)
            supplied_material = True

    requires_source = _requires_source(text, targets, parsed)
    if requires_source and not supplied_targets and not supplied_material:
        return _unestimable("Нет текста заданий: загрузите нужный учебник или приложите фото страниц/условий. "
                            "По одним номерам нельзя определить время и сложность.")
    def covered(target):
        key = (target.get('type'), str(target.get('label')))
        return (*key, '') in supplied_targets or all(
            (*key, str(part)) in supplied_targets for part in target.get('subitems') or [''])

    missing = [t for t in targets if t.get('type') in ('exercise', 'paragraph', 'page', 'rule')
               and not covered(t)]
    if not supplied_material and (missing or len(parsed.get('targets') or []) > MAX_TARGETS):
        return _unestimable("Не все условия заданий доступны. Приложите недостающие страницы или фото; "
                            "оценка всего ДЗ пока недоступна.")

    if not targets and not materials:
        parts.append({"text": "\nСтруктурных целей не нашлось, оцени задание целиком."})

    assessment, stats = gemini_client.generate(
        parts, schema=ai_prompts.ASSESS_SCHEMA, system=ai_prompts.ASSESS_SYSTEM)
    log(f"[Analysis] Оценка: estimable={assessment.get('estimable')} "
        f"{assessment.get('total_minutes')} мин, {stats['sec']}с")
    return assessment


def _store_images(cursor, conn, analysis_id, images):
    cursor.execute("DELETE FROM homework_analysis_images WHERE analysis_id = %s", (analysis_id,))
    for order, image in enumerate(images):
        if not image.get("path"):
            continue
        cursor.execute("""
            INSERT INTO homework_analysis_images
                (analysis_id, label, subitem, target_type, printed_page, storage_path, sort_order)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (analysis_id, image["label"][:32], image["subitem"][:16], image["target_type"],
              image.get("printed_page"), image["path"], order))
    conn.commit()


def summary_lines(analysis):
    """хвост уведомления с оценкой. Пусто, если разбора нет"""
    if not analysis or analysis.get("status") != "done":
        return []
    # оценивать нечего: задание живёт на листочке, которого у нас нет
    if not analysis.get("estimable", True):
        reason = analysis.get("unestimable_reason") or "нужен сам материал"
        return [f"📎 Оценить не получилось: {reason}"]
    lines = []
    total = analysis.get("total_minutes")
    if total:
        span = ""
        low, high = analysis.get("range_min"), analysis.get("range_max")
        if low and high and low != high:
            span = f" ({low}-{high})"
        lines.append(f"⏱ примерно {total} мин{span}")

    items = analysis.get("items") or []
    if items:
        hard = max(items, key=lambda i: (i.get("difficulty") or 0, i.get("minutes") or 0))
        parts = []
        for item in items[:4]:
            minutes = item.get("minutes")
            parts.append(f"{item.get('label')}"
                         f"{' ~' + str(minutes) + ' мин' if minutes else ''}")
        lines.append(" · ".join(parts))
        if hard.get("difficulty"):
            lines.append(f"🎯 сложнее всего: {hard.get('label')} ({hard['difficulty']}/5)")

    conflicts = [i.get("mode_conflict") for i in items if i.get("mode_conflict")]
    if conflicts:
        lines.append(f"⚠️ {conflicts[0]}")
    return lines


def load(analysis_id, cursor=None):
    own = cursor is None
    conn = None
    if own:
        conn = get_db_connection()
        if not conn:
            return None
        cursor = conn.cursor()
    try:
        cursor.execute("""
            SELECT id, status, total_minutes, range_min, range_max, hardest, why, items,
                   targets, reject_reason, reject_detail, grade_class, subject, lesson_date,
                   estimable, unestimable_reason
            FROM homework_analysis WHERE id = %s
        """, (analysis_id,))
        row = cursor.fetchone()
        if not row:
            return None
        return {
            "id": row[0], "status": row[1], "total_minutes": row[2],
            "range_min": row[3], "range_max": row[4], "hardest": row[5], "why": row[6],
            "items": row[7] or [], "targets": row[8] or [],
            "reject_reason": row[9], "reject_detail": row[10],
            "grade_class": row[11], "subject": row[12], "lesson_date": row[13],
            "estimable": row[14], "unestimable_reason": row[15],
        }
    finally:
        if own:
            cursor.close()
            conn.close()


def analysis_images(cursor, analysis_id):
    """вырезки в виде вложений: подпись такая же, как в карточке приложения"""
    cursor.execute("""
        SELECT label, subitem, target_type, printed_page, storage_path
        FROM homework_analysis_images WHERE analysis_id = %s ORDER BY sort_order
    """, (analysis_id,))
    result = []
    for label, subitem, target_type, printed, path in cursor.fetchall():
        name = ("§ " if target_type == "paragraph" else "№ ") + str(label)
        if subitem:
            name += f" ({subitem})"
        if printed:
            name += f", с. {printed}"
        result.append({"name": name, "path": path, "isImage": True})
    return result


def flush(analysis_id):
    """отправить отложенные пуши, дописав к ним разбор"""
    from .notification_delivery import send_notification_with_telegram
    from .routes.notifications import _notify_classmates

    conn = get_db_connection()
    if not conn:
        return
    cursor = conn.cursor()
    try:
        cursor.execute("""
            UPDATE pending_notifications
            SET status = 'sent', sent_at = (now() AT TIME ZONE 'utc')
            WHERE analysis_id = %s AND status = 'pending'
            RETURNING id, audience, registration_id, grade_class, title, body, data, payload,
                   exclude_classmate_id, exclude_registration_id
        """, (analysis_id,))
        rows = sorted(cursor.fetchall(), key=lambda row: row[0])
        if not rows:
            return

        analysis = load(analysis_id, cursor)
        extra = summary_lines(analysis)
        attachments = analysis_images(cursor, analysis_id) if analysis else []

        conn.commit()
    finally:
        cursor.close()
        conn.close()

    for row in rows:
        (_id, audience, registration_id, grade_class, title, body, data, payload,
         exclude_classmate, exclude_registration) = row
        data = data or {}
        if analysis:
            data = {**data, "analysisId": str(analysis_id)}
        full_body = "\n".join([part for part in [body] + extra if part])
        try:
            if audience == "registration":
                send_notification_with_telegram(
                    title, full_body, data,
                    registration_id=registration_id,
                    notification_type=(payload or {}).get("notification_type", "homework"),
                    telegram_attachments=((payload or {}).get("telegram_attachments") or []) + attachments,
                    telegram_attachment_headers=(payload or {}).get("telegram_attachment_headers"),
                    telegram_attachment_cookies=(payload or {}).get("telegram_attachment_cookies"),
                    telegram_analysis=analysis,
                )
            elif audience == "class" and (payload or {}).get("custom_homework_id"):
                # своё домашнее задание идёт ещё и в группу телеграма, там свой формат карточки
                from .routes.homework import _send_custom_homework_notifications
                _send_custom_homework_notifications(
                    homework_id=payload["custom_homework_id"],
                    grade_class=grade_class,
                    subject=(analysis or {}).get("subject"),
                    lesson_date=payload.get("lesson_date"),
                    text=body or "",
                    author_full_name=payload.get("author_full_name") or "Одноклассник",
                    files=payload.get("files") or [],
                    base_url=payload.get("base_url"),
                    classmate_id=exclude_classmate,
                    exclude_reg_id=exclude_registration,
                    extra_lines=extra,
                    analysis_id=analysis_id,
                    attachments=attachments,
                    analysis_data=analysis,
                )
            elif audience == "class":
                _notify_classmates(grade_class, title, full_body, data,
                                   exclude_classmate_id=exclude_classmate,
                                   exclude_registration_id=exclude_registration)
        except Exception as e:
            log(f"[Analysis] Отправка отложенного пуша {_id} не удалась: {e}")
    log(f"[Analysis] {analysis_id}: отправлено отложенных пушей {len(rows)}")


def flush_stale():
    """по таймауту отправляем уведомление без разбора, чтобы задание не потерялось"""
    conn = get_db_connection()
    if not conn:
        return
    cursor = conn.cursor()
    try:
        deadline = datetime.utcnow() - timedelta(seconds=ANALYSIS_NOTIFICATION_TIMEOUT_SECONDS)
        cursor.execute("""
            SELECT DISTINCT analysis_id FROM pending_notifications
            WHERE status = 'pending' AND created_at < %s
        """, (deadline,))
        stale = [r[0] for r in cursor.fetchall()]
    finally:
        cursor.close()
        conn.close()

    for analysis_id in stale:
        log(f"[Analysis] {analysis_id}: разбор не поспел, шлём пуш без него")
        try:
            flush(analysis_id)
        except Exception as e:
            log(f"[Analysis] Сторож не смог отправить {analysis_id}: {e}")
