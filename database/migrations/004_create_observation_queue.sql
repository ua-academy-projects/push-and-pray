BEGIN;

CREATE TABLE IF NOT EXISTS observation_queue (
    msg_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message JSONB NOT NULL,
    read_count INTEGER NOT NULL DEFAULT 0,
    enqueued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    visible_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_observation_queue_visible
    ON observation_queue (visible_at, msg_id);

CREATE TABLE IF NOT EXISTS observation_queue_archive (
    msg_id BIGINT PRIMARY KEY,
    message JSONB NOT NULL,
    read_count INTEGER NOT NULL,
    enqueued_at TIMESTAMPTZ NOT NULL,
    archived_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMIT;
