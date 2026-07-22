import os
from datetime import datetime, timezone

import requests
from flask import Flask, jsonify, request

app = Flask(__name__)

EXTERNAL_WEATHER_URL = os.getenv(
    "EXTERNAL_WEATHER_URL",
    "https://api.open-meteo.com/v1/forecast",
)

REQUEST_TIMEOUT = 10
DEFAULT_TIMEZONE = "Europe/Kyiv"


def is_debug_enabled():
    return os.getenv("FLASK_DEBUG", "false").lower() in {
        "1",
        "true",
        "yes",
    }


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


if __name__ == "__main__":
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
