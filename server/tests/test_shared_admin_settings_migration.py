"""переход с раздельных настроек проверяется в изолированной схеме PostgreSQL"""

import os
from pathlib import Path
import unittest
import uuid


@unittest.skipUnless(os.getenv('RESCHOOL_TEST_DATABASE_URL'), 'нужна отдельная RESCHOOL_TEST_DATABASE_URL')
class SharedAdminSettingsMigrationTests(unittest.TestCase):
    def test_existing_settings_survive_and_device_credentials_stay_separate(self):
        import psycopg
        from psycopg import sql
        schema = 'settings_migration_' + uuid.uuid4().hex
        migrations = Path(__file__).resolve().parents[1] / 'server_advanced' / 'migrations'
        with psycopg.connect(os.environ['RESCHOOL_TEST_DATABASE_URL']) as conn:
            conn.execute(sql.SQL('CREATE SCHEMA {}').format(sql.Identifier(schema)))
            conn.execute(sql.SQL('SET LOCAL search_path TO {}').format(sql.Identifier(schema)))
            for migration in sorted(migrations.glob('*.sql')):
                if migration.name.startswith('0008_'):
                    break
                conn.execute(migration.read_text())
            conn.execute('''INSERT INTO cf3_registrations
                (id, username, password_encrypted, fcm_token, registration_secret_hash,
                 telegram_enabled, telegram_bot_token, telegram_user_id, telegram_group_enabled,
                 telegram_group_chat_id, check_interval_minutes, check_interval_max_minutes, created_at)
                VALUES ('old', 'student', 'password-one', 'push-one', 'secret-one',
                    TRUE, '123:TEST', '55', TRUE, '-123', 17, 29, '2026-09-01'),
                    ('new', 'student', 'password-two', 'push-two', 'secret-two',
                    FALSE, NULL, NULL, FALSE, NULL, 10, NULL, '2026-09-11')''')
            conn.execute((migrations / '0008_shared_admin_settings.sql').read_text())
            rows = conn.execute('''SELECT telegram_enabled, telegram_bot_token, telegram_user_id,
                telegram_group_enabled, telegram_group_chat_id, check_interval_minutes,
                check_interval_max_minutes FROM cf3_registrations ORDER BY id''').fetchall()
            self.assertEqual(rows, [(True, '123:TEST', '55', True, '-123', 17, 29)] * 2)
            self.assertEqual(conn.execute('''SELECT password_encrypted, fcm_token, registration_secret_hash
                FROM cf3_registrations WHERE id = 'new' ''').fetchone(),
                ('password-two', 'push-two', 'secret-two'))
            self.assertEqual(conn.execute("SELECT cf3_account_primary('new')").fetchone()[0], 'old')
            conn.execute((migrations / '0009_remove_push_delivery.sql').read_text())
            self.assertEqual(conn.execute("""SELECT column_name FROM information_schema.columns
                WHERE table_schema = current_schema() AND table_name IN ('cf3_registrations', 'classmate_registrations')
                AND column_name IN ('fcm_token', 'relay_device_token')""").fetchall(), [])
            self.assertEqual(conn.execute("SELECT count(*) FROM cf3_registrations").fetchone()[0], 2)
            self.assertEqual(conn.execute("SELECT telegram_group_chat_id FROM cf3_registrations WHERE id = 'new'").fetchone()[0], '-123')
            conn.rollback()
