

import os
import logging

import requests
from flask import Flask, render_template, request, jsonify

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ui-service")

app = Flask(__name__)

PROXY_SERVICE_URL = os.getenv("PROXY_SERVICE_URL", "http://localhost:5001")


@app.route("/", methods=["GET"])
def index():
    return render_template("index.html")


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "ui-service"})


@app.route("/history", methods=["GET"])
def history():
    try:
        # Передаємо ліміт далі до Proxy, щоб UI міг побудувати графік
        # за більшою кількістю вже збережених у БД точок.
        limit = request.args.get("limit")
        params = {"limit": limit} if limit else None
        resp = requests.get(
            f"{PROXY_SERVICE_URL}/api/history", params=params, timeout=15
        )
        return jsonify(resp.json()), resp.status_code
    except requests.RequestException as exc:
        logger.exception("Proxy недоступний")
        return jsonify({"error": f"Proxy недоступний: {exc}"}), 502

@app.route("/hourly", methods=["GET"])
def hourly():
    try:
        resp = requests.get(f"{PROXY_SERVICE_URL}/api/hourly", timeout=15)
        return jsonify(resp.json()), resp.status_code
    except requests.RequestException as exc:
        logger.exception("Proxy недоступний")
        return jsonify({"error": f"Proxy недоступний: {exc}"}), 502

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
