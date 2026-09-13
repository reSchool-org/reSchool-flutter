"""сводка урока: несколько записей на один слот одной карточкой
сводка это производное представление, а не слияние записей. Оригиналы никто
не трогает, поэтому правку и удаление не приходится разматывать: достаточно
пересобрать сводку из того, что осталось
показываем её, только когда источников больше одного: учитель плюс одноклассник
или двое одноклассников. На единственной записи сводка не нужна"""

import hashlib
import json
import os

from . import ai_prompts, analysis, gemini_client
from .database import get_db_connection, json_value
from .logging_utils import log

# пауза перед пересборкой: правки в одном слоте коалесцируются в одну
REBUILD_DELAY_SECONDS = int(os.environ.get("MERGE_REBUILD_DELAY_SECONDS", "30"))
MAX_PARTS = 10


def slot_key(grade_class, subject, lesson_date):
    return f"{grade_class}|{subject}|{lesson_date}"


def request_rebuild(conn, grade_class, subject, lesson_date):
    """поставить пересборку в очередь
    уникальный индекс по dedup_key сам склеит несколько правок подряд в одну
    задачу, а run_after даёт окно, чтобы дождаться соседних изменений"""
    if not (grade_class and subject and lesson_date):
        return
    key = slot_key(grade_class, subject, lesson_date)
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO ai_jobs (kind, dedup_key, payload, run_after)
            VALUES ('merge_homework', %s, %s,
                    (now() AT TIME ZONE 'utc') + %s * INTERVAL '1 second')
            ON CONFLICT DO NOTHING
        """, (f"merge:{key}", json_value({
            "grade_class": grade_class,
            "subject": subject,
            "lesson_date": str(lesson_date),
        }), REBUILD_DELAY_SECONDS))
        conn.commit()
    finally:
        cursor.close()


def _load_parts(cursor, grade_class, subject, lesson_date):
    """записи слота, которые дожили до сводки. Отклонённые в неё не попадают"""
    cursor.execute("""
        SELECT a.id, a.source, a.source_id, a.raw_text, a.attachments, a.estimable
        FROM homework_analysis a
        WHERE a.grade_class = %s AND a.subject = %s AND a.lesson_date = %s
          AND a.status <> 'rejected'
        ORDER BY (a.source = 'teacher') DESC, a.id
        LIMIT %s
    """, (grade_class, subject, lesson_date, MAX_PARTS))

    parts = []
    for row in cursor.fetchall():
        analysis_id, source, source_id, raw_text, attachments, estimable = row
        author = "Учитель"
        if source == "custom" and source_id:
            cursor.execute(
                "SELECT author_full_name FROM custom_homework WHERE id = %s",
                (source_id,))
            found = cursor.fetchone()
            # запись могли удалить, тогда её в сводке быть не должно
            if not found:
                continue
            author = found[0] or "Одноклассник"
        parts.append({
            "analysis_id": analysis_id,
            "source": source,
            "source_id": source_id,
            "text": raw_text or "",
            "author": author,
            "attachments": attachments or [],
            "estimable": estimable,
        })
    return parts


def _parts_hash(parts):
    payload = [f"{p['analysis_id']}:{analysis._normalize(p['text'])}"
               f":{len(p['attachments'])}" for p in parts]
    return hashlib.sha256("|".join(payload).encode()).hexdigest()


def rebuild(grade_class, subject, lesson_date, attempts=3):
    """собрать сводку слота заново
    пока сводка считалась, в слот могла приехать ещё одна запись, а её просьба
    о пересборке отвалилась по уникальному ключу задачи. Поэтому в конце
    сверяем состав ещё раз и при расхождении идём на второй круг"""
    result = None
    for _ in range(attempts):
        result = _rebuild_once(grade_class, subject, lesson_date)
        if not result.get("stale"):
            break
        log(f"[Merge] {grade_class}/{subject}/{lesson_date}: состав изменился на ходу, пересобираем")
    return result


def _rebuild_once(grade_class, subject, lesson_date):
    conn = get_db_connection()
    if not conn:
        raise RuntimeError("нет соединения с базой")
    cursor = conn.cursor()

    # пересборка идёт под тем же замком, что и модерация: иначе две правки
    # подряд могут записать сводку в обратном порядке
    lock_key = analysis._slot_lock_key(grade_class, subject, lesson_date)
    cursor.execute("SELECT pg_advisory_lock(%s)", (lock_key,))
    conn.commit()
    try:
        parts = _load_parts(cursor, grade_class, subject, lesson_date)
        digest = _parts_hash(parts)

        cursor.execute("""
            INSERT INTO homework_merge (grade_class, subject, lesson_date)
            VALUES (%s, %s, %s)
            ON CONFLICT (grade_class, subject, lesson_date) DO NOTHING
            RETURNING id
        """, (grade_class, subject, lesson_date))
        row = cursor.fetchone()
        if row:
            merge_id = row[0]
        else:
            cursor.execute("""
                SELECT id FROM homework_merge
                WHERE grade_class = %s AND subject = %s AND lesson_date = %s
            """, (grade_class, subject, lesson_date))
            merge_id = cursor.fetchone()[0]
        conn.commit()

        # на одной записи сводка не нужна, но строку держим: удалят соседа
        # и она сама схлопнется в пустую, а не останется висеть от прошлого раза
        if len(parts) < 2:
            cursor.execute("""
                UPDATE homework_merge SET status = 'empty', parts_hash = %s,
                    merged_text = NULL, authors = NULL, highlights = NULL,
                    part_count = %s, last_error = NULL
                WHERE id = %s
            """, (digest, len(parts), merge_id))
            cursor.execute("DELETE FROM homework_merge_parts WHERE merge_id = %s",
                           (merge_id,))
            conn.commit()
            log(f"[Merge] {grade_class}/{subject}/{lesson_date}: частей {len(parts)}, сводка не нужна")
            return {"status": "empty", "parts": len(parts), "stale": False}

        cursor.execute("SELECT parts_hash, status FROM homework_merge WHERE id = %s",
                       (merge_id,))
        stored_hash, stored_status = cursor.fetchone()
        if stored_hash == digest and stored_status == 'ready':
            log(f"[Merge] {grade_class}/{subject}/{lesson_date}: состав не менялся")
            return {"status": "ready", "parts": len(parts), "cached": True, "stale": False}

        merged = _summarize(parts, subject, lesson_date)
        authors = []
        for part in parts:
            if part["author"] not in authors:
                authors.append(part["author"])

        cursor.execute("""
            UPDATE homework_merge SET status = 'ready', parts_hash = %s, merged_text = %s,
                authors = %s, highlights = %s, part_count = %s, last_error = NULL
            WHERE id = %s
        """, (digest, merged.get("text"), json_value(authors),
              json_value(merged.get("highlights") or []), len(parts), merge_id))

        cursor.execute("DELETE FROM homework_merge_parts WHERE merge_id = %s", (merge_id,))
        for order, part in enumerate(parts):
            cursor.execute("""
                INSERT INTO homework_merge_parts
                    (merge_id, analysis_id, source, author, sort_order)
                VALUES (%s, %s, %s, %s, %s)
            """, (merge_id, part["analysis_id"], part["source"],
                  part["author"][:256], order))
        conn.commit()
        log(f"[Merge] {grade_class}/{subject}/{lesson_date}: сводка из {len(parts)} частей, "
            f"авторов {len(authors)}")
        fresh = _parts_hash(_load_parts(cursor, grade_class, subject, lesson_date))
        return {"status": "ready", "parts": len(parts), "stale": fresh != digest}
    finally:
        cursor.execute("SELECT pg_advisory_unlock(%s)", (lock_key,))
        conn.commit()
        cursor.close()
        conn.close()


def _summarize(parts, subject, lesson_date):
    lines = [f"Предмет: {subject}. Дата урока: {lesson_date}.", "", "Записи:"]
    for part in parts:
        who = "учитель" if part["source"] == "teacher" else part["author"]
        attached = ""
        if part["attachments"]:
            attached = f" (приложено файлов: {len(part['attachments'])})"
        lines.append(f"- {who}: {part['text']}{attached}")

    merged, stats = gemini_client.generate(
        [{"text": "\n".join(lines)}], schema=ai_prompts.MERGE_SCHEMA,
        system=ai_prompts.MERGE_SYSTEM, media_resolution=None)
    log(f"[Merge] Сведено за {stats['sec']}с")
    return merged


def load(cursor, grade_class, subject, lesson_date):
    """готовая сводка слота вместе с картинками всех частей"""
    cursor.execute("""
        SELECT id, status, merged_text, authors, highlights, part_count
        FROM homework_merge
        WHERE grade_class = %s AND subject = %s AND lesson_date = %s
    """, (grade_class, subject, lesson_date))
    row = cursor.fetchone()
    if not row or row[1] != 'ready':
        return None

    merge_id, _, merged_text, authors, highlights, part_count = row
    cursor.execute("""
        SELECT analysis_id, source, author FROM homework_merge_parts
        WHERE merge_id = %s ORDER BY sort_order
    """, (merge_id,))
    parts = cursor.fetchall()

    images = []
    total_minutes = 0
    has_estimate = bool(parts)
    for analysis_id, source, author in parts:
        images.extend(_part_images(cursor, analysis_id, author))
        cursor.execute(
            "SELECT total_minutes, estimable FROM homework_analysis WHERE id = %s",
            (analysis_id,))
        found = cursor.fetchone()
        if found and found[1] and found[0]:
            total_minutes += found[0]
        else:
            has_estimate = False

    return {
        "id": merge_id,
        "text": merged_text,
        "authors": authors or [],
        "highlights": highlights or [],
        "partCount": part_count,
        "images": images,
        "totalMinutes": total_minutes if has_estimate else None,
    }


def _part_images(cursor, analysis_id, author):
    """вырезки из учебника и приложенные фотографии одной части"""
    result = []
    cursor.execute("""
        SELECT id, label, subitem, target_type, printed_page
        FROM homework_analysis_images
        WHERE analysis_id = %s ORDER BY sort_order
    """, (analysis_id,))
    for row in cursor.fetchall():
        result.append({
            "kind": "textbook",
            "label": row[1],
            "subitem": row[2] or None,
            "targetType": row[3],
            "printedPage": row[4],
            "author": author,
            "url": f"/homework/analysis/image/{row[0]}",
        })

    cursor.execute("SELECT attachments FROM homework_analysis WHERE id = %s", (analysis_id,))
    row = cursor.fetchone()
    attachments = (row[0] if row else None) or []
    for index, attachment in enumerate(attachments):
        if not attachment.get("path"):
            continue
        result.append({
            "kind": "attachment",
            "label": attachment.get("name") or "Вложение",
            "author": author,
            "url": f"/homework/analysis/attachment/{analysis_id}/{index}",
        })
    return result


def parts_for_analysis(cursor, analysis_id):
    """слот, в который входит разбор. Нужен, чтобы дёрнуть пересборку"""
    cursor.execute("""
        SELECT grade_class, subject, lesson_date FROM homework_analysis WHERE id = %s
    """, (analysis_id,))
    return cursor.fetchone()
