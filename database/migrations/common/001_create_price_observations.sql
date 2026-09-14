BEGIN;

CREATE TABLE IF NOT EXISTS price_observations (
    id UUID PRIMARY KEY,
    instrument_code VARCHAR(80) NOT NULL,
    instrument_name VARCHAR(180) NOT NULL,
    category VARCHAR(30) NOT NULL,
    price NUMERIC(18, 6) NOT NULL,
    currency VARCHAR(3) NOT NULL,
    unit VARCHAR(80) NOT NULL,
    source VARCHAR(80) NOT NULL,
    source_series_id VARCHAR(160) NOT NULL,
    source_period DATE NOT NULL,
    scheduled_for TIMESTAMPTZ NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL,
    source_url TEXT NOT NULL,
    raw_data JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uq_instrument_slot'
          AND conrelid = 'price_observations'::regclass
    ) THEN
        ALTER TABLE price_observations
            ADD CONSTRAINT uq_instrument_slot UNIQUE (instrument_code, scheduled_for);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_price_positive'
          AND conrelid = 'price_observations'::regclass
    ) THEN
        ALTER TABLE price_observations
            ADD CONSTRAINT ck_price_positive CHECK (price > 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_category_known'
          AND conrelid = 'price_observations'::regclass
    ) THEN
        ALTER TABLE price_observations
            ADD CONSTRAINT ck_category_known CHECK (category IN ('crude_oil', 'gasoline'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'ck_currency_iso_length'
          AND conrelid = 'price_observations'::regclass
    ) THEN
        ALTER TABLE price_observations
            ADD CONSTRAINT ck_currency_iso_length CHECK (char_length(currency) = 3);
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS ix_observation_instrument_period
    ON price_observations (instrument_code, source_period);

CREATE INDEX IF NOT EXISTS ix_observation_scheduled_for
    ON price_observations (scheduled_for DESC);

COMMIT;
