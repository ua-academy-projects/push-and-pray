BEGIN;

CREATE TABLE IF NOT EXISTS ui_sessions (
    session_hash BYTEA PRIMARY KEY,
    preferences JSONB NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT ck_ui_session_hash_sha256 CHECK (octet_length(session_hash) = 32),
    CONSTRAINT ck_ui_session_preferences_object CHECK (
        jsonb_typeof(preferences) = 'object'
    )
);

DO $$
DECLARE
    preferences_type TEXT;
BEGIN
    SELECT columns.udt_name
    INTO preferences_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'ui_sessions'
      AND column_name = 'preferences';

    IF preferences_type = 'hstore' THEN
        EXECUTE 'ALTER TABLE ui_sessions '
            'ALTER COLUMN preferences TYPE JSONB '
            'USING hstore_to_jsonb(preferences)';
    ELSIF preferences_type <> 'jsonb' THEN
        RAISE EXCEPTION 'ui_sessions.preferences has unsupported type %', preferences_type;
    END IF;
END
$$;

ALTER TABLE ui_sessions
    DROP CONSTRAINT IF EXISTS ck_ui_session_preferences_object;

ALTER TABLE ui_sessions
    ADD CONSTRAINT ck_ui_session_preferences_object CHECK (
        jsonb_typeof(preferences) = 'object'
    );

CREATE INDEX IF NOT EXISTS ix_ui_sessions_expires_at
    ON ui_sessions (expires_at);

COMMIT;
