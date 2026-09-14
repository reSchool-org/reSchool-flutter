"""учебники и разбор домашних заданий доступны в пределах класса пользователя"""

import os
import uuid

from flask import Blueprint, jsonify, request, send_file
from werkzeug.utils import secure_filename

from .. import analysis, ai_worker, gemini_client, merge, textbook
from ..config import MAX_TEXTBOOK_SIZE, TEXTBOOK_FOLDER
from ..database import get_db_connection
from ..logging_utils import log
from ..rate_limiter import rate_limit
from .homework import _resolve_grade_class_for_request

bp = Blueprint('textbooks', __name__)


@bp.route('/textbook/upload', methods=['POST'])
@rate_limit('default')
def upload_textbook():
    """принять PDF: воркер сам определит данные книги, затем построит индекс"""
    if not gemini_client.is_configured():
        return jsonify({"error": "AI is not configured on this server"}), 503

    grade_class, error = _resolve_grade_class_for_request()
    if error:
        return error

    upload = request.files.get('file')
    if not upload or not upload.filename:
        return jsonify({"error": "No file provided"}), 400
    if not upload.filename.lower().endswith('.pdf'):
        return jsonify({"error": "Only PDF is supported"}), 400

    upload.seek(0, 2)
    size = upload.tell()
    upload.seek(0)
    if size > MAX_TEXTBOOK_SIZE:
        return jsonify({"error": "File is too large"}), 400

    name = secure_filename(upload.filename) or 'textbook.pdf'
    path = os.path.join(TEXTBOOK_FOLDER, f"{uuid.uuid4().hex}_{name}")
    upload.save(path)

    conn = get_db_connection()
    if not conn:
        os.remove(path)
        return jsonify({"error": "Database connection failed"}), 500

    cursor = conn.cursor()
    try:
        # страницы считаем сразу, чтобы клиент видел прогресс с первой секунды
        try:
            doc = textbook.open_document(path)
            try:
                if doc.needs_pass or not doc.page_count:
                    raise ValueError("PDF защищён паролем или не содержит страниц")
                page_count = doc.page_count
            finally:
                doc.close()
        except Exception as e:
            os.remove(path)
            return jsonify({"error": f"Cannot read PDF: {e}"}), 400

        cursor.execute("""
            INSERT INTO textbooks
                (grade_class, subject, grade, title, authors, part, kind, pdf_path, page_count)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            RETURNING id
        """, (grade_class, '', None, upload.filename[:512], None, None,
              'textbook', path, page_count))
        textbook_id = cursor.fetchone()[0]

        # enqueue коммитит и книгу, и задачу одной транзакцией
        ai_worker.enqueue(conn, 'index_textbook', {"textbook_id": textbook_id},
                          dedup_key=f"textbook:{textbook_id}")
        log(f"[Textbook] Загружен {textbook_id} ({page_count} стр.) для {grade_class}")
        return jsonify({
            "success": True,
            "textbook": {"id": textbook_id, "title": upload.filename[:512],
                         "subject": "", "pageCount": page_count, "status": "pending"},
        })
    except Exception as e:
        conn.rollback()
        try:
            os.remove(path)
        except OSError:
            pass
        log(f"[Textbook] Upload error: {e}")
        return jsonify({"error": "Database error"}), 500
    finally:
        cursor.close()
        conn.close()


@bp.route('/textbook/list', methods=['POST'])
@rate_limit('default')
def list_textbooks():
    grade_class, error = _resolve_grade_class_for_request()
    if error:
        return error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500
    cursor = conn.cursor()
    try:
        cursor.execute("""
            SELECT id, subject, grade, title, authors, part, kind, page_count,
                   indexed_pages, status, status_detail
            FROM textbooks
            WHERE grade_class = %s OR grade_class IS NULL
            ORDER BY subject, id
        """, (grade_class,))
        return jsonify({"textbooks": [{
            "id": r[0], "subject": r[1], "grade": r[2], "title": r[3], "authors": r[4],
            "part": r[5], "kind": r[6], "pageCount": r[7], "indexedPages": r[8],
            "status": r[9], "statusDetail": r[10],
        } for r in cursor.fetchall()]})
    finally:
        cursor.close()
        conn.close()


@bp.route('/textbook/<int:textbook_id>', methods=['DELETE'])
@rate_limit('default')
def delete_textbook(textbook_id):
    grade_class, error = _resolve_grade_class_for_request()
    if error:
        return error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT pdf_path FROM textbooks WHERE id = %s AND grade_class = %s",
            (textbook_id, grade_class))
        row = cursor.fetchone()
        if not row:
            return jsonify({"error": "Not found"}), 404
        cursor.execute("DELETE FROM textbooks WHERE id = %s", (textbook_id,))
        conn.commit()
        try:
            os.remove(row[0])
        except OSError:
            pass
        return jsonify({"success": True})
    finally:
        cursor.close()
        conn.close()


