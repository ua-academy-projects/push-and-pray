CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS observations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    instrument_id TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('crypto', 'fiat')),
    base_code TEXT NOT NULL,
    quote_code TEXT NOT NULL,
    price NUMERIC(38, 18) NOT NULL CHECK (price > 0),
    change_24h_percent NUMERIC(20, 10),
    market_cap NUMERIC(38, 8),
    rank INTEGER,
    source TEXT NOT NULL,
    source_timestamp TIMESTAMPTZ NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'success',
    request_id UUID NOT NULL,
    raw_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source, instrument_id, source_timestamp)
);

CREATE INDEX IF NOT EXISTS observations_instrument_requested_idx
    ON observations (instrument_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS observations_requested_idx
    ON observations (requested_at DESC);
