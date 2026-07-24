import os

import requests
from flask import (
    Flask,
    jsonify,
    render_template,
)

app = Flask(__name__)

BACKEND_URL = os.getenv(
    "BACKEND_URL",
    "http://127.0.0.1:5001",
).rstrip("/")

REQUEST_TIMEOUT = 10


def is_debug_enabled():
    return os.getenv("FLASK_DEBUG", "false").lower() in {
        "1",
        "true",
        "yes",
    }


def proxy_json_response(response):
    try:
        payload = response.json()

    except ValueError:
        payload = {
            "error": (
                "The Backend Service returned "
                "an invalid response."
            )
        }

    return jsonify(payload), response.status_code


@app.get("/")
def index():
    return render_template("index.html")


@app.get("/health")
def health():
    return jsonify({
        "service": "ui",
        "status": "ok",
    })


@app.get("/api/weather")
def weather():
    try:
        response = requests.get(
            f"{BACKEND_URL}/api/weather",
            timeout=REQUEST_TIMEOUT,
        )

        return proxy_json_response(response)

    except requests.RequestException:
        return jsonify({
            "error": "Backend Service is unavailable."
        }), 503


@app.get("/api/forecast")
def forecast():
    try:
        response = requests.get(
            f"{BACKEND_URL}/api/forecast",
            timeout=REQUEST_TIMEOUT,
        )

        return proxy_json_response(response)

    except requests.RequestException:
        return jsonify({
            "error": "Backend Service is unavailable."
        }), 503


@app.get("/api/history")
def history():
    try:
        response = requests.get(
            f"{BACKEND_URL}/api/history",
            timeout=REQUEST_TIMEOUT,
        )

        return proxy_json_response(response)

    except requests.RequestException:
        return jsonify({
            "error": "Backend Service is unavailable."
        }), 503


@app.delete("/api/history")
def clear_history():
    try:
        response = requests.delete(
            f"{BACKEND_URL}/api/history",
            timeout=REQUEST_TIMEOUT,
        )

        return proxy_json_response(response)

    except requests.RequestException:
        return jsonify({
            "error": "Backend Service is unavailable."
        }), 503


if __name__ == "__main__":
    app.run(
        host=os.getenv("APP_HOST", "0.0.0.0"),
        port=int(os.getenv("APP_PORT", "5000")),
        debug=is_debug_enabled(),
    )
