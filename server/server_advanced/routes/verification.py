import os
import hashlib
import math
import re
import secrets
import uuid
import shutil
from datetime import datetime, timezone

import flask
import requests
from flask import Blueprint, jsonify, request

from .. import config
from ..database import get_db_connection, invalidate_verified_user
from ..config import UPLOAD_FOLDER
from ..rate_limiter import rate_limit
from ..logging_utils import log
from ..eschool_api import server_state, get_messages, get_thread_messages


bp = Blueprint('verification', __name__)


def get_verified_name(prs_id, cookies):
    """имя отправителя спрашиваем у eSchool, клиенту тут верить нельзя
    getProfile_new на чужой prsId отвечает noAccess, короткий профиль отдаёт всем"""
    if type(prs_id) is not int or prs_id <= 0 or not cookies:
        return None
    try:
        response = requests.get(
            f"{config.BASE_URL}/profile/getShortProfile",
            params={'prsId': prs_id}, cookies=cookies,
            headers={'Accept': 'application/json', 'User-Agent': config.USER_AGENT},
            timeout=15, allow_redirects=False,
        )
        try:
            if response.status_code != 200:
                return None
            profile = response.json()
        finally:
            response.close()
        if not isinstance(profile, dict) or not isinstance(profile.get('profile'), dict):
            return None
        basic = profile['profile'].get('prsBasic')
        if (not isinstance(basic, dict) or type(basic.get('prsId')) is not int
                or basic['prsId'] != prs_id):
            return None
        name_parts = [basic.get('lastName'), basic.get('firstName')]
        if basic.get('middleName') is not None:
            name_parts.append(basic['middleName'])
        if any(not isinstance(part, str) or not part.strip() for part in name_parts):
            return None
        full_name = ' '.join(part.strip() for part in name_parts)
        return full_name if 0 < len(full_name) <= 256 else None
    except Exception as e:
        log(f"Verification profile error: {type(e).__name__}")
        return None


def normalize_grade_class(value):
    """класс приходит от клиента: чужой класс по prsId eSchool не отдаёт, взять его больше неоткуда"""
    if not isinstance(value, str):
        return None
    value = value.strip()
    return value if 0 < len(value) <= 32 else None


