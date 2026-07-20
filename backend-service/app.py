import atexit
import os
import threading
from datetime import datetime, timedelta, timezone

import requests
from apscheduler.schedulers.background import BackgroundScheduler
from flask import Flask, jsonify

app = Flask(__name__)

WEATHER_URL = "https://api.open-meteo.com/v1/forecast"

HISTORY_URL = os.getenv(
    "HISTORY_URL",
    "http://127.0.0.1:5002",
).rstrip("/")

REQUEST_TIMEOUT = 10
COLLECTION_INTERVAL_MINUTES = 30
MINIMUM_INTERVAL_MINUTES = 25

CITY_NAME = "Надвірна"
COUNTRY_NAME = "Україна"
LATITUDE = 48.6348
LONGITUDE = 24.5694

scheduler = BackgroundScheduler(
    timezone="Europe/Kyiv"
)

collection_lock = threading.Lock()


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
        TypeError,
        ValueError,
    ):
        return None


def get_latest_history_item():
    response = requests.get(
        f"{HISTORY_URL}/history",
        timeout=REQUEST_TIMEOUT,
    )

    response.raise_for_status()

    history_data = response.json()
    items = history_data.get("items", [])

    if not items:
        return None

    return items[0]


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


def collect_weather_without_lock(
    force=False,
):
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
        "Collecting weather for %s.",
        CITY_NAME,
    )

    weather_response = requests.get(
        WEATHER_URL,
        params={
            "latitude": LATITUDE,
            "longitude": LONGITUDE,
            "current": (
                "temperature_2m,"
                "relative_humidity_2m,"
                "wind_speed_10m"
            ),
            "timezone": "Europe/Kyiv",
        },
        timeout=REQUEST_TIMEOUT,
    )

    weather_response.raise_for_status()

    weather_data = weather_response.json()
    current = weather_data.get("current")

    if not isinstance(current, dict):
        raise ValueError(
            "Weather API returned no current weather."
        )

    result = {
        "query": CITY_NAME,
        "location": {
            "name": CITY_NAME,
            "country": COUNTRY_NAME,
            "latitude": LATITUDE,
            "longitude": LONGITUDE,
        },
        "current": current,
        "current_units": weather_data.get(
            "current_units",
            {},
        ),
        "source": "open-meteo",
        "collected_at": datetime.now(
            timezone.utc
        ).isoformat(),
    }

    save_response = requests.post(
        f"{HISTORY_URL}/history",
        json={
            "query": CITY_NAME,
            "response_data": result,
            "source": "open-meteo",
            "status": "success",
        },
        timeout=REQUEST_TIMEOUT,
    )

    save_response.raise_for_status()

    app.logger.info(
        "Weather saved: %s°C.",
        current.get("temperature_2m"),
    )

    return {
        "saved": True,
        "weather": result,
    }


def collect_weather(force=False):
    with collection_lock:
        return collect_weather_without_lock(
            force=force
        )


def run_weather_collection():
    try:
        collect_weather(force=False)

    except (
        requests.RequestException,
        ValueError,
        KeyError,
    ) as error:
        app.logger.error(
            "Weather collection failed: %s",
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

    scheduler.start()

    app.logger.info(
        "Weather scheduler started. "
        "Collection interval: %s minutes.",
        COLLECTION_INTERVAL_MINUTES,
    )


@app.get("/health")
def health():
    return jsonify({
        "service": "backend",
        "status": "ok",
        "city": CITY_NAME,
        "collection_interval_minutes": (
            COLLECTION_INTERVAL_MINUTES
        ),
        "scheduler_running": scheduler.running,
    })


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

        result = latest_item.get(
            "response_data",
            {},
        )

        result["requested_at"] = (
            latest_item.get("requested_at")
        )

        return jsonify(result)

    except (
        requests.RequestException,
        ValueError,
    ):
        return jsonify({
            "error": "History Service недоступний."
        }), 503


@app.get("/api/history")
def history():
    try:
        response = requests.get(
            f"{HISTORY_URL}/history",
            timeout=REQUEST_TIMEOUT,
        )

        response.raise_for_status()

        return jsonify(response.json())

    except (
        requests.RequestException,
        ValueError,
    ):
        return jsonify({
            "error": "History Service недоступний."
        }), 503


@app.delete("/api/history")
def clear_history():
    try:
        with collection_lock:
            delete_response = requests.delete(
                f"{HISTORY_URL}/history",
                timeout=REQUEST_TIMEOUT,
            )

            delete_response.raise_for_status()

            delete_data = delete_response.json()

            collection_result = (
                collect_weather_without_lock(
                    force=True
                )
            )

        return jsonify({
            "message": (
                "Історію очищено. "
                "Нові погодні дані збережено."
            ),
            "deleted_count": delete_data.get(
                "deleted_count",
                0,
            ),
            "weather": collection_result.get(
                "weather"
            ),
        })

    except requests.RequestException as error:
        app.logger.error(
            "Could not clear history or "
            "collect weather: %s",
            error,
        )

        return jsonify({
            "error": (
                "Не вдалося очистити історію "
                "або отримати нову погоду."
            )
        }), 503

    except (
        ValueError,
        KeyError,
    ) as error:
        app.logger.error(
            "Invalid weather response: %s",
            error,
        )

        return jsonify({
            "error": (
                "Погодний сервіс повернув "
                "неправильні дані."
            )
        }), 502


atexit.register(
    lambda: (
        scheduler.shutdown(wait=False)
        if scheduler.running
        else None
    )
)


if __name__ == "__main__":
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