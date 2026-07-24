import atexit
import os
import threading
import uuid
from datetime import datetime, timedelta, timezone

import psycopg
import requests
from apscheduler.schedulers.background import BackgroundScheduler
from flask import Flask, jsonify
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

app = Flask(__name__)

DATABASE_URL = os.getenv("DATABASE_URL")

PROVIDER_URL = os.getenv(
    "PROVIDER_URL",
    "http://127.0.0.1:5002",
).rstrip("/")

REQUEST_TIMEOUT = 10
COLLECTION_INTERVAL_MINUTES = 30
MINIMUM_INTERVAL_MINUTES = 25
FORECAST_HOURS = 24
FORECAST_REFRESH_INTERVAL_HOURS = 24
FORECAST_RETRY_INTERVAL_MINUTES = 15
FORECAST_ADVISORY_LOCK_ID = 726241118

CITY_NAME = "Надвірна"
COUNTRY_NAME = "Україна"
LATITUDE = 48.6348
LONGITUDE = 24.5694
WEATHER_TIMEZONE = "Europe/Kyiv"
FORECAST_LOCATION_KEY = "nadvirna"

scheduler = BackgroundScheduler(
    timezone=WEATHER_TIMEZONE
)

collection_lock = threading.Lock()


class ProviderServiceError(Exception):
    def __init__(
        self,
        message,
        status_code=502,
    ):
        super().__init__(message)
        self.message = message
        self.status_code = status_code


def is_debug_enabled():
    return os.getenv("FLASK_DEBUG", "false").lower() in {
        "1",
        "true",
        "yes",
    }


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
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS weather_requests (
                    id BIGSERIAL PRIMARY KEY,
                    requested_at TIMESTAMPTZ
                        NOT NULL DEFAULT NOW(),
                    query TEXT NOT NULL,
                    response_data JSONB NOT NULL,
                    source TEXT,
                    status TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS weather_forecast_state (
                    location_key TEXT PRIMARY KEY,
                    city TEXT NOT NULL,
                    country TEXT NOT NULL,
                    latitude DOUBLE PRECISION NOT NULL,
                    longitude DOUBLE PRECISION NOT NULL,
                    timezone TEXT NOT NULL,
                    provider TEXT NOT NULL,
                    forecast_issued_at TIMESTAMPTZ NOT NULL,
                    last_success_at TIMESTAMPTZ NOT NULL,
                    batch_id UUID NOT NULL
                );

                CREATE TABLE IF NOT EXISTS weather_forecast_points (
                    location_key TEXT NOT NULL,
                    forecast_at TIMESTAMPTZ NOT NULL,
                    temperature DOUBLE PRECISION NOT NULL,
                    temperature_unit TEXT NOT NULL,
                    provider TEXT NOT NULL,
                    forecast_issued_at TIMESTAMPTZ NOT NULL,
                    updated_at TIMESTAMPTZ NOT NULL,
                    batch_id UUID NOT NULL,
                    PRIMARY KEY (
                        location_key,
                        forecast_at
                    )
                );

                CREATE INDEX IF NOT EXISTS
                    weather_forecast_points_batch_idx
                ON weather_forecast_points (
                    location_key,
                    batch_id,
                    forecast_at
                );
                """
            )


def serialize_history_item(item):
    serialized_item = dict(item)
    requested_at = serialized_item.get(
        "requested_at"
    )

    if isinstance(requested_at, datetime):
        serialized_item["requested_at"] = (
            requested_at.isoformat()
        )

    return serialized_item


def get_latest_history_item():
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    id,
                    requested_at,
                    query,
                    response_data,
                    source,
                    status
                FROM weather_requests
                ORDER BY requested_at DESC
                LIMIT 1;
                """
            )

            item = cursor.fetchone()

    if item is None:
        return None

    return serialize_history_item(item)


def get_history_items():
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    id,
                    requested_at,
                    query,
                    response_data,
                    source,
                    status
                FROM weather_requests
                ORDER BY requested_at DESC
                LIMIT 50;
                """
            )

            items = cursor.fetchall()

    return [
        serialize_history_item(item)
        for item in items
    ]


def insert_weather(connection, weather_data):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO weather_requests (
                query,
                response_data,
                source,
                status
            )
            VALUES (%s, %s, %s, %s)
            RETURNING id, requested_at;
            """,
            (
                CITY_NAME,
                Jsonb(weather_data),
                weather_data.get("source"),
                "success",
            ),
        )

        return cursor.fetchone()


def save_weather(weather_data):
    with get_connection() as connection:
        saved_record = insert_weather(
            connection,
            weather_data,
        )

    return serialize_history_item(saved_record)


