import atexit
import os
import threading
from datetime import datetime, timedelta, timezone

import psycopg
import requests
from apscheduler.schedulers.background import BackgroundScheduler
from flask import Flask, jsonify, request
from psycopg.rows import dict_row

app = Flask(__name__)

DATABASE_URL = os.getenv("DATABASE_URL")

PROVIDER_URL = os.getenv(
    "PROVIDER_URL",
    "http://127.0.0.1:5002",
).rstrip("/")

REQUEST_TIMEOUT = 10

# Scheduler: run once per hour
SYNC_INTERVAL_MINUTES = 60

FORECAST_HOURS = 24
HISTORY_HOURS = 168

ALLOWED_HISTORY_HOURS = {24, 168}

CITY_NAME = "Надвірна"
COUNTRY_NAME = "Україна"
LATITUDE = 48.6348
LONGITUDE = 24.5694
WEATHER_TIMEZONE = "Europe/Kyiv"
LOCATION_KEY = "nadvirna"

TEMPERATURE_UNIT = "°C"
HUMIDITY_UNIT = "%"
WIND_SPEED_UNIT = "km/h"

scheduler = BackgroundScheduler(
    timezone=WEATHER_TIMEZONE
)

sync_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Custom exceptions
# ---------------------------------------------------------------------------

class ProviderServiceError(Exception):
    def __init__(
        self,
        message,
        status_code=502,
    ):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def is_debug_enabled():
    return os.getenv("FLASK_DEBUG", "false").lower() in {
        "1",
        "true",
        "yes",
    }


def floor_to_hour(dt: datetime) -> datetime:
    """Truncate a datetime to the start of its hour (UTC)."""
    utc = dt.astimezone(timezone.utc)
    return utc.replace(minute=0, second=0, microsecond=0)


def parse_datetime(value):
    if not value:
        return None

    try:
        normalized_value = value.replace(
            "Z",
            "+00:00",
        )

        parsed_value = datetime.fromisoformat(
            normalized_value
        )

        if parsed_value.tzinfo is None:
            parsed_value = parsed_value.replace(
                tzinfo=timezone.utc
            )

        return parsed_value.astimezone(
            timezone.utc
        )

    except (
        AttributeError,
        TypeError,
        ValueError,
    ):
        return None


# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------

def get_connection():
    if not DATABASE_URL:
        raise RuntimeError(
            "DATABASE_URL is not configured."
        )

    return psycopg.connect(
        DATABASE_URL,
        row_factory=dict_row,
    )


def create_tables():
    """Apply migration SQL to ensure the schema exists."""
    migrations_dir = os.path.join(
        os.path.dirname(__file__),
        "migrations",
    )

    migration_file = os.path.join(
        migrations_dir,
        "001_unified_hourly_weather.sql",
    )

    if not os.path.isfile(migration_file):
        app.logger.warning(
            "Migration file not found: %s",
            migration_file,
        )
        return

    with open(migration_file, encoding="utf-8") as fh:
        migration_sql = fh.read()

    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(migration_sql)
            # Fix any corrupt historical rows that are in the future
            cursor.execute(
                """
                UPDATE weather_hourly_points
                SET data_kind = 'forecast'
                WHERE data_kind = 'historical'
                  AND weather_at > NOW();
                """
            )

    app.logger.info(
        "Schema migration applied: %s",
        migration_file,
    )


# ---------------------------------------------------------------------------
# Provider helpers
# ---------------------------------------------------------------------------

def _raise_for_provider_response(response):
    """Parse provider JSON and raise ProviderServiceError on failure."""
    try:
        data = response.json()
    except ValueError as error:
        raise ProviderServiceError(
            "Provider Service повернув некоректну відповідь."
        ) from error

    if not isinstance(data, dict):
        raise ProviderServiceError(
            "Provider Service повернув некоректну відповідь."
        )

    if not response.ok:
        error_message = data.get("error")

        if not isinstance(error_message, str):
            error_message = (
                "Provider Service не зміг отримати дані."
            )

        status_code = (
            response.status_code
            if response.status_code in {502, 504}
            else 502
        )

        raise ProviderServiceError(
            error_message,
            status_code=status_code,
        )

    return data


