CREATE TABLE IF NOT EXISTS weather_history (
    id              SERIAL PRIMARY KEY,
    requested_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    city            TEXT NOT NULL,
    latitude        DOUBLE PRECISION,
    longitude       DOUBLE PRECISION,
    temperature     DOUBLE PRECISION,
    windspeed       DOUBLE PRECISION,
    source          TEXT NOT NULL DEFAULT 'open-meteo',
    status          TEXT NOT NULL DEFAULT 'ok',
    raw_response    JSONB
);

CREATE INDEX IF NOT EXISTS idx_weather_history_requested_at
    ON weather_history (requested_at DESC);

-- Погодинний прогноз: один рядок на кожну (місто, конкретну годину).
-- UNIQUE(city, forecast_hour) дає змогу робити UPSERT - при повторному
-- отриманні прогнозу для тієї ж години значення оновлюється, а не дублюється.
CREATE TABLE IF NOT EXISTS weather_hourly (
    id                  SERIAL PRIMARY KEY,
    city                TEXT NOT NULL,
    latitude            DOUBLE PRECISION,
    longitude           DOUBLE PRECISION,
    forecast_hour       TIMESTAMPTZ NOT NULL,
    temperature         DOUBLE PRECISION,
    precipitation       DOUBLE PRECISION,
    weathercode         INTEGER,
    windspeed           DOUBLE PRECISION,
    forecast_fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (city, forecast_hour)
);

CREATE INDEX IF NOT EXISTS idx_weather_hourly_city_hour
    ON weather_hourly (city, forecast_hour);

-- Якщо таблиця вже існувала зі старої версії схеми (без цих колонок) -
-- додає їх, нічого не ламаючи в уже існуючих даних.
ALTER TABLE weather_hourly ADD COLUMN IF NOT EXISTS precipitation DOUBLE PRECISION;
ALTER TABLE weather_hourly ADD COLUMN IF NOT EXISTS weathercode INTEGER;
