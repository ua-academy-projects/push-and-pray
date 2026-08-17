BEGIN;

CREATE TABLE IF NOT EXISTS price_events (
    id UUID PRIMARY KEY,
    event_key VARCHAR(200) NOT NULL,
    schema_version SMALLINT NOT NULL DEFAULT 1,
    payload JSONB NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    attempts INTEGER NOT NULL DEFAULT 0,
    available_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processing_started_at TIMESTAMPTZ,
    processed_at TIMESTAMPTZ,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_price_events_event_key UNIQUE (event_key),
    CONSTRAINT ck_price_events_schema_version_positive CHECK (schema_version > 0),
    CONSTRAINT ck_price_events_payload_object CHECK (jsonb_typeof(payload) = 'object'),
    CONSTRAINT ck_price_events_status_known CHECK (
        status IN ('pending', 'processing', 'processed', 'failed')
    ),
    CONSTRAINT ck_price_events_attempts_non_negative CHECK (attempts >= 0)
);

CREATE INDEX IF NOT EXISTS ix_price_events_ready
    ON price_events (available_at, created_at)
    WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS ix_price_events_processing_started_at
    ON price_events (processing_started_at)
    WHERE status = 'processing';

COMMENT ON TABLE price_events IS
    'Durable PostgreSQL queue for versioned price-observation events.';
COMMENT ON COLUMN price_events.event_key IS
    'Producer-defined idempotency key; retries reuse the same value.';
COMMENT ON COLUMN price_events.payload IS
    'Complete versioned price-observation event encoded as a JSON object.';
COMMENT ON COLUMN price_events.status IS
    'Processing state: pending, processing, processed, or failed.';
COMMENT ON COLUMN price_events.attempts IS
    'Number of processing attempts started by History workers.';
COMMENT ON COLUMN price_events.available_at IS
    'Earliest time at which a pending event may be claimed.';
COMMENT ON COLUMN price_events.processing_started_at IS
    'Time at which the current or most recent processing attempt started.';

COMMIT;
