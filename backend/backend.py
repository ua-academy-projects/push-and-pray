

import os
import json
import logging

import psycopg2
import psycopg2.extras
from flask import Flask, request, jsonify

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("backend-service")

app = Flask(__name__)

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

@app.route("/history", methods=["POST"])
def save_history():
    payload = request.get_json(silent=True)
    if not payload or "city" not in payload:
        return jsonify({"error": "Поле 'city' є обов'язковим"}), 400

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO weather_history
                    (city, latitude, longitude, temperature, windspeed, status, raw_response)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                RETURNING id, requested_at;
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
            new_id, requested_at = cur.fetchone()
        conn.commit()
        logger.info("Збережено запис #%s для міста %s", new_id, payload.get("city"))
        return jsonify({"id": new_id, "requested_at": requested_at.isoformat()}), 201
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        logger.exception("Помилка при збереженні запису")
        return jsonify({"error": str(exc)}), 500
    finally:
        conn.close()


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
@app.route("/history/hourly", methods=["POST"])
def save_hourly():
    """
    Приймає погодинний прогноз від Backend і зберігає/оновлює його
    (UPSERT по (city, forecast_hour) - повторний запис тієї ж години
    оновлює значення, а не створює дубль).
    """
    payload = request.get_json(silent=True)
    if not payload or "city" not in payload or "hours" not in payload:
        return jsonify({"error": "Поля 'city' та 'hours' є обов'язковими"}), 400

    city = payload["city"]
    latitude = payload.get("latitude")
    longitude = payload.get("longitude")
    hours = payload["hours"]

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
        logger.info("Збережено %s погодинних записів для міста %s", len(hours), city)
        return jsonify({"city": city, "saved_hours": len(hours)}), 201
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        logger.exception("Помилка при збереженні погодинного прогнозу")
        return jsonify({"error": str(exc)}), 500
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
    port = int(os.getenv("PORT", 5002))
    app.run(host="0.0.0.0", port=port)