def fetch_weather_from_provider():
    """Fetch current conditions from provider-service."""
    try:
        response = requests.get(
            f"{PROVIDER_URL}/weather/current",
            params={
                "latitude": LATITUDE,
                "longitude": LONGITUDE,
                "timezone": WEATHER_TIMEZONE,
            },
            timeout=REQUEST_TIMEOUT,
        )

    except requests.Timeout as error:
        raise ProviderServiceError(
            "Provider Service не відповідає вчасно.",
            status_code=503,
        ) from error

    except requests.RequestException as error:
        raise ProviderServiceError(
            "Provider Service недоступний.",
            status_code=503,
        ) from error

    provider_data = _raise_for_provider_response(response)

    current = provider_data.get("current")

    required_fields = {
        "temperature_2m",
        "relative_humidity_2m",
        "wind_speed_10m",
    }

    if (
        not isinstance(current, dict) or
        not required_fields.issubset(current)
    ):
        raise ProviderServiceError(
            "Provider Service повернув неповні погодні дані."
        )

    location = provider_data.get("location")

    if not isinstance(location, dict):
        location = {}

    location.update({
        "name": CITY_NAME,
        "country": COUNTRY_NAME,
        "latitude": LATITUDE,
        "longitude": LONGITUDE,
    })

    return {
        "query": CITY_NAME,
        "location": location,
        "current": current,
        "current_units": provider_data.get(
            "current_units",
            {},
        ),
        "source": provider_data.get(
            "source",
            "open-meteo",
        ),
        "collected_at": provider_data.get(
            "collected_at",
            datetime.now(timezone.utc).isoformat(),
        ),
    }


def fetch_forecast_from_provider():
    """Fetch 24-hour forecast from provider-service."""
    try:
        response = requests.get(
            f"{PROVIDER_URL}/weather/forecast",
            params={
                "latitude": LATITUDE,
                "longitude": LONGITUDE,
                "timezone": WEATHER_TIMEZONE,
            },
            timeout=REQUEST_TIMEOUT,
        )

    except requests.Timeout as error:
        raise ProviderServiceError(
            "Provider Service не відповідає вчасно.",
            status_code=503,
        ) from error

    except requests.RequestException as error:
        raise ProviderServiceError(
            "Provider Service недоступний.",
            status_code=503,
        ) from error

    provider_data = _raise_for_provider_response(response)

    hourly = provider_data.get("hourly")

    if not isinstance(hourly, dict):
        raise ProviderServiceError(
            "Provider Service повернув неповні дані прогнозу."
        )

    times = hourly.get("time")
    temperatures = hourly.get("temperature_2m")

    if (
        not isinstance(times, list) or
        not isinstance(temperatures, list) or
        len(times) != len(temperatures)
    ):
        raise ProviderServiceError(
            "Provider Service повернув неповні дані прогнозу."
        )

    location = provider_data.get("location")

    if not isinstance(location, dict):
        location = {}

    location.update({
        "name": CITY_NAME,
        "country": COUNTRY_NAME,
        "latitude": LATITUDE,
        "longitude": LONGITUDE,
        "timezone": WEATHER_TIMEZONE,
    })

    return {
        "query": CITY_NAME,
        "forecast_hours": FORECAST_HOURS,
        "location": location,
        "hourly": {
            "time": times,
            "temperature_2m": temperatures,
        },
        "hourly_units": provider_data.get(
            "hourly_units",
            {},
        ),
        "source": provider_data.get(
            "source",
            "open-meteo",
        ),
        "generated_at": provider_data.get(
            "generated_at",
            datetime.now(timezone.utc).isoformat(),
        ),
    }


def fetch_history_from_provider(past_hours: int):
    """Fetch historical hourly data from provider-service."""
    try:
        response = requests.get(
            f"{PROVIDER_URL}/weather/history",
            params={
                "latitude": LATITUDE,
                "longitude": LONGITUDE,
                "timezone": WEATHER_TIMEZONE,
                "past_hours": past_hours,
            },
            timeout=REQUEST_TIMEOUT,
        )

    except requests.Timeout as error:
        raise ProviderServiceError(
            "Provider Service не відповідає вчасно.",
            status_code=503,
        ) from error

    except requests.RequestException as error:
        raise ProviderServiceError(
            "Provider Service недоступний.",
            status_code=503,
        ) from error

    provider_data = _raise_for_provider_response(response)

    hourly = provider_data.get("hourly")

    if not isinstance(hourly, dict):
        raise ProviderServiceError(
            "Provider Service повернув неповні історичні дані."
        )

    times = hourly.get("time")
    temperatures = hourly.get("temperature_2m")

    if (
        not isinstance(times, list) or
        not isinstance(temperatures, list) or
        len(times) != len(temperatures)
    ):
        raise ProviderServiceError(
            "Provider Service повернув неповні історичні дані."
        )

    return provider_data


