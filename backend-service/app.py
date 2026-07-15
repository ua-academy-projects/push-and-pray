import requests
from flask import Flask, jsonify, request


app = Flask(__name__)

GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search"
WEATHER_URL = "https://api.open-meteo.com/v1/forecast"


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
            timeout=10,
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
            timeout=10,
        )

        weather_response.raise_for_status()
        weather_data = weather_response.json()

        result = {
            "query": city,
            "location": {
                "name": location["name"],
                "country": location.get("country"),
                "latitude": location["latitude"],
                "longitude": location["longitude"],
            },
            "current": weather_data.get("current", {}),
            "current_units": weather_data.get("current_units", {}),
            "source": "open-meteo",
        }

        return jsonify(result)

    except requests.RequestException:
        return jsonify({
            "error": "Public weather API is unavailable."
        }), 502


if __name__ == "__main__":
    app.run(
        host="127.0.0.1",
        port=5001,
        debug=True,
    )
