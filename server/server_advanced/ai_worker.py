"""индексацию и разбор домашних заданий выполняем вне http потока, они идут минутами"""

import os
import socket
import threading
import time
import uuid

from . import analysis, merge, textbook
from .config import ANALYSIS_ENABLED
from .database import get_db_connection, json_value
from .logging_utils import log

WORKER_ID = f"{socket.gethostname()}:{os.getpid()}:{uuid.uuid4().hex[:6]}"
POLL_SECONDS = 10
# задача, зависшая дольше этого, считается брошенной и уходит обратно в очередь
STUCK_MINUTES = 30
MAX_ATTEMPTS = 3

_stop = threading.Event()
_thread = None


def enqueue(conn, kind, payload, dedup_key=None):
    cursor = conn.cursor()
    try:
        cursor.execute("""
            INSERT INTO ai_jobs (kind, dedup_key, payload) VALUES (%s, %s, %s)
            ON CONFLICT DO NOTHING RETURNING id
        """, (kind, dedup_key, json_value(payload)))
        row = cursor.fetchone()
        conn.commit()
        return row[0] if row else None
    finally:
        cursor.close()


def _claim(conn):
    """взять задачу так, чтобы её не взял второй воркер"""
    cursor = conn.cursor()
    try:
        cursor.execute("""
            UPDATE ai_jobs SET status = 'running', locked_at = (now() AT TIME ZONE 'utc'),
                locked_by = %s
            WHERE id = (
                SELECT id FROM ai_jobs
                WHERE status = 'queued' AND run_after <= (now() AT TIME ZONE 'utc')
                ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1
            )
            RETURNING id, kind, payload, attempts
        """, (WORKER_ID,))
        row = cursor.fetchone()
        conn.commit()
        if not row:
            return None
        return {"id": row[0], "kind": row[1], "payload": row[2] or {}, "attempts": row[3]}
    finally:
        cursor.close()


def _finish(conn, job_id, status, error=None, retry_in=None):
    cursor = conn.cursor()
    try:
        if status == "retry":
            cursor.execute("""
                UPDATE ai_jobs SET status = 'queued', attempts = attempts + 1, last_error = %s,
                    locked_at = NULL, locked_by = NULL,
                    run_after = (now() AT TIME ZONE 'utc') + %s * INTERVAL '1 second'
                WHERE id = %s
            """, (str(error)[:500] if error else None, retry_in or 120, job_id))
        else:
            cursor.execute("""
                UPDATE ai_jobs SET status = %s, attempts = attempts + 1, last_error = %s,
                    locked_at = NULL, locked_by = NULL
                WHERE id = %s
            """, (status, str(error)[:500] if error else None, job_id))
        conn.commit()
    finally:
        cursor.close()


def _release_stuck(conn):
    cursor = conn.cursor()
    try:
        cursor.execute("""
            UPDATE ai_jobs SET status = 'queued', locked_at = NULL, locked_by = NULL
            WHERE status = 'running'
              AND locked_at < (now() AT TIME ZONE 'utc') - %s * INTERVAL '1 minute'
        """, (STUCK_MINUTES,))
        if cursor.rowcount:
            log(f"[AIWorker] Вернул в очередь зависших задач: {cursor.rowcount}")
        conn.commit()
    finally:
        cursor.close()


def _run_job(job):
    kind = job["kind"]
    payload = job["payload"]
    if kind == "analyze_homework":
        analysis.run(payload["analysis_id"])
    elif kind == "merge_homework":
        merge.rebuild(payload["grade_class"], payload["subject"], payload["lesson_date"])
    elif kind == "index_textbook":
        textbook.index_textbook(payload["textbook_id"])
    else:
        raise RuntimeError(f"неизвестный тип задачи: {kind}")


def _mark_textbook_failed(textbook_id, error):
    conn = get_db_connection()
    if not conn:
        return
    cursor = conn.cursor()
    try:
        cursor.execute(
            "UPDATE textbooks SET status = 'failed', status_detail = %s WHERE id = %s",
            (str(error)[:500], textbook_id))
        conn.commit()
    finally:
        cursor.close()
        conn.close()


def _loop():
    log(f"[AIWorker] Запущен, id={WORKER_ID}")
    last_watchdog = 0
    while not _stop.is_set():
        conn = get_db_connection()
        if not conn:
            _stop.wait(POLL_SECONDS)
            continue
        try:
            _release_stuck(conn)
            job = _claim(conn)
        except Exception as e:
            log(f"[AIWorker] Не удалось взять задачу: {e}")
            job = None
        finally:
            conn.close()

        if job:
            log(f"[AIWorker] Задача {job['id']} {job['kind']}")
            try:
                _run_job(job)
                conn = get_db_connection()
                if conn:
                    _finish(conn, job["id"], "done")
                    conn.close()
            except Exception as e:
                log(f"[AIWorker] Задача {job['id']} упала: {e}")
                conn = get_db_connection()
                if conn:
                    if job["attempts"] + 1 >= MAX_ATTEMPTS:
                        _finish(conn, job["id"], "failed", e)
                        if job["kind"] == "index_textbook":
                            _mark_textbook_failed(job["payload"].get("textbook_id"), e)
                    else:
                        _finish(conn, job["id"], "retry", e, retry_in=120 * (job["attempts"] + 1))
                    conn.close()
            continue

        # пушей, застрявших из за неподнявшегося разбора, ждать нельзя
        if time.time() - last_watchdog > 60:
            last_watchdog = time.time()
            try:
                analysis.flush_stale()
            except Exception as e:
                log(f"[AIWorker] Сторож отложенных пушей упал: {e}")

        _stop.wait(POLL_SECONDS)
    log("[AIWorker] Остановлен")


def start():
    global _thread
    if not ANALYSIS_ENABLED:
        log("[AIWorker] Разбор выключен через ANALYSIS_ENABLED")
        return
    if _thread and _thread.is_alive():
        return
    _stop.clear()
    _thread = threading.Thread(target=_loop, name="ai-worker", daemon=True)
    _thread.start()


def stop():
    _stop.set()
    if _thread:
        _thread.join(timeout=5)


if __name__ == "__main__":
    from .database import init_db
    init_db()
    try:
        _loop()
    except KeyboardInterrupt:
        _stop.set()