# ---------------------------------------------------------------------------
# Forecast — normalize & save
# ---------------------------------------------------------------------------

def normalize_forecast_points(forecast_data):
    """Parse 24 forecast hourly points from provider data.

    Returns a list of dicts: {forecast_at: datetime (UTC), temperature: float}.
    """
    hourly = forecast_data.get("hourly")

    if not isinstance(hourly, dict):
        raise ProviderServiceError(
            "Provider Service повернув неповні дані прогнозу."
        )

    times = hourly.get("time")
    temperatures = hourly.get("temperature_2m")

    if (
        not isinstance(times, list) or
        not isinstance(temperatures, list) or
        len(times) != FORECAST_HOURS or
        len(temperatures) != FORECAST_HOURS
    ):
        raise ProviderServiceError(
            "Provider Service повинен повернути "
            "24 погодинні точки прогнозу."
        )

    points_by_time = {}

    for raw_time, raw_temperature in zip(
        times,
        temperatures,
    ):
        if (
            not isinstance(raw_time, (int, float)) or
            not isinstance(
                raw_temperature,
                (int, float),
            )
        ):
            raise ProviderServiceError(
                "Provider Service повернув "
                "некоректні точки прогнозу."
            )

        try:
            forecast_at = datetime.fromtimestamp(
                raw_time,
                tz=timezone.utc,
            )

        except (
            OSError,
            OverflowError,
            ValueError,
        ) as error:
            raise ProviderServiceError(
                "Provider Service повернув "
                "некоректний час прогнозу."
            ) from error

        # Truncate to hour boundary to avoid sub-hour duplicates
        forecast_at = floor_to_hour(forecast_at)
        points_by_time[forecast_at] = float(raw_temperature)

    if len(points_by_time) != FORECAST_HOURS:
        raise ProviderServiceError(
            "Provider Service повернув дублікати "
            "часових точок прогнозу."
        )

    ordered_points = [
        {
            "forecast_at": forecast_at,
            "temperature": temperature_value,
        }
        for forecast_at, temperature_value
        in sorted(points_by_time.items())
    ]

    for previous, current in zip(
        ordered_points,
        ordered_points[1:],
    ):
        if (
            current["forecast_at"] -
            previous["forecast_at"]
        ) != timedelta(hours=1):
            raise ProviderServiceError(
                "Provider Service повернув "
                "непослідовні погодинні точки."
            )

    return ordered_points


def save_forecast_points(
    connection,
    points,
    provider,
    fetched_at,
):
    """UPSERT 24 forecast points into weather_hourly_points."""
    with connection.cursor() as cursor:
        cursor.executemany(
            """
            INSERT INTO weather_hourly_points (
                location_key,
                weather_at,
                temperature,
                relative_humidity,
                wind_speed,
                temperature_unit,
                humidity_unit,
                wind_speed_unit,
                provider,
                data_kind,
                source_generated_at,
                fetched_at
            )
            VALUES (
                %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s,
                %s, %s
            )
            ON CONFLICT (location_key, weather_at)
            DO UPDATE SET
                temperature = EXCLUDED.temperature,
                temperature_unit = EXCLUDED.temperature_unit,
                provider = EXCLUDED.provider,
                data_kind = EXCLUDED.data_kind,
                source_generated_at =
                    EXCLUDED.source_generated_at,
                fetched_at = EXCLUDED.fetched_at
            WHERE weather_hourly_points.data_kind
                  = 'forecast';
            """,
            [
                (
                    LOCATION_KEY,
                    point["forecast_at"],
                    point["temperature"],
                    None,   # humidity not in forecast
                    None,   # wind_speed not in forecast
                    TEMPERATURE_UNIT,
                    HUMIDITY_UNIT,
                    WIND_SPEED_UNIT,
                    provider,
                    "forecast",
                    fetched_at,
                    fetched_at,
                )
                for point in points
            ],
        )

    return len(points)


