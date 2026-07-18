import os

import requests
from flask import Flask, jsonify, request

app = Flask(__name__)

GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search"
WEATHER_URL = "https://api.open-meteo.com/v1/forecast"

HISTORY_URL = os.getenv(
    "HISTORY_URL",
    "http://127.0.0.1:5002",
).rstrip("/")

REQUEST_TIMEOUT = 10


def is_debug_enabled():
    return os.getenv("FLASK_DEBUG", "false").lower() in {
        "1",
        "true",
        "yes",
    }


@app.get("/health")
def health():
    return jsonify({
        "service": "backend",
        "status": "ok",
    })


@app.get("/api/weather")
def weather():
    city = request.args.get("city", "").strip()

    if not city:
        return jsonify({
            "error": "City is required."
        }), 400

    try:
        location_response = requests.get(
            GEOCODING_URL,
            params={
                "name": city,
                "count": 1,
                "language": "en",
                "format": "json",
            },
            timeout=REQUEST_TIMEOUT,
        )

        location_response.raise_for_status()
        location_data = location_response.json()

        locations = location_data.get("results", [])

        if not locations:
            return jsonify({
                "error": "City was not found."
            }), 404

        location = locations[0]

        weather_response = requests.get(
            WEATHER_URL,
            params={
                "latitude": location["latitude"],
                "longitude": location["longitude"],
                "current": (
                    "temperature_2m,"
                    "relative_humidity_2m,"
                    "wind_speed_10m"
                ),
            },
            timeout=REQUEST_TIMEOUT,
        )

        weather_response.raise_for_status()
        weather_data = weather_response.json()

    except (
        requests.RequestException,
        KeyError,
        ValueError,
    ):
        return jsonify({
            "error": (
                "The public weather API is unavailable "
                "or returned invalid data."
            )
        }), 502

    result = {
        "query": city,
        "location": {
            "name": location.get("name", city),
            "country": location.get("country"),
            "latitude": location["latitude"],
            "longitude": location["longitude"],
        },
        "current": weather_data.get("current", {}),
        "current_units": weather_data.get(
            "current_units",
            {},
        ),
        "source": "open-meteo",
    }

    try:
        save_response = requests.post(
            f"{HISTORY_URL}/history",
            json={
                "query": city,
                "response_data": result,
                "source": "open-meteo",
                "status": "success",
            },
            timeout=REQUEST_TIMEOUT,
        )

        save_response.raise_for_status()

    except requests.RequestException:
        return jsonify({
            "error": (
                "Weather data was received, but the "
                "History Service could not save the request."
            )
        }), 503

    return jsonify(result)


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
            "error": "History Service is unavailable."
        }), 503


@app.delete("/api/history")
def clear_history():
    try:
        response = requests.delete(
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
            "error": "History Service is unavailable."
        }), 503


if __name__ == "__main__":
    app.run(
        host=os.getenv("APP_HOST", "127.0.0.1"),
        port=int(os.getenv("APP_PORT", "5001")),
        debug=is_debug_enabled(),
    )