"""миграции выполняются по одному разу, контрольная сумма замечает последующие изменения файла"""

import hashlib
import os
import re
import sys
import time
from collections import namedtuple

from .config import MIGRATIONS_ALLOW_CHECKSUM_DRIFT, SCRIPT_DIR
from .logging_utils import log


MIGRATIONS_DIR = os.path.join(SCRIPT_DIR, 'migrations')

FILENAME_RE = re.compile(r'^(\d{4})_([a-z0-9]+(?:_[a-z0-9]+)*)\.sql$')

# после правки только комментариев сохраняем прежние суммы для существующих баз
# сопоставляем полные байты и имя файла, любая следующая правка снова изменит сумму
COMMENT_ONLY_CHECKSUMS = {
    '0002_textbooks_and_analysis.sql': (
        '8fe39cdc86f1564c96aee91a907b67e9f12016d307d8944f7d7944c094f0a5df',
        'db3d69efa24e1b33ad6a88cad0fee558849389b3b011b518dedabd961f79b179',
    ),
    '0004_homework_summary.sql': (
        '34a436648afb5f90cd8419b62eba2835494f3f4d2e40e74c3a199f48932b6438',
        '441be49b86029c6341208b9153b89d4a249612ac67ea298d4f13327302bb9cbc',
    ),
    '0007_random_check_intervals.sql': (
        'e9fe9839de4d3dba40be492f4e6b30c245034cb2a9ecaa8e26e599e1d8943872',
        '18f12c7fba624f09f7ab1ff78f0fc724adcfe0baf73e37abe39e97dea1372c12',
    ),
    '0008_shared_admin_settings.sql': (
        'b172ea690af1647091546a7de3aa5f0d338bdac90ad13bc6ebccc12308077d3a',
        '6033c0b16e847dbed1b91bc612a1d351a1b20bc2747668662eb8e26884da39ed',
    ),
    '0009_remove_push_delivery.sql': (
        '39f0f557053fcb39ca9f83c8026e81c23f1590eaab14220ad5f8b23a77976766',
        '4634073b07b8cb2b387c5a4785398c4fc9823e44c087eac4e3044ac0049ece1c',
    ),
}


def _migration_checksum(filename, raw):
    checksum = hashlib.sha256(raw).hexdigest()
    rewritten, original = COMMENT_ONLY_CHECKSUMS.get(filename, (None, None))
    return original if checksum == rewritten else checksum


# файл с этой строкой в шапке идёт без транзакции, нужно для CREATE INDEX CONCURRENTLY
NO_TRANSACTION_MARKER = 'reschool:no-transaction'

# произвольная константа, по ней два процесса не полезут накатывать одно и то же
ADVISORY_LOCK_KEY = 7723001

REGISTRY_DDL = """
CREATE TABLE IF NOT EXISTS schema_migrations (
    version      INTEGER     PRIMARY KEY,
    name         TEXT        NOT NULL,
    checksum     CHAR(64)    NOT NULL,
    applied_at   TIMESTAMP   NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    duration_ms  INTEGER     NOT NULL
)
"""

TEMPLATE = """-- миграция {name}
-- накатится один раз и целиком в транзакции
-- если нужна команда, которой транзакция мешает, например CREATE INDEX CONCURRENTLY,
-- поставьте первой строкой файла: -- {marker}

"""


class MigrationError(Exception):
    """миграции разложены неправильно или не легли на базу"""


Migration = namedtuple('Migration', 'version name filename path sql checksum transactional')


# разбор файлов

def _is_escape_string(sql, quote_at):
    """строка вида E'...', только в ней обратный слеш экранирует символы"""
    i = quote_at - 1
    if i < 0 or sql[i] not in 'eE':
        return False
    # перед E не должно быть куска идентификатора, иначе это просто хвост слова
    return i == 0 or not (sql[i - 1].isalnum() or sql[i - 1] == '_')


def _scan_single_quote(sql, i):
    escapes = _is_escape_string(sql, i)
    j = i + 1
    while j < len(sql):
        if escapes and sql[j] == '\\':
            j += 2
            continue
        if sql[j] == "'":
            if j + 1 < len(sql) and sql[j + 1] == "'":
                j += 2
                continue
            return j + 1
        j += 1
    return len(sql)


def _scan_double_quote(sql, i):
    j = i + 1
    while j < len(sql):
        if sql[j] == '"':
            if j + 1 < len(sql) and sql[j + 1] == '"':
                j += 2
                continue
            return j + 1
        j += 1
    return len(sql)


_DOLLAR_TAG_RE = re.compile(r'\$([A-Za-z_][A-Za-z0-9_]*)?\$')


def _scan_dollar_quote(sql, i):
    """тело $$...$$ или $tag$...$tag$, None если это не долларовая кавычка"""
    match = _DOLLAR_TAG_RE.match(sql, i)
    if not match:
        return None
    tag = match.group(0)
    end = sql.find(tag, match.end())
    return len(sql) if end == -1 else end + len(tag)


