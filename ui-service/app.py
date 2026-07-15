import os

import requests
from flask import Flask, jsonify, render_template, request

app = Flask(__name__)

BACKEND_URL = os.getenv(
    "BACKEND_URL",
    "http://127.0.0.1:5001",
)


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
    city = request.args.get("city", "").strip()

    if not city:
        return jsonify({
            "error": "City is required."
        }), 400

    try:
        response = requests.get(
            f"{BACKEND_URL}/api/weather",
            params={"city": city},
            timeout=10,
        )

        return jsonify(response.json()), response.status_code

    except requests.RequestException:
        return jsonify({
            "error": "Backend Service is unavailable."
        }), 503


@app.get("/api/history")
def history():
    try:
        response = requests.get(
            f"{BACKEND_URL}/api/history",
            timeout=10,
        )

        return jsonify(response.json()), response.status_code

    except requests.RequestException:
        return jsonify({
            "error": "Backend Service is unavailable."
        }), 503


if __name__ == "__main__":
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=True,
    )
