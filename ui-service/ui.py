import os
import uuid
import json
import logging

import redis
import requests
from flask import Flask, render_template, request, jsonify, make_response

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ui-service")

app = Flask(__name__)

BACKEND_SERVICE_URL = os.getenv("BACKEND_SERVICE_URL", "http://localhost:5002")

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
SESSION_TTL_SECONDS = 60 * 60 * 24  # 24 години - "ефемерна" сесія без автентифікації

redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

DEFAULT_UI_STATE = {
    "graph_period": 100,
    "filters": {"cities": ["Kyiv", "Warsaw", "Berlin"]},
    "history_expanded": False,
}


def get_or_create_session_id() -> str:
    """Читає session_id з cookie; якщо нема - генерує новий."""
    return request.cookies.get("session_id") or str(uuid.uuid4())


def attach_session_cookie(response, session_id: str):
    """Проставляє/продовжує cookie з session_id при кожній відповіді."""
    response.set_cookie(
        "session_id",
        session_id,
        max_age=SESSION_TTL_SECONDS,
        httponly=True,
        samesite="Lax",
    )
    return response


@app.route("/", methods=["GET"])
def index():
    # A visit to the UI itself starts an anonymous, browser-scoped session.
    session_id = get_or_create_session_id()
    redis_client.set(
        f"session:{session_id}",
        json.dumps(DEFAULT_UI_STATE),
        ex=SESSION_TTL_SECONDS,
        nx=True,
    )
    response = make_response(render_template("index.html"))
    return attach_session_cookie(response, session_id)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "ui-service"})


@app.route("/session/state", methods=["GET"])
def get_session_state():
    """Повертає збережений UI-стан для поточної сесії (або дефолти)."""
    session_id = get_or_create_session_id()
    raw = redis_client.get(f"session:{session_id}")
    state = json.loads(raw) if raw else DEFAULT_UI_STATE
    return attach_session_cookie(jsonify(state), session_id)


@app.route("/session/state", methods=["POST"])
def save_session_state():
    """Зберігає UI-стан (період графіка, фільтри, toggle'и) для поточної сесії."""
    session_id = get_or_create_session_id()
    payload = request.get_json(silent=True) or {}
    redis_client.set(f"session:{session_id}", json.dumps(payload), ex=SESSION_TTL_SECONDS)
    return attach_session_cookie(jsonify({"status": "saved"}), session_id)


@app.route("/history", methods=["GET"])
def history():
    try:
        limit = request.args.get("limit")
        params = {"limit": limit} if limit else None
        resp = requests.get(f"{BACKEND_SERVICE_URL}/history", params=params, timeout=15)
        return jsonify(resp.json()), resp.status_code
    except requests.RequestException as exc:
        logger.exception("Backend недоступний")
        return jsonify({"error": f"Backend недоступний: {exc}"}), 502


@app.route("/hourly", methods=["GET"])
def hourly():
    try:
        resp = requests.get(f"{BACKEND_SERVICE_URL}/history/hourly", timeout=15)
        return jsonify(resp.json()), resp.status_code
    except requests.RequestException as exc:
        logger.exception("Backend недоступний")
        return jsonify({"error": f"Backend недоступний: {exc}"}), 502


if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
