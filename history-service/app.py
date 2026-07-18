import os

import psycopg
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

load_dotenv()

app = Flask(__name__)

DATABASE_URL = os.getenv("DATABASE_URL")


def is_debug_enabled():
    return os.getenv("FLASK_DEBUG", "false").lower() in {
        "1",
        "true",
        "yes",
    }


def get_connection():
    if not DATABASE_URL:
        raise RuntimeError(
            "DATABASE_URL is not configured."
        )

    return psycopg.connect(
        DATABASE_URL,
        row_factory=dict_row,
    )


def create_table():
    with get_connection() as connection:
        with connection.cursor() as cursor:
            cursor.execute(
                """
                CREATE TABLE IF NOT EXISTS weather_requests (
                    id BIGSERIAL PRIMARY KEY,
                    requested_at TIMESTAMPTZ
                        NOT NULL DEFAULT NOW(),
                    query TEXT NOT NULL,
                    response_data JSONB NOT NULL,
                    source TEXT,
                    status TEXT NOT NULL
                );
                """
            )


@app.get("/health")
def health():
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1;")

        return jsonify({
            "service": "history",
            "status": "ok",
            "database": "ok",
        })

    except (
        psycopg.Error,
        RuntimeError,
    ):
        return jsonify({
            "service": "history",
            "status": "error",
            "database": "unavailable",
        }), 503


@app.post("/history")
def save_history():
    data = request.get_json(silent=True)

    if not isinstance(data, dict):
        return jsonify({
            "error": "A JSON object is required."
        }), 400

    query = str(
        data.get("query", "")
    ).strip()

    response_data = data.get("response_data")
    source = data.get("source")

    status = str(
        data.get("status", "success")
    ).strip()

    if not query or response_data is None:
        return jsonify({
            "error": (
                "query and response_data are required."
            )
        }), 400

    if not status:
        return jsonify({
            "error": "status cannot be empty."
        }), 400

    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    INSERT INTO weather_requests (
                        query,
                        response_data,
                        source,
                        status
                    )
                    VALUES (%s, %s, %s, %s)
                    RETURNING id, requested_at;
                    """,
                    (
                        query,
                        Jsonb(response_data),
                        source,
                        status,
                    ),
                )

                saved_record = cursor.fetchone()

        return jsonify({
            "message": "History record saved.",
            "record": saved_record,
        }), 201

    except (
        psycopg.Error,
        RuntimeError,
    ):
        return jsonify({
            "error": (
                "Could not save history record."
            )
        }), 500


@app.get("/history")
def get_history():
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT
                        id,
                        requested_at,
                        query,
                        response_data,
                        source,
                        status
                    FROM weather_requests
                    ORDER BY requested_at DESC
                    LIMIT 50;
                    """
                )

                records = cursor.fetchall()

        return jsonify({
            "count": len(records),
            "items": records,
        })

    except (
        psycopg.Error,
        RuntimeError,
    ):
        return jsonify({
            "error": "Could not load history."
        }), 500


@app.delete("/history")
def clear_history():
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    "DELETE FROM weather_requests;"
                )

                deleted_count = cursor.rowcount

        return jsonify({
            "message": "History cleared.",
            "deleted_count": deleted_count,
        })

    except (
        psycopg.Error,
        RuntimeError,
    ):
        return jsonify({
            "error": "Could not clear history."
        }), 500


if __name__ == "__main__":
    create_table()

    app.run(
        host=os.getenv("APP_HOST", "127.0.0.1"),
        port=int(os.getenv("APP_PORT", "5002")),
        debug=is_debug_enabled(),
    )