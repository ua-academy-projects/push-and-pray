import json
import os

import psycopg
from dotenv import load_dotenv
from flask import Flask, jsonify, request
from psycopg.rows import dict_row

load_dotenv()

app = Flask(__name__)

DATABASE_URL = os.getenv("DATABASE_URL")


def get_connection():
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
                    requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
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

    except psycopg.Error:
        return jsonify({
            "service": "history",
            "status": "error",
            "database": "unavailable",
        }), 503


@app.post("/history")
def save_history():
    data = request.get_json(silent=True)

    if not data:
        return jsonify({
            "error": "JSON body is required."
        }), 400

    query = data.get("query")
    response_data = data.get("response_data")
    source = data.get("source")
    status = data.get("status", "success")

    if not query or response_data is None:
        return jsonify({
            "error": "query and response_data are required."
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
                        json.dumps(response_data),
                        source,
                        status,
                    ),
                )

                saved_record = cursor.fetchone()

        return jsonify({
            "message": "History record saved.",
            "record": saved_record,
        }), 201

    except psycopg.Error:
        return jsonify({
            "error": "Could not save history record."
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

    except psycopg.Error:
        return jsonify({
            "error": "Could not load history."
        }), 500

@app.delete("/history")
def clear_history():
    try:
        with get_connection() as connection:
            with connection.cursor() as cursor:
                cursor.execute(
                    """
                    DELETE FROM weather_requests
                    RETURNING id;
                    """
                )

                deleted_records = cursor.fetchall()

        return jsonify({
            "message": "History cleared.",
            "deleted_count": len(deleted_records),
        })

    except psycopg.Error:
        return jsonify({
            "error": "Could not clear history."
        }), 500

if __name__ == "__main__":
    if not DATABASE_URL:
        raise RuntimeError("DATABASE_URL is not configured.")

    create_table()

    app.run(
        host="127.0.0.1",
        port=5002,
        debug=True,
    )
