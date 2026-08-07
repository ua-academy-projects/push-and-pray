import logging
from datetime import datetime, timezone

import psycopg2
import psycopg2.extras
from flask import Flask, jsonify, request

from database import get_connection

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("backend-api")

PERIODS = {
    "24h": "24 hours",
    "7d": "7 days",
    "30d": "30 days",
    "all": None,
}

METRICS = {
    "temperature": {
        "column": "temperature",
        "label": "Температура",
        "unit": "°C",
    },
    "feels_like": {
        "column": "feels_like",
        "label": "Відчувається як",
        "unit": "°C",
    },
    "humidity": {
        "column": "humidity",
        "label": "Вологість",
        "unit": "%",
    },
    "pressure": {
        "column": "pressure",
        "label": "Тиск",
        "unit": "hPa",
    },
    "wind_speed": {
        "column": "wind_speed",
        "label": "Швидкість вітру",
        "unit": "км/год",
    },
}

app = Flask(__name__)


def iso(value):
    return value.isoformat() if isinstance(value, datetime) else value


def execute_one(sql, parameters=()):
    connection = get_connection()
    try:
        with connection.cursor(
            cursor_factory=psycopg2.extras.RealDictCursor
        ) as cursor:
            cursor.execute(sql, parameters)
            return cursor.fetchone()
    finally:
        connection.close()


def execute_all(sql, parameters=()):
    connection = get_connection()
    try:
        with connection.cursor(
            cursor_factory=psycopg2.extras.RealDictCursor
        ) as cursor:
            cursor.execute(sql, parameters)
            return cursor.fetchall()
    finally:
        connection.close()


def resolve_city():
    city_id = request.args.get("city_id", "").strip()
    city_name = request.args.get("city", "").strip()

    if city_id:
        try:
            parsed_id = int(city_id)
        except ValueError as error:
            raise ValueError("city_id повинен бути цілим числом") from error

        row = execute_one(
            """
            SELECT id, name, name_en, oblast, latitude, longitude, active
            FROM cities
            WHERE id = %s AND active = TRUE;
            """,
            (parsed_id,),
        )
    elif city_name:
        row = execute_one(
            """
            SELECT id, name, name_en, oblast, latitude, longitude, active
            FROM cities
            WHERE active = TRUE
              AND (LOWER(name) = LOWER(%s) OR LOWER(name_en) = LOWER(%s));
            """,
            (city_name, city_name),
        )
    else:
        raise ValueError("Потрібно передати city_id або city")

    if row is None:
        raise LookupError("Місто не знайдено у списку активних обласних центрів")

    return dict(row)


def serialize_weather(row):
    return {
        "id": row["id"],
        "city_id": row["city_id"],
        "city": row["city"],
        "city_en": row["city_en"],
        "oblast": row["oblast"],
        "country": row["country"],
        "latitude": row["latitude"],
        "longitude": row["longitude"],
        "temperature": row["temperature"],
        "feels_like": row["feels_like"],
        "humidity": row["humidity"],
        "pressure": row["pressure"],
        "wind_speed": row["wind_speed"],
        "weather_code": row["weather_code"],
        "weather_description": row["weather_description"],
        "source": row["source"],
        "observed_at": iso(row["observed_at"]),
        "received_at": iso(row["received_at"]),
    }


@app.get("/")
def index():
    return jsonify(
        {
            "service": "weather-backend",
            "status": "running",
            "data_source": "PostgreSQL only",
            "consumer": "RabbitMQ -> PostgreSQL",
            "endpoints": [
                "/health",
                "/api/cities",
                "/api/weather?city_id=9",
                "/api/history?city_id=9&limit=50",
                "/api/chart?city_id=9&period=7d&metric=temperature",
            ],
        }
    )


@app.get("/health")
def health():
    try:
        row = execute_one(
            """
            SELECT
                (SELECT COUNT(*) FROM cities WHERE active = TRUE) AS active_cities,
                (SELECT COUNT(*) FROM weather_history) AS weather_rows,
                (SELECT MAX(received_at) FROM weather_history) AS last_received_at;
            """
        )

        return jsonify(
            {
                "service": "weather-backend",
                "status": "healthy",
                "database": "available",
                "active_cities": row["active_cities"],
                "weather_rows": row["weather_rows"],
                "last_received_at": iso(row["last_received_at"]),
                "checked_at": datetime.now(timezone.utc).isoformat(),
            }
        )
    except psycopg2.Error:
        logger.exception("Database health check failed")
        return (
            jsonify(
                {
                    "service": "weather-backend",
                    "status": "unhealthy",
                    "database": "unavailable",
                }
            ),
            503,
        )


@app.get("/api/cities")
def cities():
    try:
        rows = execute_all(
            """
            SELECT
                c.id,
                c.name,
                c.name_en,
                c.oblast,
                c.latitude,
                c.longitude,
                latest.observed_at AS latest_observed_at
            FROM cities c
            LEFT JOIN LATERAL (
                SELECT wh.observed_at
                FROM weather_history wh
                WHERE wh.city_id = c.id
                ORDER BY wh.observed_at DESC
                LIMIT 1
            ) latest ON TRUE
            WHERE c.active = TRUE
            ORDER BY c.name;
            """
        )

        items = []
        for row in rows:
            item = dict(row)
            item["latest_observed_at"] = iso(item["latest_observed_at"])
            items.append(item)

        return jsonify({"count": len(items), "items": items})
    except psycopg2.Error:
        logger.exception("Could not load cities")
        return jsonify({"error": "Не вдалося завантажити список міст"}), 500


