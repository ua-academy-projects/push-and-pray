ALTER TABLE observations
    ADD COLUMN IF NOT EXISTS instrument_name TEXT NOT NULL DEFAULT '',
    ADD COLUMN IF NOT EXISTS change_1h_percent NUMERIC(20, 10);

CREATE INDEX IF NOT EXISTS observations_instrument_source_idx
    ON observations (instrument_id, source_timestamp DESC);
