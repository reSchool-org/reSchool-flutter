"""вручную повторяем доставку, когда причина постоянной ошибки уже устранена"""
import argparse
import json

from .database import get_db_connection
from .logging_utils import log
from .telegram_diagnostics import delivery_log


def main():
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest='command', required=True)
    listing = commands.add_parser('list')
    listing.add_argument('--status', choices=['pending', 'sending', 'retry', 'sent', 'failed', 'unknown'])
    listing.add_argument('--limit', type=int, default=30)
    retry = commands.add_parser('retry')
    retry.add_argument('id', type=int)
    retry.add_argument('--allow-unknown', action='store_true', help='после проверки, что неподтверждённая часть не доставлена')
    args = parser.parse_args()
    conn = get_db_connection()
    if not conn:
        parser.exit(1, 'Нет соединения с базой\n')
    try:
        cursor = conn.cursor(dictionary=True)
        if args.command == 'list':
            cursor.execute('''
                SELECT id, notification_type, source_id, status, attempts,
                       next_attempt_at, last_error, created_at, sent_at
                FROM telegram_outbox WHERE (%s::text IS NULL OR status = %s)
                ORDER BY id DESC LIMIT %s
            ''', (args.status, args.status, max(1, min(args.limit, 200))))
            print(json.dumps(cursor.fetchall(), ensure_ascii=False, default=str, indent=2))
        else:
            cursor.execute('''
                UPDATE telegram_outbox SET status = 'retry', attempts = 0,
                    next_attempt_at = (now() AT TIME ZONE 'utc'), locked_until = NULL,
                    updated_at = (now() AT TIME ZONE 'utc')
                WHERE id = %s AND (status IN ('failed', 'retry') OR (status = 'unknown' AND %s))
                RETURNING id
            ''', (args.id, args.allow_unknown))
            if not cursor.fetchone():
                parser.exit(1, 'Повтор не выполнен: проверьте ID и статус. Для unknown сначала проверьте фактическую доставку.\n')
            conn.commit()
            delivery_log(log, 'manual_retry_requested', outbox_id=args.id, allow_unknown=args.allow_unknown)
        cursor.close()
    finally:
        conn.close()


if __name__ == '__main__':
    main()
