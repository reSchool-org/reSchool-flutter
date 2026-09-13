"""проверяем поиск миграций, контрольные суммы и разбор sql без базы"""

import hashlib
import importlib.util
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch


SERVER = Path(__file__).resolve().parents[1]
PACKAGE = '_migrations_backend'


def load_migrator(allow_drift=False):
    package = types.ModuleType(PACKAGE)
    package.__path__ = []
    modules = {PACKAGE: package}
    for name, attributes in {
        f'{PACKAGE}.config': {
            'SCRIPT_DIR': str(SERVER / 'server_advanced'),
            'MIGRATIONS_ALLOW_CHECKSUM_DRIFT': allow_drift,
        },
        f'{PACKAGE}.logging_utils': {'log': Mock()},
    }.items():
        modules[name] = types.ModuleType(name)
        modules[name].__dict__.update(attributes)
    spec = importlib.util.spec_from_file_location(
        f'{PACKAGE}.migrator', SERVER / 'server_advanced' / 'migrator.py'
    )
    module = importlib.util.module_from_spec(spec)
    with patch.dict(sys.modules, modules):
        spec.loader.exec_module(module)
    return module


class StatementSplitterTests(unittest.TestCase):
    def setUp(self):
        self.migrator = load_migrator()

    def split(self, sql):
        return self.migrator.split_statements(sql)

    def test_plain_statements(self):
        self.assertEqual(self.split("SELECT 1; SELECT 2;"), ["SELECT 1", "SELECT 2"])

    def test_trailing_statement_without_semicolon(self):
        self.assertEqual(self.split("SELECT 1;\nSELECT 2"), ["SELECT 1", "SELECT 2"])

    def test_semicolon_inside_string_is_not_a_separator(self):
        self.assertEqual(self.split("INSERT INTO t VALUES ('a;b'); SELECT 1"),
                         ["INSERT INTO t VALUES ('a;b')", "SELECT 1"])

    def test_doubled_quote_inside_string(self):
        self.assertEqual(self.split("SELECT 'it''s; fine'; SELECT 2"),
                         ["SELECT 'it''s; fine'", "SELECT 2"])

    def test_backslash_only_escapes_in_e_strings(self):
        # при standard_conforming_strings обратный слеш это обычный символ
        self.assertEqual(self.split(r"SELECT 'C:\'; SELECT 2"), [r"SELECT 'C:\'", "SELECT 2"])
        self.assertEqual(self.split(r"SELECT E'a\';b'; SELECT 2"), [r"SELECT E'a\';b'", "SELECT 2"])

    def test_quoted_identifier(self):
        self.assertEqual(self.split('SELECT "we;ird" FROM t; SELECT 2'),
                         ['SELECT "we;ird" FROM t', 'SELECT 2'])

    def test_dollar_quoted_body(self):
        sql = ("CREATE FUNCTION f() RETURNS trigger AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql;"
               "\nSELECT 1;")
        self.assertEqual(self.split(sql), [
            "CREATE FUNCTION f() RETURNS trigger AS $$ BEGIN RETURN NEW; END; $$ LANGUAGE plpgsql",
            "SELECT 1",
        ])

    def test_tagged_dollar_quoting(self):
        sql = "SELECT $body$ a; $$ b; $body$; SELECT 2;"
        self.assertEqual(self.split(sql), ["SELECT $body$ a; $$ b; $body$", "SELECT 2"])

    def test_lone_dollar_is_not_a_quote(self):
        self.assertEqual(self.split("SELECT 1 $ 2; SELECT 3"), ["SELECT 1 $ 2", "SELECT 3"])

    def test_comments_are_skipped(self):
        sql = "-- a; comment\nSELECT 1; /* another; one */ SELECT 2;"
        self.assertEqual(self.split(sql), ["-- a; comment\nSELECT 1", "/* another; one */ SELECT 2"])

    def test_nested_block_comments(self):
        self.assertEqual(self.split("/* outer /* inner; */ still; */ SELECT 1;"),
                         ["/* outer /* inner; */ still; */ SELECT 1"])

    def test_empty_statements_are_dropped(self):
        self.assertEqual(self.split(";;\nSELECT 1;;"), ["SELECT 1"])


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.migrator = load_migrator()
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def write(self, filename, body="SELECT 1;\n"):
        path = Path(self.dir.name) / filename
        path.write_text(body, encoding='utf-8')
        return path

    def test_orders_by_version_and_hashes_bytes(self):
        self.write("0002_second.sql", "SELECT 2;\n")
        self.write("0001_first.sql", "SELECT 1;\n")
        found = self.migrator.discover(self.dir.name)
        self.assertEqual([m.version for m in found], [1, 2])
        self.assertEqual([m.name for m in found], ['first', 'second'])
        self.assertEqual(found[0].checksum, hashlib.sha256(b"SELECT 1;\n").hexdigest())
        self.assertTrue(all(m.transactional for m in found))

    def test_rejects_bad_filenames(self):
        for filename in ("1_short.sql", "0001-dashes.sql", "0001_Upper.sql", "0001_.sql", "0001_two__scores.sql"):
            with self.subTest(filename=filename):
                path = self.write(filename)
                with self.assertRaises(self.migrator.MigrationError):
                    self.migrator.discover(self.dir.name)
                path.unlink()

    def test_rejects_duplicate_versions(self):
        self.write("0001_first.sql")
        self.write("0001_again.sql")
        with self.assertRaises(self.migrator.MigrationError):
            self.migrator.discover(self.dir.name)

    def test_rejects_empty_migration(self):
        self.write("0001_first.sql", "\n\n")
        with self.assertRaises(self.migrator.MigrationError):
            self.migrator.discover(self.dir.name)

    def test_ignores_non_sql_files(self):
        self.write("0001_first.sql")
        self.write("README.md", "notes")
        self.write(".hidden.sql", "SELECT 1;")
        self.assertEqual(len(self.migrator.discover(self.dir.name)), 1)

    def test_no_transaction_marker_only_counts_in_the_header(self):
        self.write("0001_head.sql", "-- reschool:no-transaction\nCREATE INDEX CONCURRENTLY i ON t (a);\n")
        self.write("0002_body.sql", "SELECT 1;\n-- reschool:no-transaction\n")
        found = self.migrator.discover(self.dir.name)
        self.assertFalse(found[0].transactional)
        self.assertTrue(found[1].transactional)

    def test_marker_must_be_the_whole_comment_line(self):
        # в шаблоне про маркер написано словами, и это не должно его включать
        self.write("0001_mention.sql",
                   "-- поставьте первой строкой: -- reschool:no-transaction\nSELECT 1;\n")
        self.assertTrue(self.migrator.discover(self.dir.name)[0].transactional)

    def test_missing_directory_raises(self):
        with self.assertRaises(self.migrator.MigrationError):
            self.migrator.discover(str(Path(self.dir.name) / 'nope'))


