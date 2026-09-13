-- админские установки одного точного логина eSchool имеют общие настройки
-- секреты регистрации, токены пушей, сессии и курсоры остаются у устройств
CREATE INDEX idx_cf3_admin_account ON cf3_registrations (username, created_at, id)
    WHERE cloud_role = 'admin';

CREATE FUNCTION cf3_account_primary(registration_id VARCHAR) RETURNS VARCHAR
LANGUAGE sql STABLE AS $$
    SELECT peer.id FROM cf3_registrations source
    JOIN cf3_registrations peer ON peer.username = source.username
        AND peer.cloud_role = 'admin'
    WHERE source.id = registration_id AND source.cloud_role = 'admin'
    ORDER BY peer.created_at, peer.id LIMIT 1
$$;

-- при объединении выбираем существующую настройку телеграма, затем самую раннюю регистрацию
-- updated_at меняется монитором, поэтому по нему нельзя судить о правках
WITH source AS MATERIALIZED (
    SELECT DISTINCT ON (username) * FROM cf3_registrations
    WHERE cloud_role = 'admin'
    ORDER BY username,
        (telegram_enabled OR telegram_group_enabled OR telegram_bot_token IS NOT NULL
            OR telegram_user_id IS NOT NULL) DESC, created_at, id
)
UPDATE cf3_registrations target SET
        check_interval_minutes = source.check_interval_minutes,
        check_interval_max_minutes = source.check_interval_max_minutes,
        telegram_enabled = source.telegram_enabled,
        telegram_bot_token = source.telegram_bot_token,
        telegram_user_id = source.telegram_user_id,
        telegram_group_enabled = source.telegram_group_enabled,
        telegram_group_chat_id = source.telegram_group_chat_id,
        telegram_group_title = source.telegram_group_title,
        telegram_topic_map = source.telegram_topic_map,
        chat_forward_map = source.chat_forward_map,
        selected_period_id = source.selected_period_id,
        selected_period_name = source.selected_period_name
FROM source WHERE target.username = source.username AND target.cloud_role = 'admin';

-- блокировка берётся до блокировок строк, поэтому одновременные записи с двух
-- устройств не расходятся и не захватывают строки в противоположном порядке
CREATE FUNCTION cf3_lock_account_settings() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(7723002);
    RETURN NULL;
END
$$;
CREATE TRIGGER cf3_settings_insert_lock BEFORE INSERT ON cf3_registrations
    FOR EACH STATEMENT EXECUTE FUNCTION cf3_lock_account_settings();
CREATE TRIGGER cf3_settings_update_lock BEFORE UPDATE OF check_interval_minutes, check_interval_max_minutes, telegram_enabled, telegram_bot_token, telegram_user_id, telegram_group_enabled, telegram_group_chat_id, telegram_group_title, telegram_topic_map, chat_forward_map, selected_period_id, selected_period_name
    ON cf3_registrations FOR EACH STATEMENT EXECUTE FUNCTION cf3_lock_account_settings();

CREATE FUNCTION cf3_inherit_account_settings() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE source cf3_registrations%ROWTYPE;
BEGIN
    IF NEW.cloud_role = 'admin' THEN
        SELECT * INTO source FROM cf3_registrations
        WHERE username = NEW.username AND cloud_role = 'admin'
        ORDER BY created_at, id LIMIT 1;
        IF FOUND THEN
            NEW.check_interval_minutes := source.check_interval_minutes;
            NEW.check_interval_max_minutes := source.check_interval_max_minutes;
            NEW.telegram_enabled := source.telegram_enabled;
            NEW.telegram_bot_token := source.telegram_bot_token;
            NEW.telegram_user_id := source.telegram_user_id;
            NEW.telegram_group_enabled := source.telegram_group_enabled;
            NEW.telegram_group_chat_id := source.telegram_group_chat_id;
            NEW.telegram_group_title := source.telegram_group_title;
            NEW.telegram_topic_map := source.telegram_topic_map;
            NEW.chat_forward_map := source.chat_forward_map;
            NEW.selected_period_id := source.selected_period_id;
            NEW.selected_period_name := source.selected_period_name;
        END IF;
    END IF;
    RETURN NEW;
END
$$;
CREATE TRIGGER cf3_settings_inherit BEFORE INSERT ON cf3_registrations
    FOR EACH ROW EXECUTE FUNCTION cf3_inherit_account_settings();

CREATE FUNCTION cf3_sync_account_settings() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.cloud_role <> 'admin' OR pg_trigger_depth() > 1
        OR ROW(NEW.check_interval_minutes, NEW.check_interval_max_minutes, NEW.telegram_enabled, NEW.telegram_bot_token, NEW.telegram_user_id, NEW.telegram_group_enabled, NEW.telegram_group_chat_id, NEW.telegram_group_title, NEW.telegram_topic_map, NEW.chat_forward_map, NEW.selected_period_id, NEW.selected_period_name) IS NOT DISTINCT FROM ROW(OLD.check_interval_minutes, OLD.check_interval_max_minutes, OLD.telegram_enabled, OLD.telegram_bot_token, OLD.telegram_user_id, OLD.telegram_group_enabled, OLD.telegram_group_chat_id, OLD.telegram_group_title, OLD.telegram_topic_map, OLD.chat_forward_map, OLD.selected_period_id, OLD.selected_period_name) THEN
        RETURN NULL;
    END IF;
    UPDATE cf3_registrations SET
        check_interval_minutes = NEW.check_interval_minutes,
        check_interval_max_minutes = NEW.check_interval_max_minutes,
        telegram_enabled = NEW.telegram_enabled,
        telegram_bot_token = NEW.telegram_bot_token,
        telegram_user_id = NEW.telegram_user_id,
        telegram_group_enabled = NEW.telegram_group_enabled,
        telegram_group_chat_id = NEW.telegram_group_chat_id,
        telegram_group_title = NEW.telegram_group_title,
        telegram_topic_map = NEW.telegram_topic_map,
        chat_forward_map = NEW.chat_forward_map,
        selected_period_id = NEW.selected_period_id,
        selected_period_name = NEW.selected_period_name,
        next_check_at = CASE WHEN
            ROW(NEW.check_interval_minutes, NEW.check_interval_max_minutes)
                IS DISTINCT FROM ROW(OLD.check_interval_minutes, OLD.check_interval_max_minutes)
            THEN clock_timestamp() + make_interval(mins => NEW.check_interval_minutes +
                floor(random() * (COALESCE(NEW.check_interval_max_minutes,
                    NEW.check_interval_minutes) - NEW.check_interval_minutes + 1))::integer)
            ELSE next_check_at END
    WHERE username = NEW.username AND cloud_role = 'admin' AND id <> NEW.id;
    RETURN NULL;
END
$$;
CREATE TRIGGER cf3_settings_sync AFTER UPDATE OF check_interval_minutes, check_interval_max_minutes, telegram_enabled, telegram_bot_token, telegram_user_id, telegram_group_enabled, telegram_group_chat_id, telegram_group_title, telegram_topic_map, chat_forward_map, selected_period_id, selected_period_name
    ON cf3_registrations FOR EACH ROW EXECUTE FUNCTION cf3_sync_account_settings();
