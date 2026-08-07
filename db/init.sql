CREATE TABLE IF NOT EXISTS cities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(120) NOT NULL UNIQUE,
    name_en VARCHAR(120) NOT NULL UNIQUE,
    oblast VARCHAR(160) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);


DO $migration$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'weather_history'
    ) AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'weather_history'
          AND column_name = 'city_id'
    ) THEN
        DROP TABLE IF EXISTS weather_history_legacy CASCADE;
        ALTER TABLE weather_history RENAME TO weather_history_legacy;

        IF EXISTS (
            SELECT 1
            FROM pg_constraint
            WHERE conname = 'weather_history_pkey'
              AND conrelid = 'weather_history_legacy'::regclass
        ) THEN
            ALTER TABLE weather_history_legacy
                RENAME CONSTRAINT weather_history_pkey TO weather_history_legacy_pkey;
        END IF;

        IF to_regclass('public.weather_history_id_seq') IS NOT NULL THEN
            ALTER SEQUENCE weather_history_id_seq
                RENAME TO weather_history_legacy_id_seq;
        END IF;
    END IF;
END
$migration$;

CREATE TABLE IF NOT EXISTS weather_history (
    id BIGSERIAL PRIMARY KEY,
    city_id INTEGER NOT NULL REFERENCES cities(id) ON DELETE RESTRICT,
    country VARCHAR(120) NOT NULL DEFAULT 'Україна',
    temperature DOUBLE PRECISION NOT NULL,
    feels_like DOUBLE PRECISION,
    humidity INTEGER CHECK (humidity IS NULL OR humidity BETWEEN 0 AND 100),
    pressure DOUBLE PRECISION,
    wind_speed DOUBLE PRECISION,
    weather_code INTEGER,
    weather_description VARCHAR(255),
    source VARCHAR(80) NOT NULL DEFAULT 'Open-Meteo',
    observed_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_weather_city_observed UNIQUE (city_id, observed_at)
);

CREATE INDEX IF NOT EXISTS idx_weather_history_city_observed
    ON weather_history(city_id, observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_weather_history_received
    ON weather_history(received_at DESC);

INSERT INTO cities (name, name_en, oblast, latitude, longitude, active)
VALUES
    ('Вінниця', 'Vinnytsia', 'Вінницька область', 49.2331, 28.4682, TRUE),
    ('Луцьк', 'Lutsk', 'Волинська область', 50.7472, 25.3254, TRUE),
    ('Дніпро', 'Dnipro', 'Дніпропетровська область', 48.4647, 35.0462, TRUE),
    ('Донецьк', 'Donetsk', 'Донецька область', 48.0159, 37.8029, TRUE),
    ('Житомир', 'Zhytomyr', 'Житомирська область', 50.2547, 28.6587, TRUE),
    ('Ужгород', 'Uzhhorod', 'Закарпатська область', 48.6208, 22.2879, TRUE),
    ('Запоріжжя', 'Zaporizhzhia', 'Запорізька область', 47.8388, 35.1396, TRUE),
    ('Івано-Франківськ', 'Ivano-Frankivsk', 'Івано-Франківська область', 48.9226, 24.7111, TRUE),
    ('Київ', 'Kyiv', 'Київська область', 50.4501, 30.5234, TRUE),
    ('Кропивницький', 'Kropyvnytskyi', 'Кіровоградська область', 48.5079, 32.2623, TRUE),
    ('Луганськ', 'Luhansk', 'Луганська область', 48.5740, 39.3078, TRUE),
    ('Львів', 'Lviv', 'Львівська область', 49.8397, 24.0297, TRUE),
    ('Миколаїв', 'Mykolaiv', 'Миколаївська область', 46.9750, 31.9946, TRUE),
    ('Одеса', 'Odesa', 'Одеська область', 46.4825, 30.7233, TRUE),
    ('Полтава', 'Poltava', 'Полтавська область', 49.5883, 34.5514, TRUE),
    ('Рівне', 'Rivne', 'Рівненська область', 50.6199, 26.2516, TRUE),
    ('Суми', 'Sumy', 'Сумська область', 50.9077, 34.7981, TRUE),
    ('Тернопіль', 'Ternopil', 'Тернопільська область', 49.5535, 25.5948, TRUE),
    ('Харків', 'Kharkiv', 'Харківська область', 49.9935, 36.2304, TRUE),
    ('Херсон', 'Kherson', 'Херсонська область', 46.6354, 32.6169, TRUE),
    ('Хмельницький', 'Khmelnytskyi', 'Хмельницька область', 49.4229, 26.9871, TRUE),
    ('Черкаси', 'Cherkasy', 'Черкаська область', 49.4444, 32.0598, TRUE),
    ('Чернівці', 'Chernivtsi', 'Чернівецька область', 48.2915, 25.9403, TRUE),
    ('Чернігів', 'Chernihiv', 'Чернігівська область', 51.4982, 31.2893, TRUE)
ON CONFLICT (name) DO UPDATE SET
    name_en = EXCLUDED.name_en,
    oblast = EXCLUDED.oblast,
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    active = EXCLUDED.active,
    updated_at = CURRENT_TIMESTAMP;
