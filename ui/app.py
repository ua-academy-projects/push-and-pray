import logging
import os
from datetime import timedelta

import redis
import requests
from flask import Flask, jsonify, render_template, request, session
from flask_session import Session

BACKEND_URL = os.getenv("BACKEND_URL", "http://backend.local:5000").rstrip("/")
REDIS_HOST = os.getenv("REDIS_HOST", "db.local")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "weather_redis_password")
REQUEST_TIMEOUT = int(os.getenv("REQUEST_TIMEOUT", "20"))

ALLOWED_METRICS = {
    "temperature",
    "feels_like",
    "humidity",
    "pressure",
    "wind_speed",
}
ALLOWED_PERIODS = {"24h", "7d", "30d", "all"}
DEFAULT_PREFERENCES = {
    "city_id": None,
    "metric": "temperature",
    "period": "7d",
    "auto_refresh": True,
    "compact_mode": False,
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("weather-ui")

app = Flask(__name__)
app.config.update(
    SECRET_KEY=os.getenv("SESSION_SECRET", "weather-session-secret-change-me"),
    SESSION_TYPE="redis",
    SESSION_REDIS=redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        password=REDIS_PASSWORD,
        socket_connect_timeout=5,
        socket_timeout=5,
    ),
    SESSION_KEY_PREFIX="weather_session:",
    SESSION_USE_SIGNER=True,
    SESSION_PERMANENT=True,
    PERMANENT_SESSION_LIFETIME=timedelta(days=30),
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
)
Session(app)


def current_preferences():
    saved = session.get("preferences", {})
    result = DEFAULT_PREFERENCES.copy()
    if isinstance(saved, dict):
        result.update({key: saved.get(key, value) for key, value in result.items()})
    return result


def backend_get(path, params=None):
    response = requests.get(
        f"{BACKEND_URL}{path}",
        params=params,
        timeout=REQUEST_TIMEOUT,
    )
    try:
        data = response.json()
    except ValueError:
        data = {"error": "Не вдалося отримати дані"}
    return response.status_code, data


def proxy_backend(path, params=None):
    try:
        status, data = backend_get(path, params)
        return jsonify(data), status
    except requests.Timeout:
        return jsonify({"error": "Сервіс тимчасово не відповідає"}), 504
    except requests.ConnectionError:
        return jsonify({"error": "Сервіс тимчасово недоступний"}), 503
    except requests.RequestException:
        logger.exception("Backend request failed: %s", path)
        return jsonify({"error": "Не вдалося отримати дані"}), 502


@app.before_request
def make_session_permanent():
    session.permanent = True


@app.get("/")
def index():
    return render_template("index.html")


@app.get("/api/preferences")
def get_preferences():
    return jsonify({"preferences": current_preferences(), "storage": "Redis"})


@app.post("/api/preferences")
def save_preferences():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return jsonify({"error": "Очікується JSON-об'єкт"}), 400

    preferences = current_preferences()

    if "city_id" in payload:
        value = payload["city_id"]
        if value is None or value == "":
            preferences["city_id"] = None
        else:
            try:
                city_id = int(value)
            except (TypeError, ValueError):
                return jsonify({"error": "city_id повинен бути числом"}), 400
            if city_id <= 0:
                return jsonify({"error": "city_id повинен бути додатним"}), 400
            preferences["city_id"] = city_id

    if "metric" in payload:
        metric = str(payload["metric"]).strip().lower()
        if metric not in ALLOWED_METRICS:
            return jsonify({"error": "Непідтримуваний показник"}), 400
        preferences["metric"] = metric

    if "period" in payload:
        period = str(payload["period"]).strip().lower()
        if period not in ALLOWED_PERIODS:
            return jsonify({"error": "Непідтримуваний період"}), 400
        preferences["period"] = period

    for key in ("auto_refresh", "compact_mode"):
        if key in payload:
            if not isinstance(payload[key], bool):
                return jsonify({"error": f"{key} повинен бути true або false"}), 400
            preferences[key] = payload[key]

    session["preferences"] = preferences
    session.modified = True
    return jsonify({"preferences": preferences, "storage": "Redis"})


@app.get("/api/cities")
def cities():
    return proxy_backend("/api/cities")


@app.get("/api/weather")
def weather():
    params = {}
    if request.args.get("city_id"):
        params["city_id"] = request.args["city_id"]
    if request.args.get("city"):
        params["city"] = request.args["city"]
    return proxy_backend("/api/weather", params)


@app.get("/api/history")
def history():
    params = {
        "limit": request.args.get("limit", "50"),
    }
    if request.args.get("city_id"):
        params["city_id"] = request.args["city_id"]
    if request.args.get("city"):
        params["city"] = request.args["city"]
    return proxy_backend("/api/history", params)


@app.get("/api/chart")
def chart():
    params = {
        "period": request.args.get("period", "7d"),
        "metric": request.args.get("metric", "temperature"),
    }
    if request.args.get("city_id"):
        params["city_id"] = request.args["city_id"]
    if request.args.get("city"):
        params["city"] = request.args["city"]
    return proxy_backend("/api/chart", params)


@app.get("/api/health")
def health():
    return proxy_backend("/health")


@app.errorhandler(404)
def not_found(_error):
    return jsonify({"error": "Маршрут не знайдено"}), 404


@app.errorhandler(405)
def method_not_allowed(_error):
    return jsonify({"error": "Метод не дозволений"}), 405


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