def find_verified_sender(expected_code, client_thread_id=None):
    """подтверждённую проверку сохраняем только на время этого запроса"""
    flask.g.pop('_verification_proof', None)
    if not server_state.cookies or not server_state.prs_id:
        return None, "Server not authenticated"
    if not isinstance(expected_code, str) or not re.fullmatch(r'[0-9A-F]{32}', expected_code):
        return None, "Invalid or expired verification code"
    if client_thread_id is not None and (type(client_thread_id) is not int or client_thread_id <= 0):
        return None, "Invalid thread ID"

    target_prs_id = server_state.prs_id
    code_hash = hashlib.sha256(expected_code.encode('ascii')).hexdigest()
    conn = get_db_connection()
    if not conn:
        return None, "Database connection failed"
    cursor = None
    try:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT issued_at, LOCALTIMESTAMP(3) FROM verification_challenges
            WHERE code_hash = %s AND target_prs_id = %s
              AND consumed_at IS NULL AND expires_at > LOCALTIMESTAMP(3)
        """, (code_hash, target_prs_id))
        challenge = cursor.fetchone()
    except Exception as e:
        log(f"Verification DB error: {type(e).__name__}")
        return None, "Database error"
    finally:
        if cursor is not None:
            cursor.close()
        conn.close()
    if not challenge:
        return None, "Invalid or expired verification code"

    issued_at, checked_at = challenge
    issued_ms = issued_at.replace(tzinfo=timezone.utc).timestamp() * 1000
    checked_ms = checked_at.replace(tzinfo=timezone.utc).timestamp() * 1000
    try:
        thread_ids = [client_thread_id] if client_thread_id is not None else []
        # превью и id аватарок это метаданные для поиска, личность они не подтверждают
        threads = get_messages(server_state.cookies)
        if not isinstance(threads, list):
            return None, "Verification unavailable"
        for thread in threads[:5]:
            thread_id = thread.get('threadId') if isinstance(thread, dict) else None
            if type(thread_id) is int and thread_id > 0 and thread_id not in thread_ids:
                thread_ids.append(thread_id)
        for thread_id in thread_ids:
            messages = get_thread_messages(server_state.cookies, thread_id)
            if not isinstance(messages, list):
                continue
            for msg in messages:
                if not isinstance(msg, dict) or msg.get('msg') != f"Verification code: {expected_code}":
                    continue
                # scripts.js в eSchool сверяет message.senderId с user.prsId,
                # владельца определяет по нему, а срок правки считает по sendDate в миллисекундах,
                # подменять senderPrsId, imgObjId или изменяемую дату показа нельзя
                prs_id = msg.get('senderId')
                sent_at = msg.get('sendDate')
                if (type(prs_id) is not int or prs_id <= 0 or prs_id == target_prs_id
                        or type(msg.get('msgId')) is not int or msg['msgId'] <= 0
                        or msg.get('isOwner', False) is not False
                        or msg.get('senderPrsId', prs_id) != prs_id
                        or type(sent_at) not in (int, float) or not math.isfinite(sent_at)
                        or not issued_ms < sent_at <= checked_ms):
                    continue

                full_name = get_verified_name(prs_id, server_state.cookies)
                if not full_name:
                    return None, "Sender profile unavailable"
                if server_state.prs_id != target_prs_id:
                    return None, "Server not authenticated"
                flask.g._verification_proof = {
                    'code_hash': code_hash, 'target_prs_id': target_prs_id,
                    'prs_id': prs_id, 'full_name': full_name.strip(),
                }
                return prs_id, None
    except Exception as e:
        log(f"Verification upstream error: {type(e).__name__}")
        return None, "Verification unavailable"
    return None, "Verification code not found"


def issue_verification_token(prs_id, device_name, full_name, grade_class):
    """погашаем подтверждение вместе с записью токена; имя проверяет сервер, класс приходит от клиента"""
    proof = flask.g.pop('_verification_proof', None)
    if not proof or proof['prs_id'] != prs_id or proof['target_prs_id'] != server_state.prs_id:
        return None, "Verification required"
    if not isinstance(device_name, str) or not 0 < len(device_name) <= 128:
        return None, "Invalid device name"
    conn = get_db_connection()
    if not conn:
        return None, "Database connection failed"

    cursor = None
    try:
        cursor = conn.cursor()
        # условный UPDATE держит блокировку строки: забрать её сможет
        # только один проверяющий, а срок годности перепроверяем после всех сетевых вызовов
        cursor.execute("""
            UPDATE verification_challenges SET consumed_at = LOCALTIMESTAMP(3)
            WHERE code_hash = %s AND target_prs_id = %s
              AND consumed_at IS NULL AND expires_at > LOCALTIMESTAMP(3)
        """, (proof['code_hash'], proof['target_prs_id']))
        if cursor.rowcount != 1:
            conn.rollback()
            return None, "Invalid or expired verification code"
        token = str(uuid.uuid4())
        cursor.execute("""
            INSERT INTO verified_users (token, prs_id, device_name, full_name, grade_class)
            VALUES (%s, %s, %s, %s, %s)
        """, (token, prs_id, device_name, proof['full_name'], normalize_grade_class(grade_class)))
        conn.commit()
        return token, None
    except Exception as e:
        conn.rollback()
        log(f"DB Error: {type(e).__name__}")
        return None, "Database error"
    finally:
        if cursor is not None:
            cursor.close()
        conn.close()


@bp.route('/request-verification', methods=['POST'])
@rate_limit('verification')
def request_verification():
    """запрашиваем код подтверждения"""
    if not server_state.prs_id or not server_state.cookies:
        return jsonify({"error": "Server not authenticated"}), 503

    code = secrets.token_hex(16).upper()
    target_prs_id = server_state.prs_id
    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 503
    cursor = None
    try:
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO verification_challenges (code_hash, target_prs_id, issued_at, expires_at)
            VALUES (%s, %s, LOCALTIMESTAMP(3), LOCALTIMESTAMP(3) + INTERVAL '10 minutes')
        """, (hashlib.sha256(code.encode('ascii')).hexdigest(), target_prs_id))
        conn.commit()
    except Exception as e:
        conn.rollback()
        log(f"Verification DB error: {type(e).__name__}")
        return jsonify({"error": "Database error"}), 503
    finally:
        if cursor is not None:
            cursor.close()
        conn.close()
    return jsonify({
        "code": code,
        "targetPrsId": target_prs_id
    })