def _scan_block_comment(sql, i):
    """блочные комментарии в postgres вкладываются друг в друга"""
    depth = 1
    j = i + 2
    while j < len(sql) and depth:
        if sql.startswith('/*', j):
            depth += 1
            j += 2
        elif sql.startswith('*/', j):
            depth -= 1
            j += 2
        else:
            j += 1
    return j


def split_statements(sql):
    """режем файл по точкам с запятой, не спотыкаясь о строки, комментарии и $$"""
    statements = []
    start = 0
    i = 0
    while i < len(sql):
        ch = sql[i]
        if ch == "'":
            i = _scan_single_quote(sql, i)
        elif ch == '"':
            i = _scan_double_quote(sql, i)
        elif ch == '$':
            end = _scan_dollar_quote(sql, i)
            i = i + 1 if end is None else end
        elif sql.startswith('--', i):
            newline = sql.find('\n', i)
            i = len(sql) if newline == -1 else newline + 1
        elif sql.startswith('/*', i):
            i = _scan_block_comment(sql, i)
        elif ch == ';':
            statements.append(sql[start:i])
            i += 1
            start = i
        else:
            i += 1
    statements.append(sql[start:])
    return [s.strip() for s in statements if s.strip()]


def _is_transactional(sql):
    """маркер ищем только в шапке и только целой строкой, чтобы про него не сработал рассказ о нём"""
    for line in sql.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if not stripped.startswith('--'):
            break
        if stripped.lstrip('-').strip() == NO_TRANSACTION_MARKER:
            return False
    return True


def discover(directory=None):
    """все миграции по порядку версий, с проверкой имён и дублей"""
    directory = directory or MIGRATIONS_DIR
    try:
        filenames = sorted(os.listdir(directory))
    except FileNotFoundError:
        raise MigrationError(f"Migrations directory not found: {directory}")

    migrations = []
    seen = {}
    for filename in filenames:
        if filename.startswith('.') or not filename.endswith('.sql'):
            continue
        match = FILENAME_RE.match(filename)
        if not match:
            raise MigrationError(
                f"Bad migration filename {filename!r}, expected NNNN_snake_case_name.sql"
            )
        version = int(match.group(1))
        if version in seen:
            raise MigrationError(f"Duplicate migration version {version:04d}: {seen[version]} and {filename}")
        seen[version] = filename

        path = os.path.join(directory, filename)
        with open(path, 'rb') as f:
            raw = f.read()
        sql = raw.decode('utf-8')
        if not sql.strip():
            raise MigrationError(f"Migration {filename} is empty")

        migrations.append(Migration(
            version=version,
            name=match.group(2),
            filename=filename,
            path=path,
            sql=sql,
            checksum=_migration_checksum(filename, raw),
            transactional=_is_transactional(sql),
        ))

    migrations.sort(key=lambda m: m.version)
    return migrations


# накат

def _ensure_registry(conn):
    conn.execute(REGISTRY_DDL)
    conn.commit()


def _registry_exists(conn):
    cursor = conn.cursor()
    cursor.execute("SELECT to_regclass('schema_migrations') IS NOT NULL")
    found = cursor.fetchone()[0]
    cursor.close()
    conn.rollback()
    return found


def _load_applied(conn):
    if not _registry_exists(conn):
        return {}
    cursor = conn.cursor()
    cursor.execute("SELECT version, name, checksum, applied_at FROM schema_migrations ORDER BY version")
    rows = cursor.fetchall()
    cursor.close()
    conn.rollback()
    return {row[0]: {'name': row[1], 'checksum': row[2], 'applied_at': row[3]} for row in rows}


def _check_drift(migrations, applied):
    """сверяем контрольные суммы, чтобы правка накатанного файла не прошла молча"""
    problems = []
    by_version = {m.version: m for m in migrations}

    for version, record in sorted(applied.items()):
        migration = by_version.get(version)
        if migration is None:
            problems.append(f"migration {version:04d}_{record['name']} is applied but its file is gone")
        elif migration.checksum != record['checksum']:
            problems.append(f"migration {migration.filename} changed after it was applied")

    if not problems:
        return True

    for problem in problems:
        log(f"[Migrations] {problem}")
    if MIGRATIONS_ALLOW_CHECKSUM_DRIFT:
        log("[Migrations] MIGRATIONS_ALLOW_CHECKSUM_DRIFT is on, continuing anyway")
        return True
    log("[Migrations] Refusing to migrate. Add a new migration instead of editing an applied one, "
        "or set MIGRATIONS_ALLOW_CHECKSUM_DRIFT=true if the change is known to be safe")
    return False


