import json
import os
import threading
import time
from datetime import datetime, timezone

import pika
import requests
from flask import Flask, jsonify, request

import atexit
import logging
from logging.handlers import RotatingFileHandler
import sys

app = Flask(__name__)

def setup_logging():
    log_formatter = logging.Formatter(
        "[%(asctime)s] [%(levelname)s] [provider-service] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S %z",
    )

    root_logger = logging.getLogger()
    root_logger.setLevel(logging.INFO)

    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setFormatter(log_formatter)
    root_logger.addHandler(stream_handler)

    log_dir = "/var/log/weather-app"
    log_path = os.path.join(log_dir, "provider-service.log")

    try:
        os.makedirs(log_dir, mode=0o755, exist_ok=True)
        file_handler = RotatingFileHandler(
            log_path,
            maxBytes=10 * 1024 * 1024,
            backupCount=5,
            encoding="utf-8",
        )
        file_handler.setFormatter(log_formatter)
        root_logger.addHandler(file_handler)
        if os.path.exists(log_path):
            try:
                os.chmod(log_path, 0o644)
            except OSError:
                pass
    except Exception as err:
        sys.stderr.write(f"Warning: Could not configure file logging at {log_path}: {err}\n")

    app.logger.setLevel(logging.INFO)
    app.logger.info("provider-service starting up")

    def _shutdown():
        for h in list(logging.getLogger().handlers):
            if getattr(getattr(h, "stream", None), "closed", False):
                return
        try:
            app.logger.info("provider-service shutting down")
        except Exception:
            pass

    atexit.register(_shutdown)

setup_logging()

@app.errorhandler(Exception)
def handle_unexpected_exception(error):
    app.logger.error("Unexpected exception in provider-service: %s", error, exc_info=True)
    return jsonify({"error": "Internal server error"}), 500

EXTERNAL_WEATHER_URL = os.getenv(
    "EXTERNAL_WEATHER_URL",
    "https://api.open-meteo.com/v1/forecast",
)

RABBITMQ_URL = os.getenv(
    "RABBITMQ_URL",
    "amqp://weather_user:weather_password@127.0.0.1:5672/",
)

REQUEST_TIMEOUT = 10
DEFAULT_TIMEZONE = "Europe/Kyiv"
FORECAST_HOURS = 24
MAX_HISTORY_HOURS = 168
DEFAULT_LATITUDE = 48.6348
DEFAULT_LONGITUDE = 24.5694
QUEUE_NAME = "weather_data_queue"


def is_debug_enabled():
    return os.getenv("FLASK_DEBUG", "false").lower() in {
        "1",
        "true",
        "yes",
    }


def publish_to_rabbitmq(msg_type, payload):
    """Publish a weather data message to RabbitMQ queue."""
    try:
        parameters = pika.URLParameters(RABBITMQ_URL)
        connection = pika.BlockingConnection(parameters)
        channel = connection.channel()
        channel.queue_declare(queue=QUEUE_NAME, durable=True)

        message = {
            "type": msg_type,
            "data": payload,
            "published_at": datetime.now(timezone.utc).isoformat(),
        }

        channel.basic_publish(
            exchange="",
            routing_key=QUEUE_NAME,
            body=json.dumps(message),
            properties=pika.BasicProperties(
                delivery_mode=2,  # make message persistent
            ),
        )
        connection.close()
        app.logger.info("Published %s message to RabbitMQ queue %s", msg_type, QUEUE_NAME)
    except Exception as error:
        app.logger.warning("Could not publish %s to RabbitMQ: %s", msg_type, error)