@bp.route('/check-verification', methods=['POST'])
@rate_limit('verification')
def check_verification():
    """проверяем отправку кода подтверждения"""
    if not server_state.cookies:
        return jsonify({"error": "Server not authenticated"}), 503

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"error": "Invalid request"}), 400
    expected_code = data.get('code')
    client_thread_id = data.get('threadId')

    if not expected_code:
        return jsonify({"error": "No code provided"}), 400

    verified_prs_id, verification_error = find_verified_sender(expected_code, client_thread_id)

    if verified_prs_id:
        device_name = data.get('deviceName', 'Unknown device')
        token, save_error = issue_verification_token(
            verified_prs_id, device_name, None, data.get('gradeClass'))
        if token:
            return jsonify({
                "verified": True,
                "token": token
            })

        return jsonify({"error": save_error or "Database error"}), 500

    if verification_error == "Server not authenticated":
        return jsonify({"error": verification_error}), 503

    return jsonify({"verified": False})


@bp.route('/revoke-token', methods=['POST'])
@rate_limit('devices')
def revoke_token():
    """отзываем токен подтверждения"""
    data = request.json
    token = data.get('token')

    if not token:
        return jsonify({"error": "No token provided"}), 400

    log("Revoking verification token")

    conn = get_db_connection()
    if conn:
        try:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM verified_users WHERE token = %s", (token,))
            rows_affected = cursor.rowcount
            conn.commit()
            cursor.close()
            conn.close()
            invalidate_verified_user(token)

            if rows_affected > 0:
                return jsonify({"success": True, "message": "Token revoked"})
            else:
                return jsonify({"success": False, "message": "Token not found"}), 404
        except Exception as e:
            log(f"DB Error: {type(e).__name__}")
            return jsonify({"error": "Database error"}), 500

    return jsonify({"error": "Database connection failed"}), 500


@bp.route('/delete-all-data', methods=['POST'])
@rate_limit('devices')
def delete_all_data():
    """удаляем данные пользователя с сервера"""
    data = request.json
    token = data.get('token')

    if not token:
        return jsonify({"error": "No token provided"}), 400

    log("Deleting all data for verified user")

    conn = get_db_connection()
    if not conn:
        return jsonify({"error": "Database connection failed"}), 500

    try:
        cursor = conn.cursor()

        # находим prs_id по токену
        cursor.execute("SELECT prs_id FROM verified_users WHERE token = %s", (token,))
        row = cursor.fetchone()

        if not row:
            cursor.close()
            conn.close()
            return jsonify({"error": "Invalid token"}), 401

        prs_id = row[0]
        log(f"Deleting all data for prs_id: {prs_id}")

        # собираем все добавленные пользователем домашние задания
        cursor.execute("SELECT id, grade_class FROM custom_homework WHERE author_prs_id = %s", (prs_id,))
        homework_rows = cursor.fetchall()

        # чистим файлы домашнего задания с диска
        for hw_row in homework_rows:
            hw_id, grade_class = hw_row
            homework_folder = os.path.join(UPLOAD_FOLDER, str(grade_class), str(hw_id))
            if os.path.exists(homework_folder):
                shutil.rmtree(homework_folder, ignore_errors=True)

        # удаляем домашние задания, записи файлов удалятся каскадом
        cursor.execute("DELETE FROM custom_homework WHERE author_prs_id = %s", (prs_id,))
        deleted_homework = cursor.rowcount

        # и все токены с устройствами этого пользователя,
        # заодно вычищаем их из кеша авторизации
        cursor.execute("DELETE FROM verified_users WHERE prs_id = %s RETURNING token", (prs_id,))
        revoked_tokens = [revoked[0] for revoked in cursor.fetchall()]
        deleted_tokens = len(revoked_tokens)

        conn.commit()
        cursor.close()
        conn.close()
        invalidate_verified_user(*revoked_tokens)

        log(f"Deleted {deleted_tokens} tokens and {deleted_homework} homework items for prs_id: {prs_id}")

        return jsonify({
            "success": True,
            "deleted": {
                "tokens": deleted_tokens,
                "homework": deleted_homework
            }
        })

    except Exception as e:
        log(f"Error deleting data: {type(e).__name__}")
        return jsonify({"error": "Database error"}), 500