def has_recent_measurement():
    latest_item = get_latest_history_item()

    if latest_item is None:
        return False

    latest_time = parse_datetime(
        latest_item.get("requested_at")
    )

    if latest_time is None:
        response_data = latest_item.get(
            "response_data",
            {},
        )

        latest_time = parse_datetime(
            response_data.get("collected_at")
        )

    if latest_time is None:
        return False

    minimum_allowed_time = (
        datetime.now(timezone.utc)
        - timedelta(
            minutes=MINIMUM_INTERVAL_MINUTES
        )
    )

    return latest_time >= minimum_allowed_time


def fetch_weather_from_provider():
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

    try:
        provider_data = response.json()

    except ValueError as error:
        raise ProviderServiceError(
            "Provider Service повернув некоректну відповідь."
        ) from error

    if not isinstance(provider_data, dict):
        raise ProviderServiceError(
            "Provider Service повернув некоректну відповідь."
        )

    if not response.ok:
        error_message = provider_data.get("error")

        if not isinstance(error_message, str):
            error_message = (
                "Provider Service не зміг отримати погоду."
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

    try:
        provider_data = response.json()

    except ValueError as error:
        raise ProviderServiceError(
            "Provider Service повернув "
            "некоректну відповідь."
        ) from error

    if not isinstance(provider_data, dict):
        raise ProviderServiceError(
            "Provider Service повернув "
            "некоректну відповідь."
        )

    if not response.ok:
        error_message = provider_data.get("error")

        if not isinstance(error_message, str):
            error_message = (
                "Provider Service не зміг "
                "отримати прогноз."
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

    hourly = provider_data.get("hourly")
    hourly_units = provider_data.get(
        "hourly_units"
    )

    if not isinstance(hourly, dict):
        raise ProviderServiceError(
            "Provider Service повернув "
            "неповні дані прогнозу."
        )

    times = hourly.get("time")
    temperatures = hourly.get(
        "temperature_2m"
    )

    if (
        not isinstance(times, list) or
        not isinstance(temperatures, list) or
        len(times) != len(temperatures)
    ):
        raise ProviderServiceError(
            "Provider Service повернув "
            "неповні дані прогнозу."
        )

    if not isinstance(hourly_units, dict):
        hourly_units = {}

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
        "hourly_units": hourly_units,
        "source": provider_data.get(
            "source",
            "open-meteo",
        ),
        "generated_at": provider_data.get(
            "generated_at",
            datetime.now(timezone.utc).isoformat(),
        ),
    }


def normalize_forecast_points(forecast_data):
    hourly = forecast_data.get("hourly")

    if not isinstance(hourly, dict):
        raise ProviderServiceError(
            "Provider Service повернув "
            "неповні дані прогнозу."
        )

    times = hourly.get("time")
    temperatures = hourly.get(
        "temperature_2m"
    )

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

        points_by_time[forecast_at] = float(
            raw_temperature
        )

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


def acquire_forecast_refresh_lock(connection):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT pg_try_advisory_xact_lock(%s)
                AS acquired;
            """,
            (FORECAST_ADVISORY_LOCK_ID,),
        )

        result = cursor.fetchone()

    return bool(result and result["acquired"])


def get_forecast_last_success_at(connection):
    with connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT last_success_at
            FROM weather_forecast_state
            WHERE location_key = %s;
            """,
            (FORECAST_LOCATION_KEY,),
        )

        state = cursor.fetchone()

    if state is None:
        return None

    return state["last_success_at"].astimezone(
        timezone.utc
    )


