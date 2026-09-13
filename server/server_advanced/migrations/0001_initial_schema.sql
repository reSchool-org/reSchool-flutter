-- базовая схема reSchool на postgres
-- это первая миграция, дальше схему меняем только новыми файлами рядом
-- всё тут идемпотентно нарочно: миграция должна лечь и на базу,
-- которую успели создать старым schema.sql до появления реестра версий

-- postgres не умеет ON UPDATE CURRENT_TIMESTAMP, так что штампуем время триггером
CREATE OR REPLACE FUNCTION touch_updated_at() RETURNS trigger AS $$
BEGIN
    NEW.updated_at := (now() AT TIME ZONE 'utc');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- куки собственного аккаунта сервера, строка тут всегда одна, с id = 1
CREATE TABLE IF NOT EXISTS server_sessions (
    id          INTEGER      PRIMARY KEY,
    cookies     TEXT         NOT NULL,
    updated_at  TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);


-- подтверждённые устройства, на каждое своё устройство своя строка
CREATE TABLE IF NOT EXISTS verified_users (
    token        VARCHAR(64)  PRIMARY KEY,
    prs_id       INTEGER      NOT NULL,
    device_name  VARCHAR(128),
    full_name    VARCHAR(256),
    grade_class  VARCHAR(32),
    created_at   TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS idx_verified_users_prs_id ON verified_users (prs_id);


-- одноразовые коды подтверждения, точность до миллисекунд нужна,
-- чтобы отсечь сообщения, отправленные до выдачи кода
CREATE TABLE IF NOT EXISTS verification_challenges (
    code_hash      VARCHAR(64)  PRIMARY KEY,
    target_prs_id  INTEGER      NOT NULL,
    issued_at      TIMESTAMP(3) NOT NULL,
    expires_at     TIMESTAMP(3) NOT NULL,
    consumed_at    TIMESTAMP(3)
);

CREATE INDEX IF NOT EXISTS idx_verification_challenges_expires
    ON verification_challenges (expires_at);


-- регистрации на пуши, тут же лежат настройки телеграма и снимок последнего опроса
CREATE TABLE IF NOT EXISTS cf3_registrations (
    id                        VARCHAR(64)  PRIMARY KEY,
    username                  VARCHAR(256) NOT NULL,
    full_name                 VARCHAR(256),
    grade_class               VARCHAR(32),
    password_encrypted        TEXT         NOT NULL,
    fcm_token                 TEXT,
    relay_device_token        VARCHAR(64),
    check_interval_minutes    INTEGER      NOT NULL DEFAULT 10,
    verification_token        VARCHAR(64),
    registration_secret_hash  VARCHAR(64),
    is_classmate              BOOLEAN      NOT NULL DEFAULT FALSE,
    last_check_at             TIMESTAMP,
    last_homework_ids         TEXT,
    last_grade_ids            TEXT,
    last_notification_ids     TEXT,
    known_subjects            TEXT,
    chat_forward_map          TEXT,
    selected_period_id        INTEGER,
    selected_period_name      VARCHAR(128),
    telegram_enabled          BOOLEAN      NOT NULL DEFAULT FALSE,
    telegram_bot_token        VARCHAR(128),
    telegram_user_id          VARCHAR(64),
    telegram_group_enabled    BOOLEAN      NOT NULL DEFAULT FALSE,
    telegram_group_chat_id    VARCHAR(64),
    telegram_group_title      VARCHAR(255),
    telegram_topic_map        TEXT,
    session_invalid           BOOLEAN      NOT NULL DEFAULT FALSE,
    session_invalid_reason    VARCHAR(255),
    session_invalid_at        TIMESTAMP,
    created_at                TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at                TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

-- по этому индексу монитор выбирает, кого пора проверить
CREATE INDEX IF NOT EXISTS idx_cf3_registrations_next_check
    ON cf3_registrations (last_check_at);
CREATE INDEX IF NOT EXISTS idx_cf3_registrations_verification_token
    ON cf3_registrations (verification_token);
CREATE INDEX IF NOT EXISTS idx_cf3_registrations_grade_class
    ON cf3_registrations (grade_class);

DROP TRIGGER IF EXISTS trg_cf3_registrations_touch ON cf3_registrations;
CREATE TRIGGER trg_cf3_registrations_touch
    BEFORE UPDATE ON cf3_registrations
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();


-- куки eSchool каждой регистрации, redis держит их горячую копию
CREATE TABLE IF NOT EXISTS cf3_sessions (
    registration_id  VARCHAR(64) PRIMARY KEY
        REFERENCES cf3_registrations (id) ON DELETE CASCADE,
    cookies          TEXT      NOT NULL,
    updated_at       TIMESTAMP NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

DROP TRIGGER IF EXISTS trg_cf3_sessions_touch ON cf3_sessions;
CREATE TRIGGER trg_cf3_sessions_touch
    BEFORE UPDATE ON cf3_sessions
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();


-- хэши содержимого, по ним ловим правки уже виденных заданий и оценок
CREATE TABLE IF NOT EXISTS cf3_item_hashes (
    registration_id  VARCHAR(64) NOT NULL
        REFERENCES cf3_registrations (id) ON DELETE CASCADE,
    item_type        VARCHAR(16) NOT NULL
        CHECK (item_type IN ('homework', 'grade', 'message')),
    item_id          VARCHAR(64) NOT NULL,
    content_hash     VARCHAR(64) NOT NULL,
    updated_at       TIMESTAMP   NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    PRIMARY KEY (registration_id, item_type, item_id)
);

CREATE INDEX IF NOT EXISTS idx_cf3_item_hashes_reg_type
    ON cf3_item_hashes (registration_id, item_type);


-- история отправленных уведомлений, data лежит нативным jsonb
CREATE TABLE IF NOT EXISTS cf3_notification_history (
    id                 BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    registration_id    VARCHAR(64)  NOT NULL
        REFERENCES cf3_registrations (id) ON DELETE CASCADE,
    notification_type  VARCHAR(16)  NOT NULL
        CHECK (notification_type IN ('homework', 'grade', 'message', 'welcome')),
    title              VARCHAR(512) NOT NULL,
    body               TEXT,
    data               JSONB,
    sent_at            TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS idx_cf3_notification_history_feed
    ON cf3_notification_history (registration_id, sent_at DESC);


-- приглашения одноклассников, живут недолго и срабатывают один раз
CREATE TABLE IF NOT EXISTS classmate_invite_tokens (
    token                       VARCHAR(64) PRIMARY KEY,
    created_by_registration_id  VARCHAR(64),
    grade_class                 VARCHAR(32),
    expires_at                  TIMESTAMP   NOT NULL,
    used_at                     TIMESTAMP,
    created_at                  TIMESTAMP   NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS idx_classmate_invite_tokens_expires
    ON classmate_invite_tokens (expires_at);
CREATE INDEX IF NOT EXISTS idx_classmate_invite_tokens_author
    ON classmate_invite_tokens (created_by_registration_id);


-- одноклассники, кредов eSchool у них нет, только пуши и общая домашка
CREATE TABLE IF NOT EXISTS classmate_registrations (
    id                  VARCHAR(64)  PRIMARY KEY,
    display_name        VARCHAR(256),
    grade_class         VARCHAR(32)  NOT NULL,
    device_name         VARCHAR(128),
    fcm_token           TEXT         NOT NULL,
    classmate_token     VARCHAR(64)  NOT NULL,
    relay_device_token  VARCHAR(64),
    created_at          TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at          TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS idx_classmate_registrations_grade_class
    ON classmate_registrations (grade_class);
CREATE UNIQUE INDEX IF NOT EXISTS idx_classmate_registrations_token
    ON classmate_registrations (classmate_token);

DROP TRIGGER IF EXISTS trg_classmate_registrations_touch ON classmate_registrations;
CREATE TRIGGER trg_classmate_registrations_touch
    BEFORE UPDATE ON classmate_registrations
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();


-- история уведомлений одноклассников, отдельная, без ссылки на cf3_registrations
CREATE TABLE IF NOT EXISTS classmate_notification_history (
    id                 BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    classmate_id       VARCHAR(64)  NOT NULL,
    notification_type  VARCHAR(16)  NOT NULL
        CHECK (notification_type IN ('homework', 'grade', 'message', 'welcome')),
    title              VARCHAR(512) NOT NULL,
    body               TEXT,
    data               JSONB,
    sent_at            TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS idx_classmate_notification_history_feed
    ON classmate_notification_history (classmate_id, sent_at DESC);


-- своя домашка класса, автор либо подтверждённый ученик, либо одноклассник
CREATE TABLE IF NOT EXISTS custom_homework (
    id                   BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    author_prs_id        INTEGER      NOT NULL,
    author_full_name     VARCHAR(256),
    author_classmate_id  VARCHAR(64),
    grade_class          VARCHAR(32)  NOT NULL,
    subject              VARCHAR(256) NOT NULL,
    lesson_date          DATE         NOT NULL,
    text                 TEXT         NOT NULL,
    created_at           TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
    updated_at           TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS idx_custom_homework_grade_class_date
    ON custom_homework (grade_class, lesson_date);
CREATE INDEX IF NOT EXISTS idx_custom_homework_author
    ON custom_homework (author_prs_id);

DROP TRIGGER IF EXISTS trg_custom_homework_touch ON custom_homework;
CREATE TRIGGER trg_custom_homework_touch
    BEFORE UPDATE ON custom_homework
    FOR EACH ROW EXECUTE FUNCTION touch_updated_at();


-- вложения своей домашки, сами файлы лежат на диске по storage_path
CREATE TABLE IF NOT EXISTS custom_homework_files (
    id            BIGINT GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
    homework_id   BIGINT       NOT NULL
        REFERENCES custom_homework (id) ON DELETE CASCADE,
    file_name     VARCHAR(512) NOT NULL,
    file_size     BIGINT       NOT NULL,
    mime_type     VARCHAR(128),
    storage_path  VARCHAR(512) NOT NULL,
    uploaded_at   TIMESTAMP    NOT NULL DEFAULT (now() AT TIME ZONE 'utc')
);

CREATE INDEX IF NOT EXISTS idx_custom_homework_files_homework
    ON custom_homework_files (homework_id);