def _fetch_and_publish_all():
    """Fetch current, forecast, and history from Open-Meteo and publish to RabbitMQ."""
    # Current weather
    try:
        resp = requests.get(
            EXTERNAL_WEATHER_URL,
            params={
                "latitude": DEFAULT_LATITUDE,
                "longitude": DEFAULT_LONGITUDE,
                "current": "temperature_2m,relative_humidity_2m,wind_speed_10m",
                "timezone": DEFAULT_TIMEZONE,
            },
            timeout=REQUEST_TIMEOUT,
        )
        if resp.ok:
            data = normalize_weather(resp.json(), DEFAULT_LATITUDE, DEFAULT_LONGITUDE, DEFAULT_TIMEZONE)
            publish_to_rabbitmq("current", data)
    except Exception as err:
        app.logger.warning("Auto-fetch current weather error: %s", err)

    # Forecast
    try:
        resp = requests.get(
            EXTERNAL_WEATHER_URL,
            params={
                "latitude": DEFAULT_LATITUDE,
                "longitude": DEFAULT_LONGITUDE,
                "hourly": "temperature_2m",
                "forecast_hours": FORECAST_HOURS,
                "timeformat": "unixtime",
                "timezone": DEFAULT_TIMEZONE,
            },
            timeout=REQUEST_TIMEOUT,
        )
        if resp.ok:
            data = normalize_forecast(resp.json(), DEFAULT_LATITUDE, DEFAULT_LONGITUDE, DEFAULT_TIMEZONE)
            publish_to_rabbitmq("forecast", data)
    except Exception as err:
        app.logger.warning("Auto-fetch forecast error: %s", err)

    # History
    try:
        resp = requests.get(
            EXTERNAL_WEATHER_URL,
            params={
                "latitude": DEFAULT_LATITUDE,
                "longitude": DEFAULT_LONGITUDE,
                "hourly": "temperature_2m,relative_humidity_2m,wind_speed_10m",
                "past_hours": MAX_HISTORY_HOURS,
                "forecast_days": 0,
                "timeformat": "unixtime",
                "timezone": DEFAULT_TIMEZONE,
            },
            timeout=REQUEST_TIMEOUT,
        )
        if resp.ok:
            data = normalize_history(resp.json(), DEFAULT_LATITUDE, DEFAULT_LONGITUDE, DEFAULT_TIMEZONE, MAX_HISTORY_HOURS)
            publish_to_rabbitmq("history", data)
    except Exception as err:
        app.logger.warning("Auto-fetch history error: %s", err)


def start_periodic_publisher():
    def loop():
        # Wait initial 5s for RabbitMQ broker to start up
        time.sleep(5)
        while True:
            try:
                _fetch_and_publish_all()
            except Exception as e:
                app.logger.error("Error in periodic publisher loop: %s", e)
            time.sleep(60)  # Publish updates every 60s

    thread = threading.Thread(target=loop, daemon=True)
    thread.start()



def get_coordinate(name, minimum, maximum):
    raw_value = request.args.get(name)

    try:
        value = float(raw_value)

    except (TypeError, ValueError) as error:
        raise ValueError(
            f"{name} must be a number."
        ) from error

    if not minimum <= value <= maximum:
        raise ValueError(
            f"{name} must be between "
            f"{minimum} and {maximum}."
        )

    return value


def normalize_weather(
    weather_data,
    latitude,
    longitude,
    weather_timezone,
):
    current = weather_data.get("current")
    current_units = weather_data.get(
        "current_units"
    )

    if not isinstance(current, dict):
        raise ValueError(
            "External API returned no current weather."
        )

    required_fields = {
        "temperature_2m",
        "relative_humidity_2m",
        "wind_speed_10m",
    }

    if not required_fields.issubset(current):
        raise ValueError(
            "External API returned incomplete weather data."
        )

    if not isinstance(current_units, dict):
        current_units = {}

    return {
        "location": {
            "latitude": weather_data.get(
                "latitude",
                latitude,
            ),
            "longitude": weather_data.get(
                "longitude",
                longitude,
            ),
            "timezone": weather_data.get(
                "timezone",
                weather_timezone,
            ),
        },
        "current": {
            "time": current.get("time"),
            "interval": current.get("interval"),
            "temperature_2m": current.get(
                "temperature_2m"
            ),
            "relative_humidity_2m": current.get(
                "relative_humidity_2m"
            ),
            "wind_speed_10m": current.get(
                "wind_speed_10m"
            ),
        },
        "current_units": {
            "time": current_units.get("time"),
            "interval": current_units.get("interval"),
            "temperature_2m": current_units.get(
                "temperature_2m"
            ),
            "relative_humidity_2m": current_units.get(
                "relative_humidity_2m"
            ),
            "wind_speed_10m": current_units.get(
                "wind_speed_10m"
            ),
        },
        "source": "open-meteo",
        "collected_at": datetime.now(
            timezone.utc
        ).isoformat(),
    }