@app.get("/api/weather")
def weather():
    try:
        city = resolve_city()
        row = execute_one(
            """
            SELECT
                wh.id,
                wh.city_id,
                c.name AS city,
                c.name_en AS city_en,
                c.oblast,
                wh.country,
                c.latitude,
                c.longitude,
                wh.temperature,
                wh.feels_like,
                wh.humidity,
                wh.pressure,
                wh.wind_speed,
                wh.weather_code,
                wh.weather_description,
                wh.source,
                wh.observed_at,
                wh.received_at
            FROM weather_history wh
            JOIN cities c ON c.id = wh.city_id
            WHERE wh.city_id = %s
            ORDER BY wh.observed_at DESC
            LIMIT 1;
            """,
            (city["id"],),
        )

        if row is None:
            return (
                jsonify(
                    {
                        "error": "Для цього міста ще немає даних. Спробуйте трохи пізніше.",
                        "city": city,
                    }
                ),
                404,
            )

        return jsonify({"weather": serialize_weather(row)})
    except ValueError as error:
        return jsonify({"error": str(error)}), 400
    except LookupError as error:
        return jsonify({"error": str(error)}), 404
    except psycopg2.Error:
        logger.exception("Could not load current weather")
        return jsonify({"error": "Не вдалося завантажити поточну погоду"}), 500


@app.get("/api/history")
def history():
    try:
        city = resolve_city()
        try:
            limit = int(request.args.get("limit", "50"))
        except ValueError as error:
            raise ValueError("limit повинен бути цілим числом") from error

        limit = max(1, min(limit, 500))
        rows = execute_all(
            """
            SELECT
                wh.id,
                wh.city_id,
                c.name AS city,
                c.name_en AS city_en,
                c.oblast,
                wh.country,
                c.latitude,
                c.longitude,
                wh.temperature,
                wh.feels_like,
                wh.humidity,
                wh.pressure,
                wh.wind_speed,
                wh.weather_code,
                wh.weather_description,
                wh.source,
                wh.observed_at,
                wh.received_at
            FROM weather_history wh
            JOIN cities c ON c.id = wh.city_id
            WHERE wh.city_id = %s
            ORDER BY wh.observed_at DESC
            LIMIT %s;
            """,
            (city["id"], limit),
        )

        return jsonify(
            {
                "city": city,
                "count": len(rows),
                "items": [serialize_weather(row) for row in rows],
            }
        )
    except ValueError as error:
        return jsonify({"error": str(error)}), 400
    except LookupError as error:
        return jsonify({"error": str(error)}), 404
    except psycopg2.Error:
        logger.exception("Could not load history")
        return jsonify({"error": "Не вдалося завантажити історію"}), 500


@app.get("/api/chart")
def chart():
    period = request.args.get("period", "7d").strip().lower()
    metric = request.args.get("metric", "temperature").strip().lower()

    if period not in PERIODS:
        return (
            jsonify(
                {
                    "error": "Невідомий період",
                    "allowed_periods": list(PERIODS),
                }
            ),
            400,
        )

    if metric not in METRICS:
        return (
            jsonify(
                {
                    "error": "Невідомий показник",
                    "allowed_metrics": list(METRICS),
                }
            ),
            400,
        )

    try:
        city = resolve_city()
        where = ["city_id = %s"]
        parameters = [city["id"]]

        if PERIODS[period] is not None:
            where.append("observed_at >= CURRENT_TIMESTAMP - %s::interval")
            parameters.append(PERIODS[period])

        column = METRICS[metric]["column"]
        rows = execute_all(
            f"""
            SELECT observed_at, {column} AS value
            FROM weather_history
            WHERE {' AND '.join(where)}
              AND {column} IS NOT NULL
            ORDER BY observed_at ASC
            LIMIT 2500;
            """,
            tuple(parameters),
        )

        info = METRICS[metric]
        return jsonify(
            {
                "city": city,
                "period": period,
                "metric": metric,
                "metric_label": info["label"],
                "unit": info["unit"],
                "count": len(rows),
                "labels": [iso(row["observed_at"]) for row in rows],
                "values": [row["value"] for row in rows],
            }
        )
    except ValueError as error:
        return jsonify({"error": str(error)}), 400
    except LookupError as error:
        return jsonify({"error": str(error)}), 404
    except psycopg2.Error:
        logger.exception("Could not load chart data")
        return jsonify({"error": "Не вдалося отримати дані графіка"}), 500


@app.errorhandler(404)
def not_found(_error):
    return jsonify({"error": "Маршрут не знайдено"}), 404


@app.errorhandler(405)
def method_not_allowed(_error):
    return jsonify({"error": "Метод не дозволений"}), 405


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
