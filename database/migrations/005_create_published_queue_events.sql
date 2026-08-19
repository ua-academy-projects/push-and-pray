BEGIN;

CREATE TABLE IF NOT EXISTS published_queue_events (
    event_key TEXT PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMIT;