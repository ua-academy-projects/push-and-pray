import json
import os
import uuid

import redis
import requests
from flask import (
    Flask,
    jsonify,
    make_response,
    render_template,
    request,
)

app = Flask(__name__)

BACKEND_URL = os.getenv(
    "BACKEND_URL",
    "http://127.0.0.1:5001",
).rstrip("/")

REDIS_URL = os.getenv(
    "REDIS_URL",
    "redis://127.0.0.1:6379/0",
)

REQUEST_TIMEOUT = 10
SESSION_COOKIE_NAME = "session_id"
SESSION_TTL_SECONDS = 30 * 24 * 60 * 60  # 30 days

def get_redis_client():
    try:
        client = redis.Redis.from_url(
            REDIS_URL,
            decode_responses=True,
            socket_timeout=3,
        )
        return client
    except Exception as error:
        app.logger.warning("Could not connect to Redis: %s", error)
        return None


def is_debug_enabled():
    return os.getenv("FLASK_DEBUG", "false").lower() in {
        "1",
        "true",
        "yes",
    }


def get_or_create_session_id():
    session_id = request.cookies.get(SESSION_COOKIE_NAME)
    is_new = False
    if not session_id:
        session_id = str(uuid.uuid4())
        is_new = True
    return session_id, is_new


def attach_session_cookie(response, session_id):
    response.set_cookie(
        SESSION_COOKIE_NAME,
        session_id,
        max_age=SESSION_TTL_SECONDS,
        path="/",
        httponly=True,
        samesite="Lax",
    )
    return response


def get_session_state(session_id):
    default_state = {
        "history_hours": 24,
        "visible_table_rows": 10,
    }
    client = get_redis_client()
    if not client:
        return default_state

    try:
        raw_data = client.get(f"session:{session_id}")
        if raw_data:
            stored_state = json.loads(raw_data)
            default_state.update(stored_state)
    except Exception as error:
        app.logger.warning("Redis read error for session %s: %s", session_id, error)

    return default_state


def save_session_state(session_id, updates):
    state = get_session_state(session_id)

    if "history_hours" in updates:
        try:
            updates["history_hours"] = int(updates["history_hours"])
        except (ValueError, TypeError):
            pass

    if "visible_table_rows" in updates:
        try:
            updates["visible_table_rows"] = int(updates["visible_table_rows"])
        except (ValueError, TypeError):
            pass

    state.update(updates)

    client = get_redis_client()
    if client:
        try:
            client.setex(
                f"session:{session_id}",
                SESSION_TTL_SECONDS,
                json.dumps(state),
            )
            app.logger.info("Saved session %s state to Redis: %s", session_id, state)
        except Exception as error:
            app.logger.warning("Redis write error for session %s: %s", session_id, error)

    return state


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
    session_id, is_new = get_or_create_session_id()
    response = make_response(render_template("index.html"))
    return attach_session_cookie(response, session_id)


@app.get("/api/session")
def get_session():
    session_id, is_new = get_or_create_session_id()
    state = get_session_state(session_id)
    response = make_response(jsonify(state))
    return attach_session_cookie(response, session_id)


@app.post("/api/session")
def update_session():
    session_id, is_new = get_or_create_session_id()
    payload = request.get_json(silent=True) or {}
    updated_state = save_session_state(session_id, payload)
    response = make_response(jsonify(updated_state))
    return attach_session_cookie(response, session_id)


@app.get("/health")
def health():
    redis_status = "unavailable"
    client = get_redis_client()
    if client:
        try:
            client.ping()
            redis_status = "ok"
        except Exception:
            redis_status = "error"

    return jsonify({
        "service": "ui",
        "status": "ok",
        "redis": redis_status,
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
    # Forward the ?hours query param to backend unchanged
    hours = request.args.get("hours", "24")

    try:
        response = requests.get(
            f"{BACKEND_URL}/api/history",
            params={"hours": hours},
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
