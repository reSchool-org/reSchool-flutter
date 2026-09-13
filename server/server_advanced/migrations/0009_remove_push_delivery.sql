-- прежний способ доставки отключаем новой миграцией, уже применённую схему не переписываем
ALTER TABLE cf3_registrations DROP COLUMN IF EXISTS relay_device_token;
ALTER TABLE cf3_registrations DROP COLUMN IF EXISTS fcm_token;
ALTER TABLE classmate_registrations DROP COLUMN IF EXISTS relay_device_token;
ALTER TABLE classmate_registrations DROP COLUMN IF EXISTS fcm_token;
UPDATE pending_notifications
SET payload = payload - 'relay_device_token' - 'fcm_token'
WHERE payload ?| ARRAY['relay_device_token', 'fcm_token'];
