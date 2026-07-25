import os
import json
import logging

import pika
import requests
from flask import Flask, request, jsonify

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("proxy-service")

app = Flask(__name__)

BACKEND_SERVICE_URL = os.getenv("BACKEND_SERVICE_URL", "http://localhost:5002")

GEOCODING_API = "https://geocoding-api.open-meteo.com/v1/search"
WEATHER_API = "https://api.open-meteo.com/v1/forecast"

RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://guest:guest@localhost:5672/")
QUEUE_NAME = "weather_events"


def publish_event(event_type: str, payload: dict):
    """
    Публікує повідомлення в RabbitMQ замість прямого HTTP POST у Backend Service.
    Якщо Backend Service тимчасово недоступний - повідомлення все одно
    залишиться в черзі (durable=True + delivery_mode=2) і буде оброблене,
    щойно consumer знову підключиться.
    """
    connection = pika.BlockingConnection(pika.URLParameters(RABBITMQ_URL))
    try:
        channel = connection.channel()
        channel.queue_declare(queue=QUEUE_NAME, durable=True)
        channel.confirm_delivery()
        channel.basic_publish(
            exchange="",
            routing_key=QUEUE_NAME,
            body=json.dumps({"type": event_type, "payload": payload}),
            properties=pika.BasicProperties(
                delivery_mode=2,  # persistent - зберігається на диск
                content_type="application/json",
            ),
        )
    finally:
        connection.close()


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

        # БУЛО: requests.post(f"{BACKEND_SERVICE_URL}/history", json=record, timeout=10)
        # СТАЛО: асинхронна публікація в чергу замість прямого HTTP-виклику
        try:
            publish_event("weather_current", record)
        except Exception as exc:  # the data must not be reported as saved when it was not queued
            logger.exception("Не вдалося опублікувати подію 'weather_current' в RabbitMQ")
            return jsonify({"error": f"Черга RabbitMQ недоступна: {exc}"}), 503

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

        # БУЛО: requests.post(f"{BACKEND_SERVICE_URL}/history/hourly", json={...}, timeout=15)
        # СТАЛО: асинхронна публікація в ту саму чергу з іншим типом події
        if hours:
            try:
                publish_event("weather_hourly", {
                    "city": location["resolved_name"],
                    "latitude": location["latitude"],
                    "longitude": location["longitude"],
                    "hours": hours,
                })
            except Exception as exc:
                logger.exception("Не вдалося опублікувати подію 'weather_hourly' в RabbitMQ")
                return jsonify({"error": f"Черга RabbitMQ недоступна: {exc}"}), 503

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