def update_forecast_sync_state(connection, fetched_at):
    """Record the time of the last successful forecast refresh."""
    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO weather_sync_state (
                location_key,
                forecast_last_success_at,
                updated_at
            )
            VALUES (%s, %s, NOW())
            ON CONFLICT (location_key)
            DO UPDATE SET
                forecast_last_success_at =
                    EXCLUDED.forecast_last_success_at,
                updated_at = NOW();
            """,
            (LOCATION_KEY, fetched_at),
        )


def get_forecast_from_database():
    """Return up to 24 forecast points from DB, ordered ASC by time."""
    now_utc = datetime.now(timezone.utc)

    with get_connection() as connection:
        with connection.cursor() as cursor:
            # Grab the sync state so we can report staleness
            cursor.execute(
                """
                SELECT
                    forecast_last_success_at
                FROM weather_sync_state
                WHERE location_key = %s;
                """,
                (LOCATION_KEY,),
            )

            state = cursor.fetchone()

            # Fetch forecast points that are >= current hour
            current_hour = floor_to_hour(now_utc)

            cursor.execute(
                """
                SELECT
                    weather_at,
                    temperature,
                    temperature_unit
                FROM weather_hourly_points
                WHERE location_key = %s
                  AND data_kind = 'forecast'
                  AND weather_at >= %s
                ORDER BY weather_at ASC
                LIMIT %s;
                """,
                (
                    LOCATION_KEY,
                    current_hour,
                    FORECAST_HOURS,
                ),
            )

            points = cursor.fetchall()

    if not points:
        return None

    last_success_at = None

    if state and state.get("forecast_last_success_at"):
        last_success_at = (
            state["forecast_last_success_at"]
            .astimezone(timezone.utc)
        )

    stale = (
        last_success_at is None or
        (now_utc - last_success_at) >= timedelta(hours=2)
    )

    return {
        "query": CITY_NAME,
        "forecast_hours": len(points),
        "location": {
            "name": CITY_NAME,
            "country": COUNTRY_NAME,
            "latitude": LATITUDE,
            "longitude": LONGITUDE,
            "timezone": WEATHER_TIMEZONE,
        },
        "hourly": {
            "time": [
                int(
                    point["weather_at"]
                    .astimezone(timezone.utc)
                    .timestamp()
                )
                for point in points
            ],
            "temperature_2m": [
                point["temperature"]
                for point in points
            ],
        },
        "hourly_units": {
            "time": "unixtime",
            "temperature_2m": (
                points[0]["temperature_unit"]
                if points
                else TEMPERATURE_UNIT
            ),
        },
        "source": "open-meteo",
        "generated_at": (
            last_success_at.isoformat()
            if last_success_at
            else now_utc.isoformat()
        ),
        "last_success_at": (
            last_success_at.isoformat()
            if last_success_at
            else None
        ),
        "stale": stale,
        "storage": "database",
    }


# ---------------------------------------------------------------------------
# History — normalize & save
# ---------------------------------------------------------------------------

def normalize_history_points(provider_data):
    """Parse hourly historical points from provider data.

    Returns list of dicts with keys:
      weather_at, temperature, humidity, wind_speed
    """
    hourly = provider_data.get("hourly")

    if not isinstance(hourly, dict):
        raise ProviderServiceError(
            "Provider Service повернув неповні історичні дані."
        )

    times = hourly.get("time", [])
    temperatures = hourly.get("temperature_2m", [])
    humidities = hourly.get("relative_humidity_2m", [])
    wind_speeds = hourly.get("wind_speed_10m", [])

    points = []

    for idx, raw_time in enumerate(times):
        if not isinstance(raw_time, (int, float)):
            continue

        try:
            weather_at = datetime.fromtimestamp(
                raw_time,
                tz=timezone.utc,
            )
        except (OSError, OverflowError, ValueError):
            continue

        weather_at = floor_to_hour(weather_at)
        now_utc = floor_to_hour(datetime.now(timezone.utc))

        # Ignore any points that are in the future — they are not historical
        if weather_at > now_utc:
            continue

        raw_temp = (
            temperatures[idx]
            if idx < len(temperatures)
            else None
        )

        temperature = (
            float(raw_temp)
            if isinstance(raw_temp, (int, float))
            else None
        )

        if temperature is None:
            # Skip points with no temperature reading
            continue

        raw_hum = (
            humidities[idx]
            if idx < len(humidities)
            else None
        )

        humidity = (
            float(raw_hum)
            if isinstance(raw_hum, (int, float))
            else None
        )

        raw_wind = (
            wind_speeds[idx]
            if idx < len(wind_speeds)
            else None
        )

        wind_speed = (
            float(raw_wind)
            if isinstance(raw_wind, (int, float))
            else None
        )

        points.append({
            "weather_at": weather_at,
            "temperature": temperature,
            "humidity": humidity,
            "wind_speed": wind_speed,
        })

    return points


def save_history_points(connection, points, provider, fetched_at):
    """UPSERT historical points into weather_hourly_points.

    Skips points that already exist in the DB (no overwrite of history).
    """
    if not points:
        return 0

    with connection.cursor() as cursor:
        cursor.executemany(
            """
            INSERT INTO weather_hourly_points (
                location_key,
                weather_at,
                temperature,
                relative_humidity,
                wind_speed,
                temperature_unit,
                humidity_unit,
                wind_speed_unit,
                provider,
                data_kind,
                source_generated_at,
                fetched_at
            )
            VALUES (
                %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s,
                %s, %s
            )
            ON CONFLICT (location_key, weather_at)
            DO UPDATE SET
                temperature = EXCLUDED.temperature,
                relative_humidity =
                    COALESCE(
                        EXCLUDED.relative_humidity,
                        weather_hourly_points.relative_humidity
                    ),
                wind_speed = COALESCE(
                    EXCLUDED.wind_speed,
                    weather_hourly_points.wind_speed
                ),
                provider = EXCLUDED.provider,
                data_kind = EXCLUDED.data_kind,
                fetched_at = EXCLUDED.fetched_at;
            """,
            [
                (
                    LOCATION_KEY,
                    point["weather_at"],
                    point["temperature"],
                    point.get("humidity"),
                    point.get("wind_speed"),
                    TEMPERATURE_UNIT,
                    HUMIDITY_UNIT,
                    WIND_SPEED_UNIT,
                    provider,
                    "historical",
                    fetched_at,
                    fetched_at,
                )
                for point in points
            ],
        )

    return len(points)


def update_history_sync_state(connection, fetched_at):
    """Record the time of the last successful history fetch."""
    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO weather_sync_state (
                location_key,
                history_last_success_at,
                updated_at
            )
            VALUES (%s, %s, NOW())
            ON CONFLICT (location_key)
            DO UPDATE SET
                history_last_success_at =
                    EXCLUDED.history_last_success_at,
                updated_at = NOW();
            """,
            (LOCATION_KEY, fetched_at),
        )


