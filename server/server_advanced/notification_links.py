"""используем один формат ссылок для всех уведомлений из телеграма"""
from urllib.parse import urlencode


def notification_open_url(kind, data):
    if not isinstance(data, dict):
        return None
    if kind in ('homework', 'grade'):
        params = {'type': kind}
        for key in ('date', 'subject', 'lessonId'):
            if data.get(key) is not None:
                params[key] = str(data[key])
        if kind == 'homework' and not data.get('date'):
            return None
    elif kind == 'message':
        thread_id = data.get('threadId') or data.get('id')
        if not thread_id:
            return None
        params = {'type': 'message', 'threadId': str(thread_id)}
        if data.get('msgNum'):
            params['msgNum'] = str(data['msgNum'])
        if data.get('isGroup') in (True, 'true'):
            params['isGroup'] = 'true'
    else:
        return None
    return 'https://reschool.app/open?' + urlencode(params)
