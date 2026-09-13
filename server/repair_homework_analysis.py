"""ремонт запускаем при остановленном сервере и после копии базы; по умолчанию только проверяем, уведомления не отправляем"""
import argparse
import json

from server_advanced import analysis
from server_advanced.database import get_db_connection, json_value
from server_advanced.school_dates import school_date


def repair(snapshot, apply=False):
    by_id = {str(hw['id']): hw for hw in snapshot if hw.get('id') is not None}
    conn = get_db_connection()
    if not conn:
        raise RuntimeError('Database unavailable')
    cursor = conn.cursor(dictionary=True)
    changes = []
    slots = set()
    try:
        cursor.execute('SELECT * FROM homework_analysis ORDER BY id FOR UPDATE')
        for row in cursor.fetchall():
            old_date = row['lesson_date']
            new_date = str(old_date) if old_date else None
            hw = by_id.get(str(row['source_id'])) if row['source'] == 'teacher' else None
            # сверяем личность и содержимое задания, чтобы не перенести чужую версию
            if (hw and hw.get('date') and hw.get('subject') == row['subject']
                    and analysis._normalize(hw.get('text')) == analysis._normalize(row['raw_text'])):
                new_date = school_date(hw['date'])
            moved = new_date != (str(old_date) if old_date else None)
            unsupported = (row['status'] == 'done' and row['estimable']
                           and not row['sources'] and not row['attachments']
                           and analysis._requires_source(row['raw_text'], row['targets'] or [], {}))
            if not moved and not unsupported:
                continue
            changes.append({'id': row['id'], 'subject': row['subject'],
                            'old_date': str(old_date), 'date': new_date,
                            'remove_unsupported_estimate': bool(unsupported)})
            slots.add((row['grade_class'], row['subject'], str(old_date)))
            slots.add((row['grade_class'], row['subject'], new_date))
            if moved:
                digest = analysis.dedup_hash(row['grade_class'], row['subject'], new_date, row['raw_text'])
                cursor.execute('SELECT id FROM homework_analysis WHERE dedup_hash = %s AND id <> %s',
                               (digest, row['id']))
                if cursor.fetchone():
                    raise RuntimeError(f"Date repair conflict for analysis {row['id']}; review before merging")
                cursor.execute('UPDATE homework_analysis SET lesson_date = %s, dedup_hash = %s WHERE id = %s',
                               (new_date, digest, row['id']))
                cursor.execute('SELECT id, data, body FROM pending_notifications WHERE analysis_id = %s',
                               (row['id'],))
                for notification in cursor.fetchall():
                    data = dict(notification['data'] or {}, date=new_date)
                    body = notification['body'] or ''
                    if body.startswith('Дата:'):
                        body = 'Дата: ' + '.'.join(reversed(new_date.split('-'))) + '\n' + body.partition('\n')[2]
                    cursor.execute('UPDATE pending_notifications SET data = %s, body = %s WHERE id = %s',
                                   (json_value(data), body, notification['id']))
            if unsupported:
                cursor.execute('''UPDATE homework_analysis SET estimable = FALSE, items = '[]'::jsonb,
                    total_minutes = NULL, range_min = NULL, range_max = NULL, hardest = NULL, why = NULL,
                    unestimable_reason = %s WHERE id = %s''',
                    ('Нет текста заданий: загрузите нужный учебник или приложите фото страниц/условий. '
                     'По одним номерам нельзя определить время и сложность.', row['id']))
        # пересобираем новым воркером только существовавшие сводки, статус отправки уведомлений сохраняем
        for grade, subject, day in slots:
            cursor.execute('''UPDATE homework_merge SET status = 'pending', parts_hash = NULL
                              WHERE grade_class = %s AND subject = %s AND lesson_date = %s RETURNING id''',
                           (grade, subject, day))
            if cursor.fetchone():
                cursor.execute('''INSERT INTO ai_jobs (kind, dedup_key, payload)
                                  VALUES ('merge_homework', %s, %s) ON CONFLICT DO NOTHING''',
                               (f'merge:{grade}|{subject}|{day}', json_value({
                                   'grade_class': grade, 'subject': subject, 'lesson_date': day})))
        print(json.dumps({'apply': apply, 'changes': changes}, ensure_ascii=False))
        if apply:
            conn.commit()
        else:
            conn.rollback()
        return changes
    except Exception:
        conn.rollback()
        raise
    finally:
        cursor.close()
        conn.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', help='JSON list from authenticated fetch_data_with_session')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    with open(args.snapshot) as source:
        repair(json.load(source), args.apply)
