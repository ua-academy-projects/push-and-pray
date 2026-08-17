BEGIN;

CREATE TABLE IF NOT EXISTS ui_sessions (
    session_id VARCHAR(128) PRIMARY KEY,
    preferences JSONB NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_ui_sessions_id_length CHECK (char_length(session_id) BETWEEN 32 AND 128),
    CONSTRAINT ck_ui_sessions_preferences_object CHECK (
        jsonb_typeof(preferences) = 'object'
    )
);

CREATE INDEX IF NOT EXISTS ix_ui_sessions_expires_at
    ON ui_sessions (expires_at);

COMMENT ON TABLE ui_sessions IS
    'Server-side UI preferences with application-managed sliding expiration.';
COMMENT ON COLUMN ui_sessions.preferences IS
    'Complete validated UI preference document encoded as a JSON object.';
COMMENT ON COLUMN ui_sessions.expires_at IS
    'Expiration time refreshed by the UI service when a session is accessed.';

COMMIT;
