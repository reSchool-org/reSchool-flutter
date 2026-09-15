import time


def student_context(state, now_ms=None):
    user = state.get('user') or {}
    position = user.get('currentPosition') or {}
    if position.get('posTypeCode') != 'P':
        return {'prsId': user.get('prsId'), 'userId': state.get('userId') or user.get('userId')}

    children = [child for child in position.get('myChildren', [])
                if isinstance(child, dict) and type(child.get('prsId')) is int and child['prsId'] > 0]
    if not children:
        raise ValueError('В родительском аккаунте нет доступного ребёнка')
    child = next((child for child in children if child.get('isDefaultChild')), children[0])
    now_ms = time.time() * 1000 if now_ms is None else now_ms
    enrollments = [item for item in child.get('userData', [])
                   if isinstance(item, dict) and item.get('orgIsReady') and item.get('userId')]
    current = [item for item in enrollments
               if isinstance(item.get('fullStartDate'), (int, float))
               and isinstance(item.get('fullEndDate'), (int, float))
               and item['fullStartDate'] <= now_ms <= item['fullEndDate']]
    enrollment = next(iter(current), None) or next(
        (item for item in enrollments if item.get('yearState') == 'CURR'), None)
    if enrollment is None and enrollments:
        enrollment = max(enrollments, key=lambda item: item.get('fullStartDate') or 0)
    return {'prsId': child['prsId'], 'userId': (enrollment or {}).get('userId')}