def _apply(conn, migration):
    started = time.monotonic()

    if migration.transactional:
        # без параметров psycopg шлёт запрос простым протоколом, так что файл уходит одной пачкой
        conn.execute(migration.sql)
    else:
        # тут транзакции быть не должно, поэтому шлём команды по одной
        conn.commit()
        conn.raw.autocommit = True
        try:
            for statement in split_statements(migration.sql):
                conn.execute(statement)
        finally:
            conn.raw.autocommit = False

    duration_ms = int((time.monotonic() - started) * 1000)
    conn.execute(
        "INSERT INTO schema_migrations (version, name, checksum, duration_ms) VALUES (%s, %s, %s, %s)",
        (migration.version, migration.name, migration.checksum, duration_ms),
    )
    conn.commit()
    return duration_ms


def run_migrations():
    """накатываем всё, что ещё не накатано, True если база в актуальном состоянии"""
    from .database import get_db_connection

    try:
        migrations = discover()
    except MigrationError as e:
        log(f"[Migrations] {e}")
        return False

    conn = get_db_connection()
    if not conn:
        log("[Migrations] Skipping: no database connection")
        return False

    locked = False
    try:
        # блокировку берём до всего остального: CREATE TABLE IF NOT EXISTS в postgres
        # не атомарен, и два одновременных старта роняют друг друга
        # блокировка живёт до конца сессии и переживает коммиты между миграциями
        conn.execute("SELECT pg_advisory_lock(%s)", (ADVISORY_LOCK_KEY,))
        conn.commit()
        locked = True

        _ensure_registry(conn)
        applied = _load_applied(conn)
        if not _check_drift(migrations, applied):
            return False

        pending = [m for m in migrations if m.version not in applied]
        if not pending:
            log(f"[Migrations] Database is up to date ({len(applied)} applied)")
            return True

        for migration in pending:
            log(f"[Migrations] Applying {migration.filename}...")
            try:
                duration_ms = _apply(conn, migration)
            except Exception as e:
                conn.rollback()
                log(f"[Migrations] {migration.filename} failed: {e}")
                if not migration.transactional:
                    log(f"[Migrations] {migration.filename} runs without a transaction, "
                        "so part of it may have been applied, check the database by hand")
                return False
            log(f"[Migrations] Applied {migration.filename} in {duration_ms} ms")

        log(f"[Migrations] Done, {len(pending)} migration(s) applied")
        return True
    except Exception as e:
        conn.rollback()
        log(f"[Migrations] Unexpected error: {e}")
        return False
    finally:
        if locked:
            try:
                conn.execute("SELECT pg_advisory_unlock(%s)", (ADVISORY_LOCK_KEY,))
                conn.commit()
            except Exception:
                pass
        conn.close()


# создание файла

def next_version(migrations=None):
    migrations = discover() if migrations is None else migrations
    return (max((m.version for m in migrations), default=0)) + 1


def slugify(name):
    slug = re.sub(r'[^a-z0-9]+', '_', str(name or '').strip().lower()).strip('_')
    if not slug:
        raise MigrationError("Migration name must contain letters or digits")
    return slug


def create_migration(name, directory=None):
    """заводим пустой файл со следующим номером, возвращаем путь до него"""
    directory = directory or MIGRATIONS_DIR
    slug = slugify(name)
    version = next_version(discover(directory))
    if version > 9999:
        raise MigrationError("Version numbers are limited to 4 digits")

    path = os.path.join(directory, f"{version:04d}_{slug}.sql")
    if os.path.exists(path):
        raise MigrationError(f"{path} already exists")
    with open(path, 'w', encoding='utf-8') as f:
        f.write(TEMPLATE.format(name=slug.replace('_', ' '), marker=NO_TRANSACTION_MARKER))
    return path


# командная строка

def _print_status():
    from .database import get_db_connection

    migrations = discover()
    conn = get_db_connection()
    applied = {}
    if conn:
        # реестр тут только читаем, создавать его дело наката
        try:
            applied = _load_applied(conn)
        finally:
            conn.close()
    else:
        print("database is unreachable, showing files only")

    for migration in migrations:
        record = applied.get(migration.version)
        if record is None:
            state = 'pending'
        elif record['checksum'] != migration.checksum:
            state = 'CHANGED AFTER APPLY'
        else:
            state = f"applied {record['applied_at']:%Y-%m-%d %H:%M:%S}"
        flag = '' if migration.transactional else '  [no-transaction]'
        print(f"{migration.version:04d}  {migration.name:<40} {state}{flag}")

    orphans = sorted(set(applied) - {m.version for m in migrations})
    for version in orphans:
        print(f"{version:04d}  {applied[version]['name']:<40} applied, FILE MISSING")


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    command = argv[0] if argv else 'status'

    try:
        if command == 'status':
            _print_status()
            return 0
        if command == 'up':
            return 0 if run_migrations() else 1
        if command == 'new':
            if len(argv) < 2:
                print("usage: python -m server_advanced.migrator new <name>", file=sys.stderr)
                return 2
            print(create_migration(' '.join(argv[1:])))
            return 0
    except MigrationError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1

    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == '__main__':
    sys.exit(main())