class DriftTests(unittest.TestCase):
    def make(self, migrator, version, name, checksum):
        return migrator.Migration(version=version, name=name, filename=f"{version:04d}_{name}.sql",
                                  path='/unused', sql='SELECT 1;', checksum=checksum, transactional=True)

    def test_clean_state_passes(self):
        migrator = load_migrator()
        migrations = [self.make(migrator, 1, 'first', 'aa')]
        applied = {1: {'name': 'first', 'checksum': 'aa', 'applied_at': None}}
        self.assertTrue(migrator._check_drift(migrations, applied))

    def test_pending_migration_is_not_drift(self):
        migrator = load_migrator()
        migrations = [self.make(migrator, 1, 'first', 'aa'), self.make(migrator, 2, 'second', 'bb')]
        applied = {1: {'name': 'first', 'checksum': 'aa', 'applied_at': None}}
        self.assertTrue(migrator._check_drift(migrations, applied))

    def test_edited_applied_migration_blocks(self):
        migrator = load_migrator()
        migrations = [self.make(migrator, 1, 'first', 'changed')]
        applied = {1: {'name': 'first', 'checksum': 'aa', 'applied_at': None}}
        self.assertFalse(migrator._check_drift(migrations, applied))

    def test_deleted_applied_migration_blocks(self):
        migrator = load_migrator()
        applied = {1: {'name': 'first', 'checksum': 'aa', 'applied_at': None}}
        self.assertFalse(migrator._check_drift([], applied))

    def test_drift_can_be_allowed_on_purpose(self):
        migrator = load_migrator(allow_drift=True)
        migrations = [self.make(migrator, 1, 'first', 'changed')]
        applied = {1: {'name': 'first', 'checksum': 'aa', 'applied_at': None}}
        self.assertTrue(migrator._check_drift(migrations, applied))


