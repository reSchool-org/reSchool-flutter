-- верхняя граница NULL означает фиксированный интервал
-- следующую проверку планируем один раз, а не при каждом проходе монитора
ALTER TABLE cf3_registrations
    ADD COLUMN check_interval_max_minutes INTEGER,
    ADD COLUMN next_check_at TIMESTAMP,
    ADD CONSTRAINT cf3_interval_range_valid CHECK (
        check_interval_max_minutes IS NULL OR (
            check_interval_max_minutes > check_interval_minutes
            AND check_interval_max_minutes <= 1440
        )
    );

CREATE INDEX idx_cf3_registrations_scheduled_check
    ON cf3_registrations (next_check_at)
    WHERE COALESCE(session_invalid, FALSE) = FALSE;
