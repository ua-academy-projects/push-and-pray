BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE TABLE IF NOT EXISTS ui_sessions (
    session_hash BYTEA PRIMARY KEY,
    preferences JSONB NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT ck_ui_session_hash_sha256 CHECK (octet_length(session_hash) = 32),
    CONSTRAINT ck_ui_session_preferences_object CHECK (jsonb_typeof(preferences) = 'object')
);

CREATE INDEX IF NOT EXISTS ix_ui_sessions_expires_at
    ON ui_sessions (expires_at);

SELECT cron.schedule(
    'delete-expired-ui-sessions',
    '* * * * *',
    $$DELETE FROM public.ui_sessions WHERE expires_at <= CURRENT_TIMESTAMP$$
);

COMMIT;
