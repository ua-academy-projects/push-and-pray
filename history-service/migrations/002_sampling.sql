ALTER TABLE observations
    DROP CONSTRAINT IF EXISTS observations_source_instrument_id_source_timestamp_key;

CREATE UNIQUE INDEX IF NOT EXISTS observations_sample_unique_idx
    ON observations (source, instrument_id, source_timestamp, requested_at);

CREATE INDEX IF NOT EXISTS observations_instrument_sample_idx
    ON observations (instrument_id, requested_at ASC);