@bp.route('/homework/analysis', methods=['POST'])
@rate_limit('default')
def get_analysis():
    """разбор домашнего задания ищем только в классе пользователя"""
    grade_class, error = _resolve_grade_class_for_request()
    if error:
        return error

    data = request.get_json(silent=True) or {}
    analysis_id = data.get('analysisId')
    subject = data.get('subject')
    lesson_date = data.get('date')
    text = data.get('text')

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500
    cursor = conn.cursor()
    try:
        if analysis_id:
            cursor.execute(
                "SELECT id FROM homework_analysis WHERE id = %s AND grade_class = %s",
                (analysis_id, grade_class))
        elif subject and lesson_date and text:
            cursor.execute("""
                SELECT id FROM homework_analysis
                WHERE grade_class = %s AND subject = %s AND lesson_date = %s
                  AND reject_reason IS DISTINCT FROM 'edited'
                  AND (raw_text = %s OR dedup_hash = %s)
                ORDER BY (raw_text = %s) DESC, id DESC LIMIT 1
            """, (grade_class, subject, lesson_date, text,
                  analysis.dedup_hash(grade_class, subject, lesson_date, text), text))
        else:
            return jsonify({"error": "Provide analysisId or subject+date+text"}), 400

        row = cursor.fetchone()
        if not row:
            return jsonify({"status": "none"})

        found = analysis.load(row[0], cursor)
        cursor.execute("""
            SELECT id, label, subitem, target_type, printed_page FROM homework_analysis_images
            WHERE analysis_id = %s ORDER BY sort_order
        """, (row[0],))
        images = [{
            "id": r[0], "label": r[1], "subitem": r[2] or None,
            "targetType": r[3], "printedPage": r[4],
            "url": f"/homework/analysis/image/{r[0]}",
        } for r in cursor.fetchall()]

        return jsonify({
            "status": found["status"],
            "analysisId": found["id"],
            "totalMinutes": found["total_minutes"],
            "rangeMinutes": [found["range_min"], found["range_max"]],
            "hardest": found["hardest"],
            "why": found["why"],
            "items": found["items"],
            "targets": found["targets"],
            "rejectReason": found["reject_reason"],
            "rejectDetail": found["reject_detail"],
            "estimable": found["estimable"],
            "unestimableReason": found["unestimable_reason"],
            "images": images,
        })
    finally:
        cursor.close()
        conn.close()


@bp.route('/homework/analysis/image/<int:image_id>', methods=['GET'])
@rate_limit('default')
def get_analysis_image(image_id):
    grade_class, error = _resolve_grade_class_for_request()
    if error:
        return error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500
    cursor = conn.cursor()
    try:
        cursor.execute("""
            SELECT i.storage_path FROM homework_analysis_images i
            JOIN homework_analysis a ON a.id = i.analysis_id
            WHERE i.id = %s AND a.grade_class = %s
        """, (image_id, grade_class))
        row = cursor.fetchone()
        if not row or not os.path.exists(row[0]):
            return jsonify({"error": "Not found"}), 404
        # тип flask возьмёт по расширению, вырезки бывают и jpeg и png
        return send_file(row[0])
    finally:
        cursor.close()
        conn.close()


@bp.route('/homework/summary', methods=['POST'])
@rate_limit('default')
def get_summary():
    """сводка урока: показываем, когда в слоте больше одной записи"""
    grade_class, error = _resolve_grade_class_for_request()
    if error:
        return error

    data = request.get_json(silent=True) or {}
    subject = data.get('subject')
    lesson_date = data.get('date')
    if not subject or not lesson_date:
        return jsonify({"error": "Provide subject and date"}), 400

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500
    cursor = conn.cursor()
    try:
        summary = merge.load(cursor, grade_class, subject, lesson_date)
        if not summary:
            return jsonify({"status": "none"})
        return jsonify({
            "status": "ready",
            "summaryId": summary["id"],
            "text": summary["text"],
            "authors": summary["authors"],
            "highlights": summary["highlights"],
            "partCount": summary["partCount"],
            "totalMinutes": summary["totalMinutes"],
            "images": summary["images"],
        })
    finally:
        cursor.close()
        conn.close()


@bp.route('/homework/analysis/attachment/<int:analysis_id>/<int:index>', methods=['GET'])
@rate_limit('default')
def get_analysis_attachment(analysis_id, index):
    """фотография, приложенная учителем или одноклассником"""
    grade_class, error = _resolve_grade_class_for_request()
    if error:
        return error

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500
    cursor = conn.cursor()
    try:
        cursor.execute(
            "SELECT attachments FROM homework_analysis WHERE id = %s AND grade_class = %s",
            (analysis_id, grade_class))
        row = cursor.fetchone()
        attachments = (row[0] if row else None) or []
        if index < 0 or index >= len(attachments):
            return jsonify({"error": "Not found"}), 404
        path = attachments[index].get('path')
        if not path or not os.path.exists(path):
            return jsonify({"error": "Not found"}), 404
        return send_file(path)
    finally:
        cursor.close()
        conn.close()
