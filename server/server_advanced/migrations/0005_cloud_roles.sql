ALTER TABLE cf3_registrations
    ADD COLUMN cloud_role VARCHAR(16) NOT NULL DEFAULT 'admin'
    CHECK (cloud_role IN ('admin', 'user'));

ALTER TABLE classmate_registrations
    ADD COLUMN monitoring_registration_id VARCHAR(64)
    REFERENCES cf3_registrations(id) ON DELETE CASCADE;

CREATE UNIQUE INDEX idx_classmate_monitoring
    ON classmate_registrations (monitoring_registration_id);

CREATE TABLE cloud_invites (
    token_hash VARCHAR(64) PRIMARY KEY,
    grade_class VARCHAR(32) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    used_at TIMESTAMP
);

CREATE TABLE cloud_server_bot (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    token_encrypted TEXT NOT NULL,
    username VARCHAR(64) NOT NULL,
    owner_registration_id VARCHAR(64)
        REFERENCES cf3_registrations(id) ON DELETE SET NULL
);
