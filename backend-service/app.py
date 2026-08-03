import json
import os
import threading
import time
from datetime import datetime, timedelta, timezone

import pika
import psycopg
from flask import Flask, jsonify, request
from psycopg.rows import dict_row

import atexit
import logging
import sys

app = Flask(__name__)

def setup_logging():
    log_formatter = logging.Formatter(
        "[%(asctime)s] [%(levelname)s] [backend-service] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S %z",
    )

    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)
    root_logger.handlers.clear()

    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setFormatter(log_formatter)
    root_logger.addHandler(stream_handler)

    app.logger.setLevel(logging.INFO)
    app.logger.info("backend-service starting up")

    def _shutdown():
        for h in list(logging.getLogger().handlers):
            if getattr(getattr(h, "stream", None), "closed", False):
                return
        try:
            app.logger.info("backend-service shutting down")
        except Exception:
            pass

    atexit.register(_shutdown)

setup_logging()

@app.errorhandler(Exception)
def handle_unexpected_exception(error):
    app.logger.error("Unexpected exception in backend-service: %s", error, exc_info=True)
    return jsonify({"error": "Internal server error"}), 500

DATABASE_URL = os.getenv("DATABASE_URL")

RABBITMQ_URL = os.getenv(
    "RABBITMQ_URL",
    "amqp://weather_user:weather_password@127.0.0.1:5672/",
)

QUEUE_NAME = "weather_data_queue"
REQUEST_TIMEOUT = 10

FORECAST_HOURS = 24
HISTORY_HOURS = 168

ALLOWED_HISTORY_HOURS = {24, 168}

CITY_NAME = "Nadvirna"
COUNTRY_NAME = "Ukraine"
LATITUDE = 48.6348
LONGITUDE = 24.5694
WEATHER_TIMEZONE = "Europe/Kyiv"
LOCATION_KEY = "nadvirna"

TEMPERATURE_UNIT = "°C"
HUMIDITY_UNIT = "%"
WIND_SPEED_UNIT = "km/h"


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


class InvalidMessageError(Exception):
    """Raised when RabbitMQ message format or content is invalid and should not be requeued."""
    pass


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

    max_retries = 30
    for attempt in range(max_retries):
        try:
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
            return
        except Exception as error:
            if attempt == max_retries - 1:
                app.logger.error("Failed to connect to database after %d attempts: %s", max_retries, error)
                raise
            app.logger.warning("Waiting for database connection (%d/%d): %s", attempt + 1, max_retries, error)
            time.sleep(2)




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
# RabbitMQ Consumer
# ---------------------------------------------------------------------------

def process_rabbitmq_message(ch, method, properties, body):
    delivery_tag = method.delivery_tag

    try:
        try:
            payload = json.loads(body.decode("utf-8"))
        except Exception as err:
            raise InvalidMessageError(f"Invalid JSON payload: {err}") from err

        if not isinstance(payload, dict):
            raise InvalidMessageError("Payload is not a JSON object")

        msg_type = payload.get("type")
        data = payload.get("data")
        if not msg_type or not isinstance(data, dict):
            raise InvalidMessageError("Missing or invalid 'type' / 'data' field in message")

        fetched_at = datetime.now(timezone.utc)

        if msg_type == "current":
            current = data.get("current")
            if not isinstance(current, dict):
                raise InvalidMessageError("Invalid 'current' payload structure")

            current_units = data.get("current_units", {})
            raw_time = current.get("time")
            if not raw_time:
                raise InvalidMessageError("Missing timestamp in current weather message")

            current_time = parse_datetime(raw_time)
            if not current_time:
                raise InvalidMessageError("Invalid timestamp in current weather message")

            weather_hour = floor_to_hour(current_time)
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
                            data.get("source", "open-meteo"),
                            "current",
                            fetched_at,
                            fetched_at,
                        ),
                    )
            app.logger.info("Persisted RabbitMQ current weather message")

        elif msg_type == "forecast":
            try:
                points = normalize_forecast_points(data)
            except Exception as err:
                raise InvalidMessageError(f"Forecast normalization failed: {err}") from err

            provider = data.get("source", "open-meteo")
            with get_connection() as connection:
                saved = save_forecast_points(connection, points, provider, fetched_at)
                update_forecast_sync_state(connection, fetched_at)
            app.logger.info("Persisted RabbitMQ forecast (%d points)", saved)

        elif msg_type == "history":
            try:
                points = normalize_history_points(data)
            except Exception as err:
                raise InvalidMessageError(f"History normalization failed: {err}") from err

            provider = data.get("source", "open-meteo")
            with get_connection() as connection:
                saved = save_history_points(connection, points, provider, fetched_at)
                update_history_sync_state(connection, fetched_at)
            app.logger.info("Persisted RabbitMQ history (%d points)", saved)

        else:
            raise InvalidMessageError(f"Unknown message type: {msg_type}")

        ch.basic_ack(delivery_tag=delivery_tag)

    except InvalidMessageError as err:
        app.logger.error("Invalid RabbitMQ message format: %s. Rejecting (requeue=False).", err)
        ch.basic_nack(delivery_tag=delivery_tag, requeue=False)

    except Exception as err:
        app.logger.error("Error processing RabbitMQ message: %s. Requeuing (requeue=True).", err)
        ch.basic_nack(delivery_tag=delivery_tag, requeue=True)


def start_rabbitmq_consumer():
    def consumer_loop():
        while True:
            try:
                app.logger.info("Connecting to RabbitMQ at %s...", RABBITMQ_URL)
                params = pika.URLParameters(RABBITMQ_URL)
                connection = pika.BlockingConnection(params)
                channel = connection.channel()
                channel.queue_declare(queue=QUEUE_NAME, durable=True)
                channel.basic_qos(prefetch_count=1)
                channel.basic_consume(
                    queue=QUEUE_NAME,
                    on_message_callback=process_rabbitmq_message,
                )
                app.logger.info("RabbitMQ consumer listening on queue %s", QUEUE_NAME)
                channel.start_consuming()
            except Exception as err:
                app.logger.warning("RabbitMQ consumer connection error: %s. Retrying in 5s...", err)
                time.sleep(5)

    thread = threading.Thread(target=consumer_loop, daemon=True)
    thread.start()


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
    """Return the latest current-conditions snapshot from database."""
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

if __name__ == "__main__":
    create_tables()
    start_rabbitmq_consumer()

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
    