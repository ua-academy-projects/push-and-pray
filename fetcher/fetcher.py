import json
import logging
import os
import time
from datetime import datetime, timezone

import pika
import psycopg2
import psycopg2.extras
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

DB_HOST = os.getenv("DB_HOST", "db.local")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "weather_db")
DB_USER = os.getenv("DB_USER", "weather_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "weather_password")

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "db.local")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.getenv("RABBITMQ_USER", "weather")
RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD", "weather_rabbit_password")
RABBITMQ_VHOST = os.getenv("RABBITMQ_VHOST", "weather")
RABBITMQ_QUEUE = os.getenv("RABBITMQ_QUEUE", "weather_updates")

WEATHER_API_URL = os.getenv(
    "WEATHER_API_URL",
    "https://api.open-meteo.com/v1/forecast",
)
FETCH_INTERVAL_SECONDS = int(os.getenv("FETCH_INTERVAL_SECONDS", "1800"))
REQUEST_TIMEOUT_SECONDS = int(os.getenv("REQUEST_TIMEOUT_SECONDS", "25"))

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("fetcher")

WEATHER_CODES = {
    0: "Ясно",
    1: "Переважно ясно",
    2: "Мінлива хмарність",
    3: "Хмарно",
    45: "Туман",
    48: "Туман з памороззю",
    51: "Легка мряка",
    53: "Мряка",
    55: "Сильна мряка",
    56: "Легка крижана мряка",
    57: "Сильна крижана мряка",
    61: "Невеликий дощ",
    63: "Дощ",
    65: "Сильний дощ",
    66: "Легкий крижаний дощ",
    67: "Сильний крижаний дощ",
    71: "Невеликий сніг",
    73: "Сніг",
    75: "Сильний сніг",
    77: "Снігові зерна",
    80: "Невеликі зливи",
    81: "Зливи",
    82: "Сильні зливи",
    85: "Невеликі снігові заряди",
    86: "Сильні снігові заряди",
    95: "Гроза",
    96: "Гроза з невеликим градом",
    99: "Гроза з сильним градом",
}


def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=10,
        application_name="weather-fetcher",
    )


def wait_for_database():
    while True:
        try:
            connection = get_db_connection()
            connection.close()
            logger.info("PostgreSQL is available")
            return
        except psycopg2.Error as error:
            logger.warning("PostgreSQL unavailable: %s. Retrying in 5 seconds.", error)
            time.sleep(5)


def load_active_cities():
    connection = get_db_connection()
    try:
        with connection.cursor(
            cursor_factory=psycopg2.extras.RealDictCursor
        ) as cursor:
            cursor.execute(
                """
                SELECT id, name, name_en, oblast, latitude, longitude
                FROM cities
                WHERE active = TRUE
                ORDER BY id;
                """
            )
            return [dict(row) for row in cursor.fetchall()]
    finally:
        connection.close()


def build_http_session():
    retry = Retry(
        total=3,
        connect=3,
        read=3,
        status=3,
        backoff_factor=1,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET",),
    )
    adapter = HTTPAdapter(max_retries=retry)
    session = requests.Session()
    session.headers.update({"User-Agent": "weather-vagrant-fetcher/1.0"})
    session.mount("https://", adapter)
    return session


def normalize_observed_at(value):
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat()


def fetch_city_weather(session, city):
    response = session.get(
        WEATHER_API_URL,
        params={
            "latitude": city["latitude"],
            "longitude": city["longitude"],
            "current": ",".join(
                [
                    "temperature_2m",
                    "apparent_temperature",
                    "relative_humidity_2m",
                    "pressure_msl",
                    "wind_speed_10m",
                    "weather_code",
                ]
            ),
            "timezone": "UTC",
            "wind_speed_unit": "kmh",
        },
        timeout=REQUEST_TIMEOUT_SECONDS,
    )
    response.raise_for_status()
    data = response.json()
    current = data.get("current")

    if not isinstance(current, dict):
        raise ValueError("Open-Meteo response has no current weather block")

    weather_code = current.get("weather_code")
    if weather_code is not None:
        weather_code = int(weather_code)

    return {
        "schema_version": 1,
        "city_id": city["id"],
        "city": city["name"],
        "city_en": city["name_en"],
        "oblast": city["oblast"],
        "country": "Україна",
        "latitude": city["latitude"],
        "longitude": city["longitude"],
        "temperature": current["temperature_2m"],
        "feels_like": current.get("apparent_temperature"),
        "humidity": current.get("relative_humidity_2m"),
        "pressure": current.get("pressure_msl"),
        "wind_speed": current.get("wind_speed_10m"),
        "weather_code": weather_code,
        "weather_description": WEATHER_CODES.get(weather_code, "Невідомо"),
        "source": "Open-Meteo",
        "observed_at": normalize_observed_at(current["time"]),
        "fetched_at": datetime.now(timezone.utc).isoformat(),
    }


def connect_rabbitmq():
    credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASSWORD)
    parameters = pika.ConnectionParameters(
        host=RABBITMQ_HOST,
        port=RABBITMQ_PORT,
        virtual_host=RABBITMQ_VHOST,
        credentials=credentials,
        heartbeat=60,
        blocked_connection_timeout=60,
        connection_attempts=12,
        retry_delay=5,
    )
    return pika.BlockingConnection(parameters)


def publish(channel, payload):
    channel.basic_publish(
        exchange="",
        routing_key=RABBITMQ_QUEUE,
        body=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        properties=pika.BasicProperties(
            content_type="application/json",
            content_encoding="utf-8",
            delivery_mode=2,
            timestamp=int(time.time()),
            type="weather.current",
        ),
        mandatory=True,
    )


def fetch_all():
    cities = load_active_cities()
    if not cities:
        logger.warning("No active cities in PostgreSQL")
        return

    logger.info("Starting weather update for %s cities", len(cities))
    session = build_http_session()
    rabbit_connection = connect_rabbitmq()
    success_count = 0
    failure_count = 0

    try:
        channel = rabbit_connection.channel()
        channel.queue_declare(queue=RABBITMQ_QUEUE, durable=True)
        channel.confirm_delivery()

        for city in cities:
            try:
                payload = fetch_city_weather(session, city)
                publish(channel, payload)
                success_count += 1
                logger.info(
                    "Published %s: %s °C, observed %s",
                    city["name"],
                    payload["temperature"],
                    payload["observed_at"],
                )
            except requests.RequestException as error:
                failure_count += 1
                logger.error("Open-Meteo failed for %s: %s", city["name"], error)
            except (KeyError, TypeError, ValueError) as error:
                failure_count += 1
                logger.error("Invalid weather data for %s: %s", city["name"], error)
    finally:
        session.close()
        if rabbit_connection.is_open:
            rabbit_connection.close()

    logger.info(
        "Weather update finished: success=%s failed=%s",
        success_count,
        failure_count,
    )


def main():
    wait_for_database()

    while True:
        try:
            # First call happens immediately after the service starts.
            fetch_all()
            logger.info("Next update in %s seconds", FETCH_INTERVAL_SECONDS)
            time.sleep(FETCH_INTERVAL_SECONDS)
        except KeyboardInterrupt:
            logger.info("Fetcher stopped")
            return
        except (pika.exceptions.AMQPError, psycopg2.Error, OSError) as error:
            logger.warning("Dependency error: %s. Retrying full cycle in 30 seconds.", error)
            time.sleep(30)
        except Exception as error:
            logger.exception("Unexpected fetcher error: %s", error)
            time.sleep(30)


if __name__ == "__main__":
    main()
