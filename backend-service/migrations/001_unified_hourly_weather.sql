-- Migration 001: unified hourly weather schema
-- Safe to re-run (all operations are idempotent).

-- Drop legacy tables that are no longer used.
DROP TABLE IF EXISTS weather_requests;
DROP TABLE IF EXISTS weather_forecast_state;
DROP TABLE IF EXISTS weather_forecast_points;

-- Unified hourly data table.
-- PRIMARY KEY (location_key, weather_at) prevents duplicate rows
-- for the same location and hour.
-- relative_humidity and wind_speed are nullable because forecast
-- data does not include them.
CREATE TABLE IF NOT EXISTS weather_hourly_points (
    location_key TEXT NOT NULL,
    weather_at TIMESTAMPTZ NOT NULL,
    temperature DOUBLE PRECISION NOT NULL,
    relative_humidity DOUBLE PRECISION,
    wind_speed DOUBLE PRECISION,
    temperature_unit TEXT NOT NULL DEFAULT '°C',
    humidity_unit TEXT NOT NULL DEFAULT '%',
    wind_speed_unit TEXT NOT NULL DEFAULT 'km/h',
    provider TEXT NOT NULL DEFAULT 'open-meteo',
    data_kind TEXT NOT NULL
        CHECK (data_kind IN ('current', 'forecast', 'historical')),
    source_generated_at TIMESTAMPTZ,
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (location_key, weather_at)
);

-- If the table already exists with NOT NULL columns, relax them.
ALTER TABLE weather_hourly_points
    ALTER COLUMN relative_humidity DROP NOT NULL;

ALTER TABLE weather_hourly_points
    ALTER COLUMN wind_speed DROP NOT NULL;

-- Ensure the constraint matches the current allowed values.
ALTER TABLE weather_hourly_points
    DROP CONSTRAINT IF EXISTS weather_hourly_points_data_kind_check;

ALTER TABLE weather_hourly_points
    ADD CONSTRAINT weather_hourly_points_data_kind_check
    CHECK (data_kind IN ('current', 'forecast', 'historical')) NOT VALID;

ALTER TABLE weather_hourly_points
    VALIDATE CONSTRAINT weather_hourly_points_data_kind_check;

-- Indexes for common query patterns.
CREATE INDEX IF NOT EXISTS weather_hourly_points_time_idx
ON weather_hourly_points (location_key, weather_at DESC);

CREATE INDEX IF NOT EXISTS weather_hourly_points_kind_time_idx
ON weather_hourly_points (location_key, data_kind, weather_at DESC);

-- Sync state: records the last successful fetch time per location.
CREATE TABLE IF NOT EXISTS weather_sync_state (
    location_key TEXT PRIMARY KEY,
    forecast_last_success_at TIMESTAMPTZ,
    forecast_window_start TIMESTAMPTZ,
    forecast_window_end TIMESTAMPTZ,
    history_last_success_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (
        (forecast_window_start IS NULL AND forecast_window_end IS NULL)
        OR (
            forecast_window_start IS NOT NULL
            AND forecast_window_end IS NOT NULL
            AND forecast_window_end >= forecast_window_start
        )
    )
);
