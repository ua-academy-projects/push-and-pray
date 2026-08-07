import json
import logging
import time
from datetime import datetime

import pika
import psycopg2

from database import get_connection, wait_for_database
from settings import (
    RABBITMQ_HOST,
    RABBITMQ_PASSWORD,
    RABBITMQ_PORT,
    RABBITMQ_QUEUE,
    RABBITMQ_USER,
    RABBITMQ_VHOST,
)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("backend-consumer")

INSERT_SQL = """
INSERT INTO weather_history (
    city_id,
    country,
    temperature,
    feels_like,
    humidity,
    pressure,
    wind_speed,
    weather_code,
    weather_description,
    source,
    observed_at,
    received_at
)
VALUES (
    %(city_id)s,
    %(country)s,
    %(temperature)s,
    %(feels_like)s,
    %(humidity)s,
    %(pressure)s,
    %(wind_speed)s,
    %(weather_code)s,
    %(weather_description)s,
    %(source)s,
    %(observed_at)s,
    CURRENT_TIMESTAMP
)
ON CONFLICT (city_id, observed_at) DO UPDATE SET
    country = EXCLUDED.country,
    temperature = EXCLUDED.temperature,
    feels_like = EXCLUDED.feels_like,
    humidity = EXCLUDED.humidity,
    pressure = EXCLUDED.pressure,
    wind_speed = EXCLUDED.wind_speed,
    weather_code = EXCLUDED.weather_code,
    weather_description = EXCLUDED.weather_description,
    source = EXCLUDED.source,
    received_at = CURRENT_TIMESTAMP
RETURNING id;
"""


def validate_message(payload):
    required = ["city_id", "temperature", "observed_at"]
    missing = [field for field in required if payload.get(field) is None]
    if missing:
        raise ValueError(f"Missing required fields: {', '.join(missing)}")

    try:
        city_id = int(payload["city_id"])
        temperature = float(payload["temperature"])
        datetime.fromisoformat(str(payload["observed_at"]).replace("Z", "+00:00"))
    except (TypeError, ValueError) as error:
        raise ValueError("Invalid city_id, temperature or observed_at") from error

    result = {
        "city_id": city_id,
        "country": str(payload.get("country") or "Україна")[:120],
        "temperature": temperature,
        "feels_like": optional_float(payload.get("feels_like")),
        "humidity": optional_int(payload.get("humidity")),
        "pressure": optional_float(payload.get("pressure")),
        "wind_speed": optional_float(payload.get("wind_speed")),
        "weather_code": optional_int(payload.get("weather_code")),
        "weather_description": str(payload.get("weather_description") or "Невідомо")[:255],
        "source": str(payload.get("source") or "Open-Meteo")[:80],
        "observed_at": str(payload["observed_at"]),
    }

    if result["humidity"] is not None and not 0 <= result["humidity"] <= 100:
        raise ValueError("Humidity must be between 0 and 100")

    return result


def optional_float(value):
    return None if value is None else float(value)


def optional_int(value):
    return None if value is None else int(value)


def save_weather(payload):
    connection = get_connection()
    try:
        with connection:
            with connection.cursor() as cursor:
                cursor.execute(INSERT_SQL, payload)
                return cursor.fetchone()[0]
    finally:
        connection.close()


def connect_rabbitmq():
    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
    parameters = pika.ConnectionParameters(
        host=RABBITMQ_HOST,
        port=RABBITMQ_PORT,
        virtual_host=RABBITMQ_VHOST,
        credentials=credentials,
        heartbeat=60,
        blocked_connection_timeout=60,
        connection_attempts=5,
        retry_delay=5,
    )
    return pika.BlockingConnection(parameters)


def on_message(channel, method, _properties, body):
    try:
        decoded = body.decode("utf-8")
        payload = validate_message(json.loads(decoded))
        row_id = save_weather(payload)
        channel.basic_ack(delivery_tag=method.delivery_tag)
        logger.info(
            "Stored message: city_id=%s row_id=%s observed_at=%s",
            payload["city_id"],
            row_id,
            payload["observed_at"],
        )
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError, TypeError) as error:
        logger.error("Rejecting invalid message: %s", error)
        channel.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
    except psycopg2.Error as error:
        logger.exception("Database error, message will be requeued: %s", error)
        time.sleep(5)
        channel.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
    except Exception as error:
        logger.exception("Unexpected consumer error, message will be requeued: %s", error)
        time.sleep(5)
        channel.basic_nack(delivery_tag=method.delivery_tag, requeue=True)


def consume_forever():
    wait_for_database()

    while True:
        connection = None
        try:
            logger.info("Connecting to RabbitMQ at %s:%s", RABBITMQ_HOST, RABBITMQ_PORT)
            connection = connect_rabbitmq()
            channel = connection.channel()
            channel.queue_declare(queue=RABBITMQ_QUEUE, durable=True)
            channel.basic_qos(prefetch_count=20)
            channel.basic_consume(
                queue=RABBITMQ_QUEUE,
                on_message_callback=on_message,
                auto_ack=False,
            )
            logger.info("Waiting for messages from queue '%s'", RABBITMQ_QUEUE)
            channel.start_consuming()
        except KeyboardInterrupt:
            logger.info("Consumer stopped")
            break
        except (pika.exceptions.AMQPError, OSError) as error:
            logger.warning("RabbitMQ unavailable: %s. Retrying in 10 seconds.", error)
            time.sleep(10)
        finally:
            if connection is not None and connection.is_open:
                connection.close()


if __name__ == "__main__":
    consume_forever()
