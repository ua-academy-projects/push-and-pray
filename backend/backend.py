

import os
import json
import logging
import threading
import time

import pika
import psycopg2
import psycopg2.extras
from flask import Flask, request, jsonify

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("backend-service")

app = Flask(__name__)

RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://guest:guest@localhost:5672/")
QUEUE_NAME = "weather_events"

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "5432"),
    "dbname": os.getenv("DB_NAME", "taska-db"),
    "user": os.getenv("DB_USER", "admin"),
    "password": os.getenv("DB_PASSWORD", "admin"),
}


def get_connection():
    return psycopg2.connect(**DB_CONFIG)


def init_db():
    schema_path = os.path.join(os.path.dirname(__file__), "db.sql")
    with open(schema_path, "r", encoding="utf-8") as f:
        schema_sql = f.read()

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(schema_sql)
        conn.commit()
        logger.info("Схему бази даних перевірено/створено успішно.")
    finally:
        conn.close()


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "backend-service"})


def save_current(payload: dict):
    """Persist one current-weather event consumed from RabbitMQ."""
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO weather_history
                    (city, latitude, longitude, temperature, windspeed, status, raw_response)
                VALUES (%s, %s, %s, %s, %s, %s, %s);
                """,
                (
                    payload.get("city"),
                    payload.get("latitude"),
                    payload.get("longitude"),
                    payload.get("temperature"),
                    payload.get("windspeed"),
                    payload.get("status", "ok"),
                    json.dumps(payload.get("raw_response", {})),
                ),
            )
        conn.commit()
    finally:
        conn.close()


def save_hourly(payload: dict):
    """Upsert hourly forecast events consumed from RabbitMQ."""
    city = payload["city"]
    latitude = payload.get("latitude")
    longitude = payload.get("longitude")
    hours = payload.get("hours", [])

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            for hour in hours:
                cur.execute(
                    """
                    INSERT INTO weather_hourly
                        (city, latitude, longitude, forecast_hour,
                         temperature, precipitation, weathercode, windspeed)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (city, forecast_hour)
                    DO UPDATE SET
                        temperature = EXCLUDED.temperature,
                        precipitation = EXCLUDED.precipitation,
                        weathercode = EXCLUDED.weathercode,
                        windspeed = EXCLUDED.windspeed,
                        forecast_fetched_at = now();
                    """,
                    (
                        city, latitude, longitude,
                        hour.get("time"),
                        hour.get("temperature"),
                        hour.get("precipitation"),
                        hour.get("weathercode"),
                        hour.get("windspeed"),
                    ),
                )
        conn.commit()
    finally:
        conn.close()


def on_weather_event(channel, method, _properties, body):
    """Handle and acknowledge one event only after its DB transaction commits."""
    try:
        message = json.loads(body)
        event_type = message.get("type")
        payload = message.get("payload", {})

        if event_type == "weather_current":
            save_current(payload)
        elif event_type == "weather_hourly":
            save_hourly(payload)
        else:
            logger.warning("Невідомий тип події: %s", event_type)

        channel.basic_ack(delivery_tag=method.delivery_tag)
        logger.info("Оброблено RabbitMQ-подію %s", event_type)
    except Exception:
        logger.exception("Помилка обробки повідомлення - повертаю в чергу")
        channel.basic_nack(delivery_tag=method.delivery_tag, requeue=True)


def consume_weather_events():
    """Run the Backend's RabbitMQ consumer, reconnecting after broker failures."""
    while True:
        try:
            connection = pika.BlockingConnection(pika.URLParameters(RABBITMQ_URL))
            channel = connection.channel()
            channel.queue_declare(queue=QUEUE_NAME, durable=True)
            channel.basic_qos(prefetch_count=1)
            channel.basic_consume(queue=QUEUE_NAME, on_message_callback=on_weather_event)
            logger.info("Backend слухає RabbitMQ-чергу '%s'", QUEUE_NAME)
            channel.start_consuming()
        except Exception:
            logger.exception("RabbitMQ consumer зупинився; повторне підключення через 5 секунд")
            time.sleep(5)


@app.route("/history", methods=["GET"])
def get_history():
    limit = request.args.get("limit", default=20, type=int)
    limit = max(1, min(limit, 100))

    conn = get_connection()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                """
                SELECT id, requested_at, city, latitude, longitude,
                       temperature, windspeed, source, status
                FROM weather_history
                ORDER BY requested_at DESC
                LIMIT %s;
                """,
                (limit,),
            )
            rows = cur.fetchall()

        for row in rows:
            row["requested_at"] = row["requested_at"].isoformat()

        return jsonify(rows)
    finally:
        conn.close()


@app.route("/history/hourly", methods=["GET"])
def get_hourly():
    """
    Повертає погодинний прогноз для ВСІХ міст одразу, але тільки для
    годин від поточної до кінця збереженого прогнозу (минулі години
    відсікаються прямо в SQL - тому "зараз 14:00" автоматично покаже
    лише 14:00 і пізніше).
    """
    conn = get_connection()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                """
                SELECT city, forecast_hour, temperature, precipitation, weathercode
                FROM weather_hourly
                WHERE forecast_hour >= date_trunc('hour', now())
                ORDER BY city, forecast_hour ASC;
                """
            )
            rows = cur.fetchall()
        for row in rows:
            row["forecast_hour"] = row["forecast_hour"].isoformat()
        return jsonify(rows)
    finally:
        conn.close()


if __name__ == "__main__":
    init_db()
    threading.Thread(target=consume_weather_events, daemon=True).start()
    port = int(os.getenv("PORT", 5002))
    app.run(host="0.0.0.0", port=port)
