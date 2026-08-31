BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS hstore;

CREATE OR REPLACE FUNCTION pg_temp.ui_session_preferences_to_hstore(preferences JSONB)
RETURNS HSTORE
LANGUAGE SQL
IMMUTABLE
STRICT
AS $$
    SELECT COALESCE(
        hstore(
            array_agg(key ORDER BY key),
            array_agg(value::text ORDER BY key)
        ),
        ''::hstore
    )
    FROM jsonb_each(preferences)
$$;

CREATE TABLE IF NOT EXISTS ui_sessions (
    session_hash BYTEA PRIMARY KEY,
    preferences HSTORE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT ck_ui_session_hash_sha256 CHECK (octet_length(session_hash) = 32)
);

DO $$
DECLARE
    preferences_type TEXT;
BEGIN
    SELECT format_type(attribute.atttypid, attribute.atttypmod)
    INTO preferences_type
    FROM pg_attribute AS attribute
    WHERE attribute.attrelid = 'public.ui_sessions'::regclass
      AND attribute.attname = 'preferences'
      AND NOT attribute.attisdropped;

    IF preferences_type = 'jsonb' THEN
        ALTER TABLE ui_sessions
            DROP CONSTRAINT IF EXISTS ck_ui_session_preferences_object;
        ALTER TABLE ui_sessions
            ALTER COLUMN preferences TYPE HSTORE
            USING pg_temp.ui_session_preferences_to_hstore(preferences);
    ELSIF preferences_type <> 'hstore' THEN
        RAISE EXCEPTION 'ui_sessions.preferences has unsupported type %', preferences_type;
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS ix_ui_sessions_expires_at
    ON ui_sessions (expires_at);

SELECT cron.schedule(
    'delete-expired-ui-sessions',
    '* * * * *',
    $$DELETE FROM public.ui_sessions WHERE expires_at <= CURRENT_TIMESTAMP$$
);

COMMIT;
