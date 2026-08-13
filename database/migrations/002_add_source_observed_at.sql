BEGIN;

ALTER TABLE price_observations
    ADD COLUMN IF NOT EXISTS source_observed_at TIMESTAMPTZ;

UPDATE price_observations
SET source_observed_at = source_period::timestamp AT TIME ZONE 'UTC'
WHERE source_observed_at IS NULL;

ALTER TABLE price_observations
    ALTER COLUMN source_observed_at SET NOT NULL;

CREATE INDEX IF NOT EXISTS ix_observation_source_observed_at
    ON price_observations (source_observed_at DESC);

CREATE INDEX IF NOT EXISTS ix_observation_instrument_observed_at
    ON price_observations (instrument_code, source_observed_at DESC);

COMMIT;