def get_last_historical_hour(connection):
    """Return the most recent weather_at for historical data, or None."""
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT MAX(weather_at) AS last_at
            FROM weather_hourly_points
            WHERE location_key = %s
              AND data_kind = 'historical'
              AND weather_at <= NOW();
            """,
            (LOCATION_KEY,),
        )

        row = cursor.fetchone()

    if row and row.get("last_at"):
        return row["last_at"].astimezone(timezone.utc)

    return None


def get_history_from_database(hours: int):
    """Return up to `hours` hourly historical points from DB, oldest first."""
    now_utc = floor_to_hour(datetime.now(timezone.utc))
    since = now_utc - timedelta(hours=hours)

    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    weather_at,
                    temperature,
                    relative_humidity,
                    wind_speed,
                    temperature_unit,
                    humidity_unit,
                    wind_speed_unit
                FROM weather_hourly_points
                WHERE location_key = %s
                  AND data_kind IN ('historical', 'current')
                  AND weather_at >= %s
                  AND weather_at <= %s
                ORDER BY weather_at ASC
                LIMIT %s;
                """,
                (
                    LOCATION_KEY,
                    since,
                    now_utc,
                    hours + 1,
                ),
            )

            points = cursor.fetchall()

    return [
        {
            "time": int(
                point["weather_at"]
                .astimezone(timezone.utc)
                .timestamp()
            ),
            "temperature": point["temperature"],
            "humidity": point.get("relative_humidity"),
            "wind_speed": point.get("wind_speed"),
            "temperature_unit": point.get(
                "temperature_unit",
                TEMPERATURE_UNIT,
            ),
            "humidity_unit": point.get(
                "humidity_unit",
                HUMIDITY_UNIT,
            ),
            "wind_speed_unit": point.get(
                "wind_speed_unit",
                WIND_SPEED_UNIT,
            ),
        }
        for point in points
    ]


