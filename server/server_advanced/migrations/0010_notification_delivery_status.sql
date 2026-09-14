-- Захват очереди не равен доставке. Неизвестный результат после падения
-- процесса не пересылаем автоматически: сообщение могло уже дойти.
ALTER TABLE pending_notifications DROP CONSTRAINT pending_notifications_status_check;
ALTER TABLE pending_notifications ADD CONSTRAINT pending_notifications_status_check
    CHECK (status IN ('pending', 'sending', 'sent', 'failed', 'dropped'));
ALTER TABLE pending_notifications ADD COLUMN attempted_at TIMESTAMP;
ALTER TABLE pending_notifications ADD COLUMN last_error TEXT;