def normalize_forecast(
    weather_data,
    latitude,
    longitude,
    weather_timezone,
):
    hourly = weather_data.get("hourly")
    hourly_units = weather_data.get(
        "hourly_units"
    )

    if not isinstance(hourly, dict):
        raise ValueError(
            "External API returned no hourly forecast."
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
        raise ValueError(
            "External API returned incomplete "
            "hourly forecast data."
        )

    if not all(
        isinstance(value, (int, float))
        for value in times
    ):
        raise ValueError(
            "External API returned invalid "
            "forecast timestamps."
        )

    if not all(
        value is None or
        isinstance(value, (int, float))
        for value in temperatures
    ):
        raise ValueError(
            "External API returned invalid "
            "forecast temperatures."
        )

    if not isinstance(hourly_units, dict):
        hourly_units = {}

    return {
        "location": {
            "latitude": weather_data.get(
                "latitude",
                latitude,
            ),
            "longitude": weather_data.get(
                "longitude",
                longitude,
            ),
            "timezone": weather_data.get(
                "timezone",
                weather_timezone,
            ),
            "utc_offset_seconds": weather_data.get(
                "utc_offset_seconds",
            ),
        },
        "hourly": {
            "time": times,
            "temperature_2m": temperatures,
        },
        "hourly_units": {
            "time": hourly_units.get("time"),
            "temperature_2m": hourly_units.get(
                "temperature_2m"
            ),
        },
        "forecast_hours": FORECAST_HOURS,
        "source": "open-meteo",
        "generated_at": datetime.now(
            timezone.utc
        ).isoformat(),
    }


def normalize_history(
    weather_data,
    latitude,
    longitude,
    weather_timezone,
    past_hours,
):
    hourly = weather_data.get("hourly")
    hourly_units = weather_data.get(
        "hourly_units"
    )

    if not isinstance(hourly, dict):
        raise ValueError(
            "External API returned no hourly history."
        )

    times = hourly.get("time")
    temperatures = hourly.get("temperature_2m")
    humidities = hourly.get("relative_humidity_2m")
    wind_speeds = hourly.get("wind_speed_10m")

    if (
        not isinstance(times, list) or
        not isinstance(temperatures, list) or
        len(times) != len(temperatures)
    ):
        raise ValueError(
            "External API returned incomplete "
            "hourly history data."
        )

    if not all(
        isinstance(value, (int, float))
        for value in times
    ):
        raise ValueError(
            "External API returned invalid "
            "history timestamps."
        )

    if not isinstance(hourly_units, dict):
        hourly_units = {}

    return {
        "location": {
            "latitude": weather_data.get(
                "latitude",
                latitude,
            ),
            "longitude": weather_data.get(
                "longitude",
                longitude,
            ),
            "timezone": weather_data.get(
                "timezone",
                weather_timezone,
            ),
            "utc_offset_seconds": weather_data.get(
                "utc_offset_seconds",
            ),
        },
        "hourly": {
            "time": times,
            "temperature_2m": temperatures,
            "relative_humidity_2m": (
                humidities
                if isinstance(humidities, list)
                else [None] * len(times)
            ),
            "wind_speed_10m": (
                wind_speeds
                if isinstance(wind_speeds, list)
                else [None] * len(times)
            ),
        },
        "hourly_units": {
            "time": hourly_units.get("time"),
            "temperature_2m": hourly_units.get(
                "temperature_2m"
            ),
            "relative_humidity_2m": hourly_units.get(
                "relative_humidity_2m"
            ),
            "wind_speed_10m": hourly_units.get(
                "wind_speed_10m"
            ),
        },
        "past_hours": past_hours,
        "source": "open-meteo",
        "generated_at": datetime.now(
            timezone.utc
        ).isoformat(),
    }


@app.get("/health")
def health():
    return jsonify({
        "service": "provider-service",
        "status": "ok",
        "external_api": "configured",
    })


@app.get("/weather/current")
def current_weather():
    try:
        latitude = get_coordinate(
            "latitude",
            -90,
            90,
        )

        longitude = get_coordinate(
            "longitude",
            -180,
            180,
        )

        weather_timezone = request.args.get(
            "timezone",
            DEFAULT_TIMEZONE,
        ).strip()

        if not weather_timezone:
            raise ValueError(
                "timezone cannot be empty."
            )

    except ValueError as error:
        return jsonify({
            "error": str(error)
        }), 400

    try:
        response = requests.get(
            EXTERNAL_WEATHER_URL,
            params={
                "latitude": latitude,
                "longitude": longitude,
                "current": (
                    "temperature_2m,"
                    "relative_humidity_2m,"
                    "wind_speed_10m"
                ),
                "timezone": weather_timezone,
            },
            timeout=REQUEST_TIMEOUT,
        )

        response.raise_for_status()
        weather_data = response.json()

    except requests.Timeout:
        app.logger.error(
            "External weather API timed out."
        )

        return jsonify({
            "error": (
                "Зовнішній погодний API "
                "не відповідає вчасно."
            )
        }), 504

    except requests.RequestException as error:
        app.logger.error(
            "External weather API request failed: %s",
            error,
        )

        return jsonify({
            "error": (
                "Не вдалося отримати дані із "
                "зовнішнього погодного API."
            )
        }), 502

    except ValueError:
        return jsonify({
            "error": (
                "Зовнішній погодний API повернув "
                "некоректну JSON-відповідь."
            )
        }), 502

    try:
        normalized_weather = normalize_weather(
            weather_data,
            latitude,
            longitude,
            weather_timezone,
        )

    except (TypeError, ValueError) as error:
        app.logger.error(
            "Invalid external weather response: %s",
            error,
        )

        return jsonify({
            "error": (
                "Зовнішній погодний API повернув "
                "неповні погодні дані."
            )
        }), 502

    return jsonify(normalized_weather)


@app.get("/weather/forecast")
def hourly_forecast():
    try:
        latitude = get_coordinate(
            "latitude",
            -90,
            90,
        )

        longitude = get_coordinate(
            "longitude",
            -180,
            180,
        )

        weather_timezone = request.args.get(
            "timezone",
            DEFAULT_TIMEZONE,
        ).strip()

        if not weather_timezone:
            raise ValueError(
                "timezone cannot be empty."
            )

    except ValueError as error:
        return jsonify({
            "error": str(error)
        }), 400

    try:
        response = requests.get(
            EXTERNAL_WEATHER_URL,
            params={
                "latitude": latitude,
                "longitude": longitude,
                "hourly": "temperature_2m",
                "forecast_hours": FORECAST_HOURS,
                "timeformat": "unixtime",
                "timezone": weather_timezone,
            },
            timeout=REQUEST_TIMEOUT,
        )

        response.raise_for_status()
        weather_data = response.json()

    except requests.Timeout:
        app.logger.error(
            "External weather forecast API timed out."
        )

        return jsonify({
            "error": (
                "Зовнішній погодний API "
                "не відповідає вчасно."
            )
        }), 504

    except requests.RequestException:
        app.logger.error(
            "External weather forecast request failed."
        )

        return jsonify({
            "error": (
                "Не вдалося отримати прогноз із "
                "зовнішнього погодного API."
            )
        }), 502

    except ValueError:
        return jsonify({
            "error": (
                "Зовнішній погодний API повернув "
                "некоректну JSON-відповідь."
            )
        }), 502

    try:
        normalized_forecast = normalize_forecast(
            weather_data,
            latitude,
            longitude,
            weather_timezone,
        )

    except (TypeError, ValueError) as error:
        app.logger.error(
            "Invalid external forecast response: %s",
            error,
        )

        return jsonify({
            "error": (
                "Зовнішній погодний API повернув "
                "неповні дані прогнозу."
            )
        }), 502

    return jsonify(normalized_forecast)


@app.get("/weather/history")
def hourly_history():
    """Return past_hours of hourly historical weather data."""
    try:
        latitude = get_coordinate(
            "latitude",
            -90,
            90,
        )

        longitude = get_coordinate(
            "longitude",
            -180,
            180,
        )

        weather_timezone = request.args.get(
            "timezone",
            DEFAULT_TIMEZONE,
        ).strip()

        if not weather_timezone:
            raise ValueError(
                "timezone cannot be empty."
            )

        raw_past_hours = request.args.get(
            "past_hours",
            str(MAX_HISTORY_HOURS),
        )

        try:
            past_hours = int(raw_past_hours)
        except (TypeError, ValueError) as error:
            raise ValueError(
                "past_hours must be an integer."
            ) from error

        if not 1 <= past_hours <= MAX_HISTORY_HOURS:
            raise ValueError(
                f"past_hours must be between 1 "
                f"and {MAX_HISTORY_HOURS}."
            )

    except ValueError as error:
        return jsonify({
            "error": str(error)
        }), 400

    try:
        response = requests.get(
            EXTERNAL_WEATHER_URL,
            params={
                "latitude": latitude,
                "longitude": longitude,
                "hourly": (
                    "temperature_2m,"
                    "relative_humidity_2m,"
                    "wind_speed_10m"
                ),
                "past_hours": past_hours,
                "forecast_days": 0,
                "timeformat": "unixtime",
                "timezone": weather_timezone,
            },
            timeout=REQUEST_TIMEOUT,
        )

        response.raise_for_status()
        weather_data = response.json()

    except requests.Timeout:
        app.logger.error(
            "External history API timed out."
        )

        return jsonify({
            "error": (
                "Зовнішній погодний API "
                "не відповідає вчасно."
            )
        }), 504

    except requests.RequestException as error:
        app.logger.error(
            "External history request failed: %s",
            error,
        )

        return jsonify({
            "error": (
                "Не вдалося отримати історію із "
                "зовнішнього погодного API."
            )
        }), 502

    except ValueError:
        return jsonify({
            "error": (
                "Зовнішній погодний API повернув "
                "некоректну JSON-відповідь."
            )
        }), 502

    try:
        normalized_history = normalize_history(
            weather_data,
            latitude,
            longitude,
            weather_timezone,
            past_hours,
        )

    except (TypeError, ValueError) as error:
        app.logger.error(
            "Invalid external history response: %s",
            error,
        )

        return jsonify({
            "error": (
                "Зовнішній погодний API повернув "
                "неповні історичні дані."
            )
        }), 502

    return jsonify(normalized_history)


if __name__ == "__main__":
    start_periodic_publisher()

    app.run(
        host=os.getenv(
            "APP_HOST",
            "127.0.0.1",
        ),
        port=int(
            os.getenv(
                "APP_PORT",
                "5002",
            )
        ),
        debug=is_debug_enabled(),
    )