# ---------------------------------------------------------------------------
# Backfill — detect and fill missing historical hours
# ---------------------------------------------------------------------------

def backfill_missing_hours():
    """Fill any gap in historical data since the last recorded hour."""
    now_utc = floor_to_hour(datetime.now(timezone.utc))

    with get_connection() as connection:
        last_at = get_last_historical_hour(connection)

    if last_at is None:
        # No data at all — fetch full HISTORY_HOURS window
        app.logger.info(
            "No historical data found. "
            "Fetching %d hours from provider.",
            HISTORY_HOURS,
        )
        _do_history_fetch(HISTORY_HOURS)
        return

    last_hour = floor_to_hour(last_at)

    # How many hours are missing (not counting the last stored hour itself)
    missing_count = int(
        (now_utc - last_hour).total_seconds() / 3600
    )

    if missing_count <= 0:
        app.logger.info(
            "Historical data is up-to-date "
            "(last: %s).",
            last_hour.isoformat(),
        )
        return

    # Limit to what the API supports
    hours_to_fetch = min(missing_count, HISTORY_HOURS)

    app.logger.info(
        "Backfilling %d missing historical hours "
        "(last recorded: %s).",
        missing_count,
        last_hour.isoformat(),
    )

    _do_history_fetch(hours_to_fetch)


def _do_history_fetch(past_hours: int):
    """Fetch `past_hours` from provider and UPSERT into DB."""
    fetched_at = datetime.now(timezone.utc)

    provider_data = fetch_history_from_provider(past_hours)

    points = normalize_history_points(provider_data)

    provider = provider_data.get("source", "open-meteo")

    with get_connection() as connection:
        saved = save_history_points(
            connection,
            points,
            provider,
            fetched_at,
        )

        update_history_sync_state(connection, fetched_at)

    app.logger.info(
        "Historical data saved: %d points "
        "(requested past_hours=%d).",
        saved,
        past_hours,
    )

    return saved


# ---------------------------------------------------------------------------
# Forecast refresh
# ---------------------------------------------------------------------------

def refresh_forecast():
    """Fetch fresh 24-hour forecast and UPSERT into DB."""
    fetched_at = datetime.now(timezone.utc)

    app.logger.info(
        "Requesting 24-hour forecast from Provider Service."
    )

    forecast_data = fetch_forecast_from_provider()
    points = normalize_forecast_points(forecast_data)
    provider = forecast_data.get("source", "open-meteo")

    with get_connection() as connection:
        saved = save_forecast_points(
            connection,
            points,
            provider,
            fetched_at,
        )

        update_forecast_sync_state(connection, fetched_at)

    app.logger.info(
        "Forecast saved: %d points.",
        saved,
    )

    return saved


# ---------------------------------------------------------------------------
# Hourly sync job (forecast + history backfill)
# ---------------------------------------------------------------------------

def run_hourly_sync():
    """Single scheduler job: refresh forecast + backfill history."""
    if not sync_lock.acquire(blocking=False):
        app.logger.warning(
            "Hourly sync already in progress — skipping."
        )
        return

    try:
        # 1. Forecast
        try:
            refresh_forecast()

        except ProviderServiceError as error:
            app.logger.error(
                "Forecast refresh failed: %s",
                error,
            )

        except (psycopg.Error, RuntimeError) as error:
            app.logger.error(
                "Could not save forecast to database: %s",
                error,
            )

        # 2. Historical backfill
        try:
            backfill_missing_hours()

        except ProviderServiceError as error:
            app.logger.error(
                "History backfill failed: %s",
                error,
            )

        except (psycopg.Error, RuntimeError) as error:
            app.logger.error(
                "Could not save history to database: %s",
                error,
            )

    finally:
        sync_lock.release()


# ---------------------------------------------------------------------------
# Scheduler
# ---------------------------------------------------------------------------

