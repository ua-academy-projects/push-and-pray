
import os
import logging

import requests
from flask import Flask, request, jsonify

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("proxy-service")

app = Flask(__name__)

BACKEND_SERVICE_URL = os.getenv("BACKEND_SERVICE_URL", "http://localhost:5002")

GEOCODING_API = "https://geocoding-api.open-meteo.com/v1/search"
WEATHER_API = "https://api.open-meteo.com/v1/forecast"


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "proxy-service"})


def geocode_city(city: str):
    resp = requests.get(GEOCODING_API, params={"name": city, "count": 1}, timeout=10)
    resp.raise_for_status()
    data = resp.json()
    results = data.get("results")
    if not results:
        return None
    place = results[0]
    return {
        "latitude": place["latitude"],
        "longitude": place["longitude"],
        "resolved_name": place.get("name", city),
        "country": place.get("country"),
    }


def fetch_weather(latitude: float, longitude: float):
    resp = requests.get(
        WEATHER_API,
        params={
            "latitude": latitude,
            "longitude": longitude,
            "current_weather": "true",
            "hourly": "temperature_2m,precipitation,weathercode",
            "timezone": "auto",
            "forecast_days": 1,
        },
        timeout=10,
    )
    resp.raise_for_status()
    return resp.json()


@app.route("/api/current", methods=["GET"])
def get_current_weather():
    city = request.args.get("city", "").strip()
    if not city:
        return jsonify({"error": "Параметр 'city' є обов'язковим"}), 400
    try:
        location = geocode_city(city)
        if location is None:
            return jsonify({"error": f"Місто '{city}' не знайдено"}), 404

        weather_data = fetch_weather(location["latitude"], location["longitude"])
        current = weather_data.get("current_weather", {})

        record = {
            "city": location["resolved_name"],
            "latitude": location["latitude"],
            "longitude": location["longitude"],
            "temperature": current.get("temperature"),
            "windspeed": current.get("windspeed"),
            "status": "ok",
            "raw_response": weather_data,
        }

        try:
            save_resp = requests.post(
                f"{BACKEND_SERVICE_URL}/history", json=record, timeout=10
            )
            save_resp.raise_for_status()
        except requests.RequestException:
            logger.exception("Не вдалося зберегти запис у Backend Service")

        # Погодинний прогноз - окремий запис у окрему таблицю
        hourly = weather_data.get("hourly", {})
        times = hourly.get("time", [])
        temps = hourly.get("temperature_2m", [])
        precs = hourly.get("precipitation", [])
        codes = hourly.get("weathercode", [])

        hours = [
            {"time": t, "temperature": temp, "precipitation": prec, "weathercode": code}
            for t, temp, prec, code in zip(times, temps, precs, codes)
        ]

        if hours:
            try:
                hourly_resp = requests.post(
                    f"{BACKEND_SERVICE_URL}/history/hourly",
                    json={
                        "city": location["resolved_name"],
                        "latitude": location["latitude"],
                        "longitude": location["longitude"],
                        "hours": hours,
                    },
                    timeout=15,
                )
                hourly_resp.raise_for_status()
            except requests.RequestException:
                logger.exception("Не вдалося зберегти погодинний прогноз у Backend Service")

        return jsonify(record)
    except requests.RequestException as exc:
        logger.exception("Помилка звернення до публічного API")
        return jsonify({"error": f"Публічне API недоступне: {exc}"}), 502


@app.route("/api/history", methods=["GET"])
def get_history():
    limit = request.args.get("limit", default=20)
    try:
        resp = requests.get(
            f"{BACKEND_SERVICE_URL}/history", params={"limit": limit}, timeout=10
        )
        resp.raise_for_status()
        return jsonify(resp.json())
    except requests.RequestException as exc:
        logger.exception("Помилка звернення до Backend Service")
        return jsonify({"error": f"Backend Service недоступний: {exc}"}), 502

@app.route("/api/hourly", methods=["GET"])
def get_hourly():
    try:
        resp = requests.get(f"{BACKEND_SERVICE_URL}/history/hourly", timeout=10)
        resp.raise_for_status()
        return jsonify(resp.json())
    except requests.RequestException as exc:
        logger.exception("Помилка звернення до Backend Service (hourly)")
        return jsonify({"error": f"Backend Service недоступний: {exc}"}), 502

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5001))
    app.run(host="0.0.0.0", port=port)
