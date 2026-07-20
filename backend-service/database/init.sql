-- Database schema for the Air Quality Backend Service.
-- Run this script while connected to the application database.

CREATE TABLE IF NOT EXISTS cities (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    country VARCHAR(100) NOT NULL DEFAULT 'Ukraine',

    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    timezone VARCHAR(100),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT cities_code_not_blank
        CHECK (length(trim(code)) > 0),

    CONSTRAINT cities_name_not_blank
        CHECK (length(trim(name)) > 0),

    CONSTRAINT cities_latitude_valid
        CHECK (latitude BETWEEN -90 AND 90),

    CONSTRAINT cities_longitude_valid
        CHECK (longitude BETWEEN -180 AND 180)
);


CREATE TABLE IF NOT EXISTS air_quality_measurements (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

    city_id BIGINT NOT NULL,

    observed_at TIMESTAMPTZ NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    european_aqi DOUBLE PRECISION,
    us_aqi DOUBLE PRECISION,

    pm2_5 DOUBLE PRECISION,
    pm10 DOUBLE PRECISION,

    nitrogen_dioxide DOUBLE PRECISION,
    ozone DOUBLE PRECISION,
    carbon_monoxide DOUBLE PRECISION,
    uv_index DOUBLE PRECISION,

    source VARCHAR(50) NOT NULL
        DEFAULT 'open-meteo',

    source_status_code SMALLINT NOT NULL
        DEFAULT 200,

    CONSTRAINT fk_measurements_city
        FOREIGN KEY (city_id)
        REFERENCES cities (id)
        ON DELETE CASCADE,

    CONSTRAINT measurements_unique_city_time
        UNIQUE (city_id, observed_at),

    CONSTRAINT measurements_source_not_blank
        CHECK (length(trim(source)) > 0),

    CONSTRAINT measurements_source_status_valid
        CHECK (source_status_code BETWEEN 100 AND 599),

    CONSTRAINT measurements_european_aqi_non_negative
        CHECK (european_aqi IS NULL OR european_aqi >= 0),

    CONSTRAINT measurements_us_aqi_non_negative
        CHECK (us_aqi IS NULL OR us_aqi >= 0),

    CONSTRAINT measurements_pm2_5_non_negative
        CHECK (pm2_5 IS NULL OR pm2_5 >= 0),

    CONSTRAINT measurements_pm10_non_negative
        CHECK (pm10 IS NULL OR pm10 >= 0)
);


CREATE INDEX IF NOT EXISTS idx_measurements_city_observed_at
    ON air_quality_measurements (
        city_id,
        observed_at DESC
    );


CREATE INDEX IF NOT EXISTS idx_measurements_observed_at
    ON air_quality_measurements (
        observed_at DESC
    );


INSERT INTO cities (
    code,
    name,
    country,
    latitude,
    longitude,
    timezone
)
VALUES
    (
        'kyiv',
        'Kyiv',
        'Ukraine',
        50.45466,
        30.5238,
        'Europe/Kyiv'
    ),
    (
        'lviv',
        'Lviv',
        'Ukraine',
        49.83826,
        24.02324,
        'Europe/Kyiv'
    ),
    (
        'odesa',
        'Odesa',
        'Ukraine',
        46.48572,
        30.74383,
        'Europe/Kyiv'
    ),
    (
        'dnipro',
        'Dnipro',
        'Ukraine',
        48.46664,
        35.04066,
        'Europe/Kyiv'
    ),
    (
        'kharkiv',
        'Kharkiv',
        'Ukraine',
        49.98177,
        36.25475,
        'Europe/Kyiv'
    ),
    (
        'cherkasy',
        'Cherkasy',
        'Ukraine',
        49.44452,
        32.05738,
        'Europe/Kyiv'
    )
ON CONFLICT (code)
DO UPDATE SET
    name = EXCLUDED.name,
    country = EXCLUDED.country,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    timezone = EXCLUDED.timezone;