def start_scheduler():
    if scheduler.running:
        return

    scheduler.add_job(
        func=run_hourly_sync,
        trigger="interval",
        minutes=SYNC_INTERVAL_MINUTES,
        id="nadvirna-hourly-sync",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
        next_run_time=datetime.now(timezone.utc),
    )

    scheduler.start()

    app.logger.info(
        "Weather scheduler started. "
        "Sync interval: %d minutes.",
        SYNC_INTERVAL_MINUTES,
    )


# ---------------------------------------------------------------------------
# Flask routes
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1;")

        return jsonify({
            "service": "backend-service",
            "status": "ok",
            "database": "ok",
            "provider": "configured",
            "city": CITY_NAME,
            "sync_interval_minutes": SYNC_INTERVAL_MINUTES,
            "scheduler_running": scheduler.running,
        })

    except (
        psycopg.Error,
        RuntimeError,
    ):
        return jsonify({
            "service": "backend-service",
            "status": "error",
            "database": "unavailable",
        }), 503


@app.get("/api/weather")
def weather():
    """Return the latest current-conditions snapshot."""
    # 1. Try to fetch live current weather from provider-service
    try:
        current_data = fetch_weather_from_provider()

        # Extract values
        current = current_data.get("current", {})
        current_units = current_data.get("current_units", {})
        raw_time = current.get("time")

        if raw_time:
            current_time = parse_datetime(raw_time)
            if current_time:
                fetched_at = datetime.now(timezone.utc)
                weather_hour = floor_to_hour(current_time)

                # Persist live current snapshot to DB so we have historical context
                try:
                    with get_connection() as connection:
                        with connection.cursor() as cursor:
                            cursor.execute(
                                """
                                INSERT INTO weather_hourly_points (
                                    location_key,
                                    weather_at,
                                    temperature,
                                    relative_humidity,
                                    wind_speed,
                                    temperature_unit,
                                    humidity_unit,
                                    wind_speed_unit,
                                    provider,
                                    data_kind,
                                    source_generated_at,
                                    fetched_at
                                )
                                VALUES (
                                    %s, %s, %s, %s, %s,
                                    %s, %s, %s, %s, %s,
                                    %s, %s
                                )
                                ON CONFLICT (location_key, weather_at)
                                DO UPDATE SET
                                    temperature = EXCLUDED.temperature,
                                    relative_humidity = COALESCE(
                                        EXCLUDED.relative_humidity,
                                        weather_hourly_points.relative_humidity
                                    ),
                                    wind_speed = COALESCE(
                                        EXCLUDED.wind_speed,
                                        weather_hourly_points.wind_speed
                                    ),
                                    data_kind = EXCLUDED.data_kind,
                                    fetched_at = EXCLUDED.fetched_at;
                                """,
                                (
                                    LOCATION_KEY,
                                    weather_hour,
                                    current.get("temperature_2m"),
                                    current.get("relative_humidity_2m"),
                                    current.get("wind_speed_10m"),
                                    current_units.get("temperature_2m", TEMPERATURE_UNIT),
                                    current_units.get("relative_humidity_2m", HUMIDITY_UNIT),
                                    current_units.get("wind_speed_10m", WIND_SPEED_UNIT),
                                    current_data.get("source", "open-meteo"),
                                    "current",
                                    fetched_at,
                                    fetched_at,
                                ),
                            )
                except Exception as db_err:
                    app.logger.warning("Could not persist live weather to DB: %s", db_err)

        return jsonify(current_data)

    except ProviderServiceError as error:
        app.logger.warning("Provider unavailable for live weather, falling back to DB: %s", error)

    # 2. Fallback to database for a row that HAS humidity and wind speed
    try:
        now_utc = datetime.now(timezone.utc)
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT
                        weather_at,
                        temperature,
                        relative_humidity,
                        wind_speed,
                        temperature_unit,
                        humidity_unit,
                        wind_speed_unit,
                        fetched_at
                    FROM weather_hourly_points
                    WHERE location_key = %s
                      AND relative_humidity IS NOT NULL
                      AND wind_speed IS NOT NULL
                      AND weather_at <= %s
                    ORDER BY weather_at DESC
                    LIMIT 1;
                    """,
                    (LOCATION_KEY, now_utc),
                )

                row = cursor.fetchone()

        if row is None:
            return jsonify({
                "error": "Дані про погоду ще не зібрані."
            }), 404

        weather_at = (
            row["weather_at"]
            .astimezone(timezone.utc)
            .isoformat()
        )

        fetched_at = (
            row["fetched_at"]
            .astimezone(timezone.utc)
            .isoformat()
        )

        return jsonify({
            "location": {
                "name": CITY_NAME,
                "country": COUNTRY_NAME,
                "latitude": LATITUDE,
                "longitude": LONGITUDE,
            },
            "current": {
                "time": weather_at,
                "temperature_2m": row["temperature"],
                "relative_humidity_2m": row.get(
                    "relative_humidity"
                ),
                "wind_speed_10m": row.get("wind_speed"),
            },
            "current_units": {
                "temperature_2m": row.get(
                    "temperature_unit",
                    TEMPERATURE_UNIT,
                ),
                "relative_humidity_2m": row.get(
                    "humidity_unit",
                    HUMIDITY_UNIT,
                ),
                "wind_speed_10m": row.get(
                    "wind_speed_unit",
                    WIND_SPEED_UNIT,
                ),
            },
            "source": "open-meteo",
            "collected_at": weather_at,
            "requested_at": fetched_at,
        })

    except (
        psycopg.Error,
        RuntimeError,
    ):
        return jsonify({
            "error": "База даних недоступна."
        }), 503


@app.get("/api/forecast")
def forecast():
    """Return 24 hourly forecast points (current hour + next 23)."""
    try:
        forecast_data = get_forecast_from_database()

        if forecast_data is None:
            return jsonify({
                "error": (
                    "Прогноз ще готується. "
                    "Спробуйте трохи пізніше."
                )
            }), 404

        return jsonify(forecast_data)

    except (
        psycopg.Error,
        RuntimeError,
    ) as error:
        app.logger.error(
            "Could not read stored forecast: %s",
            error,
        )

        return jsonify({
            "error": (
                "Не вдалося прочитати прогноз "
                "із бази даних."
            )
        }), 503


@app.get("/api/history")
def history():
    """Return hourly historical weather data.

    Query param:
        hours — 24 or 168 (default 24)
    """
    raw_hours = request.args.get("hours", "24")

    try:
        hours = int(raw_hours)
    except (TypeError, ValueError):
        return jsonify({
            "error": (
                "Параметр hours повинен бути цілим числом."
            )
        }), 400

    if hours not in ALLOWED_HISTORY_HOURS:
        return jsonify({
            "error": (
                "Параметр hours повинен бути 24 або 168."
            )
        }), 400

    try:
        points = get_history_from_database(hours)
        print(points)
        return jsonify({
            "hours": hours,
            "count": len(points),
            "location": {
                "name": CITY_NAME,
                "country": COUNTRY_NAME,
                "latitude": LATITUDE,
                "longitude": LONGITUDE,
                "timezone": WEATHER_TIMEZONE,
            },
            "hourly": {
                "time": [p["time"] for p in points],
                "temperature_2m": [
                    p["temperature"] for p in points
                ],
                "relative_humidity_2m": [
                    p.get("humidity") for p in points
                ],
                "wind_speed_10m": [
                    p.get("wind_speed") for p in points
                ],
            },
            "hourly_units": {
                "time": "unixtime",
                "temperature_2m": TEMPERATURE_UNIT,
                "relative_humidity_2m": HUMIDITY_UNIT,
                "wind_speed_10m": WIND_SPEED_UNIT,
            },
        })

    except (
        psycopg.Error,
        RuntimeError,
    ) as error:
        app.logger.error(
            "Could not load history: %s",
            error,
        )

        return jsonify({
            "error": "Не вдалося завантажити історію."
        }), 503


# ---------------------------------------------------------------------------
# Startup / shutdown
# ---------------------------------------------------------------------------

atexit.register(
    lambda: (
        scheduler.shutdown(wait=False)
        if scheduler.running
        else None
    )
)


if __name__ == "__main__":
    create_tables()
    start_scheduler()

    app.run(
        host=os.getenv(
            "APP_HOST",
            "127.0.0.1",
        ),
        port=int(
            os.getenv(
                "APP_PORT",
                "5001",
            )
        ),
        debug=is_debug_enabled(),
        use_reloader=False,
    )