def save_forecast(
    connection,
    forecast_data,
    points,
    refreshed_at,
):
    provider = forecast_data.get(
        "source",
        "open-meteo",
    )

    forecast_issued_at = parse_datetime(
        forecast_data.get("generated_at")
    ) or refreshed_at

    temperature_unit = (
        forecast_data
        .get("hourly_units", {})
        .get("temperature_2m")
        or "°C"
    )

    batch_id = uuid.uuid4()

    with connection.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO weather_forecast_state (
                location_key,
                city,
                country,
                latitude,
                longitude,
                timezone,
                provider,
                forecast_issued_at,
                last_success_at,
                batch_id
            )
            VALUES (
                %s, %s, %s, %s, %s,
                %s, %s, %s, %s, %s
            )
            ON CONFLICT (location_key)
            DO UPDATE SET
                city = EXCLUDED.city,
                country = EXCLUDED.country,
                latitude = EXCLUDED.latitude,
                longitude = EXCLUDED.longitude,
                timezone = EXCLUDED.timezone,
                provider = EXCLUDED.provider,
                forecast_issued_at =
                    EXCLUDED.forecast_issued_at,
                last_success_at =
                    EXCLUDED.last_success_at,
                batch_id = EXCLUDED.batch_id;
            """,
            (
                FORECAST_LOCATION_KEY,
                CITY_NAME,
                COUNTRY_NAME,
                LATITUDE,
                LONGITUDE,
                WEATHER_TIMEZONE,
                provider,
                forecast_issued_at,
                refreshed_at,
                batch_id,
            ),
        )

        cursor.executemany(
            """
            INSERT INTO weather_forecast_points (
                location_key,
                forecast_at,
                temperature,
                temperature_unit,
                provider,
                forecast_issued_at,
                updated_at,
                batch_id
            )
            VALUES (
                %s, %s, %s, %s,
                %s, %s, %s, %s
            )
            ON CONFLICT (
                location_key,
                forecast_at
            )
            DO UPDATE SET
                temperature = EXCLUDED.temperature,
                temperature_unit =
                    EXCLUDED.temperature_unit,
                provider = EXCLUDED.provider,
                forecast_issued_at =
                    EXCLUDED.forecast_issued_at,
                updated_at = EXCLUDED.updated_at,
                batch_id = EXCLUDED.batch_id;
            """,
            [
                (
                    FORECAST_LOCATION_KEY,
                    point["forecast_at"],
                    point["temperature"],
                    temperature_unit,
                    provider,
                    forecast_issued_at,
                    refreshed_at,
                    batch_id,
                )
                for point in points
            ],
        )

        cursor.execute(
            """
            DELETE FROM weather_forecast_points
            WHERE location_key = %s
              AND batch_id <> %s;
            """,
            (
                FORECAST_LOCATION_KEY,
                batch_id,
            ),
        )

    return {
        "batch_id": str(batch_id),
        "last_success_at": (
            refreshed_at.isoformat()
        ),
        "point_count": len(points),
    }


def get_forecast_from_database():
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    location_key,
                    city,
                    country,
                    latitude,
                    longitude,
                    timezone,
                    provider,
                    forecast_issued_at,
                    last_success_at,
                    batch_id
                FROM weather_forecast_state
                WHERE location_key = %s;
                """,
                (FORECAST_LOCATION_KEY,),
            )

            state = cursor.fetchone()

            if state is None:
                return None

            cursor.execute(
                """
                SELECT
                    forecast_at,
                    temperature,
                    temperature_unit
                FROM weather_forecast_points
                WHERE location_key = %s
                  AND batch_id = %s
                ORDER BY forecast_at ASC
                LIMIT %s;
                """,
                (
                    FORECAST_LOCATION_KEY,
                    state["batch_id"],
                    FORECAST_HOURS,
                ),
            )

            points = cursor.fetchall()

    if len(points) != FORECAST_HOURS:
        return None

    last_success_at = state[
        "last_success_at"
    ].astimezone(timezone.utc)

    return {
        "query": state["city"],
        "forecast_hours": FORECAST_HOURS,
        "location": {
            "name": state["city"],
            "country": state["country"],
            "latitude": state["latitude"],
            "longitude": state["longitude"],
            "timezone": state["timezone"],
        },
        "hourly": {
            "time": [
                int(
                    point["forecast_at"]
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
            ),
        },
        "source": state["provider"],
        "generated_at": (
            state["forecast_issued_at"]
            .astimezone(timezone.utc)
            .isoformat()
        ),
        "last_success_at": (
            last_success_at.isoformat()
        ),
        "stale": (
            datetime.now(timezone.utc) -
            last_success_at
        ) >= timedelta(
            hours=FORECAST_REFRESH_INTERVAL_HOURS
        ),
        "storage": "database",
    }


def refresh_forecast_if_due(now=None):
    refreshed_at = (
        now or datetime.now(timezone.utc)
    ).astimezone(timezone.utc)

    with get_connection() as connection:
        if not acquire_forecast_refresh_lock(
            connection
        ):
            return {
                "updated": False,
                "reason": "refresh_in_progress",
            }

        last_success_at = (
            get_forecast_last_success_at(
                connection
            )
        )

        refresh_after = (
            refreshed_at -
            timedelta(
                hours=(
                    FORECAST_REFRESH_INTERVAL_HOURS
                )
            )
        )

        if (
            last_success_at is not None and
            last_success_at > refresh_after
        ):
            return {
                "updated": False,
                "reason": "forecast_is_fresh",
                "last_success_at": (
                    last_success_at.isoformat()
                ),
            }

        app.logger.info(
            "Requesting 24-hour forecast from "
            "Provider Service."
        )

        forecast_data = (
            fetch_forecast_from_provider()
        )

        points = normalize_forecast_points(
            forecast_data
        )

        saved_forecast = save_forecast(
            connection,
            forecast_data,
            points,
            refreshed_at,
        )

    app.logger.info(
        "24-hour forecast saved: %s points.",
        saved_forecast["point_count"],
    )

    return {
        "updated": True,
        **saved_forecast,
    }


def run_forecast_refresh():
    try:
        refresh_forecast_if_due()

    except ProviderServiceError as error:
        app.logger.error(
            "Forecast refresh failed: %s",
            error,
        )

    except (
        psycopg.Error,
        RuntimeError,
    ) as error:
        app.logger.error(
            "Could not refresh stored forecast: %s",
            error,
        )


def collect_weather_without_lock(force=False):
    if not force and has_recent_measurement():
        app.logger.info(
            "Weather collection skipped: "
            "a recent measurement already exists."
        )

        return {
            "saved": False,
            "reason": "recent_measurement_exists",
        }

    app.logger.info(
        "Requesting current weather from Provider Service."
    )

    weather_data = fetch_weather_from_provider()
    saved_record = save_weather(weather_data)

    app.logger.info(
        "Weather saved: %s°C.",
        weather_data["current"].get(
            "temperature_2m"
        ),
    )

    return {
        "saved": True,
        "record": saved_record,
        "weather": weather_data,
    }


def collect_weather(force=False):
    with collection_lock:
        return collect_weather_without_lock(
            force=force
        )


def run_weather_collection():
    try:
        collect_weather(force=False)

    except ProviderServiceError as error:
        app.logger.error(
            "Weather collection failed: %s",
            error,
        )

    except (
        psycopg.Error,
        RuntimeError,
    ) as error:
        app.logger.error(
            "Could not store weather: %s",
            error,
        )


def start_scheduler():
    if scheduler.running:
        return

    scheduler.add_job(
        func=run_weather_collection,
        trigger="interval",
        minutes=COLLECTION_INTERVAL_MINUTES,
        id="nadvirna-weather-collector",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
        next_run_time=datetime.now(
            timezone.utc
        ),
    )

    scheduler.add_job(
        func=run_forecast_refresh,
        trigger="interval",
        minutes=FORECAST_RETRY_INTERVAL_MINUTES,
        id="nadvirna-forecast-refresher",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
        next_run_time=datetime.now(
            timezone.utc
        ),
    )

    scheduler.start()

    app.logger.info(
        "Weather scheduler started. "
        "Current conditions interval: %s minutes; "
        "forecast check interval: %s minutes.",
        COLLECTION_INTERVAL_MINUTES,
        FORECAST_RETRY_INTERVAL_MINUTES,
    )


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
            "collection_interval_minutes": (
                COLLECTION_INTERVAL_MINUTES
            ),
            "forecast_refresh_interval_hours": (
                FORECAST_REFRESH_INTERVAL_HOURS
            ),
            "forecast_check_interval_minutes": (
                FORECAST_RETRY_INTERVAL_MINUTES
            ),
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
    try:
        latest_item = get_latest_history_item()

        if latest_item is None:
            return jsonify({
                "error": (
                    "Дані про погоду ще не зібрані."
                )
            }), 404

        result = dict(
            latest_item.get(
                "response_data",
                {},
            )
        )

        result["requested_at"] = (
            latest_item.get("requested_at")
        )

        return jsonify(result)

    except (
        psycopg.Error,
        RuntimeError,
    ):
        return jsonify({
            "error": "База даних недоступна."
        }), 503


@app.get("/api/forecast")
def forecast():
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
    try:
        items = get_history_items()

        return jsonify({
            "count": len(items),
            "items": items,
        })

    except (
        psycopg.Error,
        RuntimeError,
    ):
        return jsonify({
            "error": "Не вдалося завантажити історію."
        }), 503


@app.delete("/api/history")
def clear_history():
    try:
        with collection_lock:
            weather_data = fetch_weather_from_provider()

            with get_connection() as connection:
                with connection.cursor() as cursor:
                    cursor.execute(
                        "DELETE FROM weather_requests;"
                    )

                    deleted_count = cursor.rowcount

                insert_weather(
                    connection,
                    weather_data,
                )

        return jsonify({
            "message": (
                "Історію очищено. "
                "Нові погодні дані збережено."
            ),
            "deleted_count": deleted_count,
            "weather": weather_data,
        })

    except ProviderServiceError as error:
        app.logger.error(
            "Could not refresh weather while clearing "
            "history: %s",
            error,
        )

        return jsonify({
            "error": (
                f"Історію не змінено. {error.message}"
            )
        }), error.status_code

    except (
        psycopg.Error,
        RuntimeError,
    ) as error:
        app.logger.error(
            "Could not replace weather history: %s",
            error,
        )

        return jsonify({
            "error": (
                "Не вдалося оновити історію в базі даних."
            )
        }), 503


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