@bp.route('/list-devices', methods=['POST'])
@rate_limit('devices')
def list_devices():
    """показываем подключённые устройства аккаунта"""
    data = request.json
    token = data.get('token')

    if not token:
        return jsonify({"error": "No token provided"}), 401

    conn = get_db_connection()
    if conn:
        try:
            cursor = conn.cursor()

            # находим prs_id по токену
            cursor.execute("SELECT prs_id FROM verified_users WHERE token = %s", (token,))
            row = cursor.fetchone()

            if not row:
                cursor.close()
                conn.close()
                return jsonify({"error": "Invalid token"}), 401

            prs_id = row[0]

            # берём все устройства этого prs_id
            cursor.execute("""
                SELECT token, device_name, created_at
                FROM verified_users
                WHERE prs_id = %s
                ORDER BY created_at DESC
            """, (prs_id,))
            results = cursor.fetchall()

            devices = []
            for row in results:
                devices.append({
                    "token": row[0],
                    "deviceName": row[1] or "Unknown device",
                    "createdAt": row[2].isoformat() if row[2] else None,
                    "isCurrent": row[0] == token
                })

            cursor.close()
            conn.close()

            return jsonify({"devices": devices})

        except Exception as e:
            log(f"DB Error: {type(e).__name__}")
            return jsonify({"error": "Database error"}), 500

    return jsonify({"error": "Database connection failed"}), 500


@bp.route('/check-verified-users', methods=['POST'])
@rate_limit('token_check')
def check_verified_users():
    """проверяем подтверждение идентификаторов пользователей"""
    data = request.json
    token = data.get('token')
    ids_to_check = data.get('ids')

    if not token:
        return jsonify({"error": "No token provided"}), 401

    if not ids_to_check or not isinstance(ids_to_check, list):
        return jsonify({"verifiedIds": []})

    conn = get_db_connection()
    if conn:
        try:
            cursor = conn.cursor()

            # проверяем, что у запросившего вменяемый токен
            cursor.execute("SELECT prs_id FROM verified_users WHERE token = %s", (token,))
            requester = cursor.fetchone()

            if not requester:
                cursor.close()
                conn.close()
                return jsonify({"error": "Invalid token"}), 401

            # смотрим, какие id из списка подтверждены
            numeric_ids = []
            for raw_id in ids_to_check:
                try:
                    numeric_ids.append(int(raw_id))
                except (TypeError, ValueError):
                    continue
            if not numeric_ids:
                cursor.close()
                conn.close()
                return jsonify({"verifiedIds": []})

            cursor.execute(
                "SELECT DISTINCT prs_id FROM verified_users WHERE prs_id = ANY(%s)",
                (numeric_ids,)
            )
            results = cursor.fetchall()

            verified_ids = [row[0] for row in results]

            cursor.close()
            conn.close()

            return jsonify({"verifiedIds": verified_ids})

        except Exception as e:
            log(f"DB Error: {type(e).__name__}")
            return jsonify({"error": "Database error"}), 500

    return jsonify({"error": "Database connection failed"}), 500
