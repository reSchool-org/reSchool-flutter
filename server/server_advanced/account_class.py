"""класс аккаунта получаем через его собственную сессию"""

from datetime import datetime, timezone

import requests

from .config import BASE_URL, USER_AGENT
from .logging_utils import log
from .student_context import student_context


def _date(value):
    try:
        if type(value) in (int, float):
            return datetime.fromtimestamp(value / 1000 if abs(value) > 10_000_000_000 else value, timezone.utc)
        if isinstance(value, str) and value.strip():
            parsed = datetime.fromisoformat(value.strip().replace('Z', '+00:00'))
            return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed
    except (ValueError, OverflowError, OSError):
        pass
    return None


def pick_account_class(classes):
    if not isinstance(classes, list):
        return None
    now = datetime.now(timezone.utc)
    current, current_from, fallback = None, None, None
    for item in classes:
        if not isinstance(item, dict):
            continue
        name = item.get('name') or item.get('groupName') or item.get('className')
        if not isinstance(name, str) or not 0 < len(name.strip()) <= 32:
            continue
        name = name.strip()
        fallback = name
        start = _date(item.get('dtFrom', item.get('begDate', item.get('bvt'))))
        end = _date(item.get('dtTo', item.get('endDate', item.get('evt'))))
        if ((start or end) and (start is None or start <= now) and (end is None or now <= end)
                and (current is None or (start and (current_from is None or start > current_from)))):
            current, current_from = name, start
    return current or fallback


def resolve_account_class(cookies, prs_id):
    if not cookies or type(prs_id) is not int or prs_id <= 0:
        return None

    def get(path, params=None):
        try:
            response = requests.get(
                BASE_URL + path, params=params, cookies=cookies,
                headers={'Accept': 'application/json', 'User-Agent': USER_AGENT},
                timeout=15, allow_redirects=False,
            )
            try:
                return response.json() if response.status_code == 200 else None
            finally:
                response.close()
        except Exception as error:
            log(f'[Cloud] Account class lookup failed: {type(error).__name__}')
            return None

    state = get('/state')
    user = state.get('user') if isinstance(state, dict) else None
    if not isinstance(user, dict) or type(user.get('prsId')) is not int or user['prsId'] != prs_id:
        return None
    try:
        student = student_context(state)
    except ValueError:
        return None
    user_id = student['userId']
    prs_id = student['prsId']
    if type(user_id) is int and user_id > 0:
        grade = pick_account_class(get('/usr/getClassByUser', {'userId': user_id}))
        if grade:
            return grade
    profile = get('/profile/getProfile_new', {'prsId': prs_id})
    data = profile.get('data') if isinstance(profile, dict) else None
    if not isinstance(data, dict) or type(data.get('prsId')) is not int or data['prsId'] != prs_id:
        return None
    return pick_account_class(profile.get('pupil'))
