import os
import json
import logging

import pika
import psycopg2

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("history-consumer")

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


def save_current(payload: dict):
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
                    payload.get("city"), payload.get("latitude"), payload.get("longitude"),
                    payload.get("temperature"), payload.get("windspeed"),
                    payload.get("status", "ok"), json.dumps(payload.get("raw_response", {})),
                ),
            )
        conn.commit()
    finally:
        conn.close()


def save_hourly(payload: dict):
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            for hour in payload.get("hours", []):
                cur.execute(
                    """
                    INSERT INTO weather_hourly
                        (city, latitude, longitude, forecast_hour, temperature, precipitation, weathercode, windspeed)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (city, forecast_hour) DO UPDATE SET
                        temperature = EXCLUDED.temperature,
                        precipitation = EXCLUDED.precipitation,
                        weathercode = EXCLUDED.weathercode,
                        windspeed = EXCLUDED.windspeed,
                        forecast_fetched_at = now();
                    """,
                    (
                        payload["city"], payload.get("latitude"), payload.get("longitude"),
                        hour.get("time"), hour.get("temperature"),
                        hour.get("precipitation"), hour.get("weathercode"), hour.get("windspeed"),
                    ),
                )
        conn.commit()
    finally:
        conn.close()


def on_message(channel, method, properties, body):
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
        logger.info("Оброблено подію %s", event_type)
    except Exception:
        logger.exception("Помилка обробки повідомлення - повертаю в чергу")
        channel.basic_nack(delivery_tag=method.delivery_tag, requeue=True)


def main():
    connection = pika.BlockingConnection(pika.URLParameters(RABBITMQ_URL))
    channel = connection.channel()
    channel.queue_declare(queue=QUEUE_NAME, durable=True)
    channel.basic_qos(prefetch_count=1)
    channel.basic_consume(queue=QUEUE_NAME, on_message_callback=on_message)

    logger.info("Consumer запущено, слухаю чергу '%s'...", QUEUE_NAME)
    channel.start_consuming()


if __name__ == "__main__":
    main()