class CreateMigrationTests(unittest.TestCase):
    def setUp(self):
        self.migrator = load_migrator()
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)

    def test_creates_next_version_from_a_free_form_name(self):
        first = self.migrator.create_migration("Add homework pinned!", self.dir.name)
        self.assertEqual(Path(first).name, "0001_add_homework_pinned.sql")
        second = self.migrator.create_migration("drop old column", self.dir.name)
        self.assertEqual(Path(second).name, "0002_drop_old_column.sql")
        self.assertEqual(len(self.migrator.discover(self.dir.name)), 2)

    def test_generated_file_is_transactional_by_default(self):
        self.migrator.create_migration("thing", self.dir.name)
        self.assertTrue(self.migrator.discover(self.dir.name)[0].transactional)

    def test_rejects_a_name_without_letters_or_digits(self):
        with self.assertRaises(self.migrator.MigrationError):
            self.migrator.create_migration("---", self.dir.name)


class ShippedMigrationsTests(unittest.TestCase):
    def test_comment_rewrites_keep_previously_recorded_checksums(self):
        migrator = load_migrator()
        migrations = {m.filename: m for m in migrator.discover()}
        applied = {}
        for filename, (rewritten, original) in migrator.COMMENT_ONLY_CHECKSUMS.items():
            with self.subTest(migration=filename):
                migration = migrations[filename]
                self.assertEqual(hashlib.sha256(Path(migration.path).read_bytes()).hexdigest(),
                                 rewritten)
                self.assertEqual(migration.checksum, original)
                applied[migration.version] = {
                    'name': migration.name, 'checksum': original, 'applied_at': None,
                }
        self.assertTrue(migrator._check_drift(list(migrations.values()), applied))

    def test_further_edits_to_comment_rewrites_still_block_startup(self):
        migrator = load_migrator()
        for filename, (_, original) in migrator.COMMENT_ONLY_CHECKSUMS.items():
            raw = (SERVER / 'server_advanced' / 'migrations' / filename).read_bytes()
            for extra in (b'\nSELECT 42;\n', '\n-- новая правка\n'.encode()):
                with self.subTest(migration=filename, extra=extra):
                    with tempfile.TemporaryDirectory() as directory:
                        (Path(directory) / filename).write_bytes(raw + extra)
                        migration = migrator.discover(directory)[0]
                    self.assertEqual(migration.checksum, hashlib.sha256(raw + extra).hexdigest())
                    applied = {migration.version: {
                        'name': migration.name, 'checksum': original, 'applied_at': None,
                    }}
                    self.assertFalse(migrator._check_drift([migration], applied))

    def test_renamed_migration_does_not_inherit_a_checksum_alias(self):
        migrator = load_migrator()
        for filename in migrator.COMMENT_ONLY_CHECKSUMS:
            with self.subTest(migration=filename):
                raw = (SERVER / 'server_advanced' / 'migrations' / filename).read_bytes()
                with tempfile.TemporaryDirectory() as directory:
                    (Path(directory) / '0999_renamed.sql').write_bytes(raw)
                    migration = migrator.discover(directory)[0]
                self.assertEqual(migration.checksum, hashlib.sha256(raw).hexdigest())

    def test_repository_migrations_are_valid(self):
        migrator = load_migrator()
        migrations = migrator.discover()
        self.assertTrue(migrations)
        self.assertEqual(migrations[0].version, 1)
        self.assertEqual([m.version for m in migrations],
                         list(range(1, len(migrations) + 1)))
        for migration in migrations:
            with self.subTest(migration=migration.filename):
                self.assertTrue(migrator.split_statements(migration.sql))


if __name__ == '__main__':
    unittest.main()
