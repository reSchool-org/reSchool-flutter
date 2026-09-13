-- повтор запроса после обрыва сети должен вернуть то же подключение
CREATE TABLE cloud_join_attempts (
    request_hash VARCHAR(64) PRIMARY KEY,
    result_encrypted TEXT NOT NULL,
    registration_id VARCHAR(64) REFERENCES cf3_registrations(id) ON DELETE CASCADE,
    classmate_id VARCHAR(64) REFERENCES classmate_registrations(id) ON DELETE CASCADE,
    expires_at TIMESTAMP NOT NULL DEFAULT (LOCALTIMESTAMP + INTERVAL '1 day')
);
