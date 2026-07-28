from datetime import timedelta
from typing import Final

import redis
from flask import (
    Flask,
    jsonify,
    render_template,
    request,
    session,
)
from flask_session import Session

from app.clients.backend import (
    BackendClient,
    BackendServiceError,
)
from app.config import get_settings


ALLOWED_HISTORY_PERIODS: Final[set[int]] = {12, 24}

ALLOWED_METRICS: Final[set[str]] = {
    "european_aqi",
    "us_aqi",
    "pm2_5",
    "pm10",
    "nitrogen_dioxide",
    "ozone",
    "carbon_monoxide",
    "uv_index",
}

DEFAULT_UI_PREFERENCES: Final[dict[str, object]] = {
    "selected_city": None,
    "period_hours": 12,
    "selected_metric": "european_aqi",
}


def get_ui_preferences() -> dict[str, object]:
    """Return current session UI preferences with defaults."""

    stored_preferences = session.get("ui_preferences", {})

    if not isinstance(stored_preferences, dict):
        stored_preferences = {}

    preferences = {
        **DEFAULT_UI_PREFERENCES,
        **stored_preferences,
    }

    session["ui_preferences"] = preferences
    session.permanent = True

    return preferences


def create_app() -> Flask:
    """Create and configure the Frontend Service."""

    app = Flask(__name__)

    settings = get_settings()
    backend_client = BackendClient(settings)

    redis_client = redis.Redis.from_url(
        settings.redis_url,
        decode_responses=False,
        socket_connect_timeout=3,
        socket_timeout=3,
    )

    app.config.update(
        SECRET_KEY=settings.flask_secret_key,
        SESSION_TYPE="redis",
        SESSION_REDIS=redis_client,
        SESSION_KEY_PREFIX=settings.session_key_prefix,
        SESSION_PERMANENT=True,
        PERMANENT_SESSION_LIFETIME=timedelta(
            seconds=settings.session_ttl_seconds,
        ),
        SESSION_USE_SIGNER=True,
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        SESSION_COOKIE_SECURE=False,
    )

    Session(app)

    @app.get("/")
    def index():
        return render_template("index.html")

    @app.get("/health")
    def health_check():
        return jsonify(
            {
                "service": "frontend-service",
                "status": "healthy",
            }
        )

    @app.get("/health/ready")
    def readiness_check():
        checks = {
            "backend_service": False,
            "redis": False,
        }

        if backend_client.is_ready():
            checks["backend_service"] = True

        try:
            redis_client.ping()
            checks["redis"] = True
        except redis.RedisError:
            pass

        if not all(checks.values()):
            return (
                jsonify(
                    {
                        "service": "frontend-service",
                        "status": "not_ready",
                        "checks": checks,
                    }
                ),
                503,
            )

        return jsonify(
            {
                "service": "frontend-service",
                "status": "ready",
                "checks": checks,
            }
        )

    @app.get("/api/session/preferences")
    def get_session_preferences():
        return jsonify(get_ui_preferences())

    @app.patch("/api/session/preferences")
    def update_session_preferences():
        payload = request.get_json(silent=True)

        if not isinstance(payload, dict):
            return (
                jsonify(
                    {
                        "detail": "A JSON object is required.",
                    }
                ),
                400,
            )

        preferences = get_ui_preferences()
        errors: dict[str, str] = {}

        if "selected_city" in payload:
            selected_city = payload["selected_city"]

            if (
                selected_city is not None
                and not isinstance(selected_city, str)
            ):
                errors["selected_city"] = (
                    "selected_city must be a string or null."
                )
            else:
                preferences["selected_city"] = selected_city

        if "period_hours" in payload:
            period_hours = payload["period_hours"]

            if (
                not isinstance(period_hours, int)
                or period_hours not in ALLOWED_HISTORY_PERIODS
            ):
                errors["period_hours"] = (
                    "period_hours must be either 12 or 24."
                )
            else:
                preferences["period_hours"] = period_hours

        if "selected_metric" in payload:
            selected_metric = payload["selected_metric"]

            if (
                not isinstance(selected_metric, str)
                or selected_metric not in ALLOWED_METRICS
            ):
                errors["selected_metric"] = (
                    "selected_metric is not supported."
                )
            else:
                preferences["selected_metric"] = selected_metric

        if errors:
            return (
                jsonify(
                    {
                        "detail": "Invalid UI preferences.",
                        "errors": errors,
                    }
                ),
                422,
            )

        session["ui_preferences"] = preferences
        session.modified = True
        session.permanent = True

        return jsonify(preferences)

    @app.get("/api/cities")
    def cities_proxy():
        try:
            payload = backend_client.list_cities()
        except BackendServiceError as exc:
            return (
                jsonify({"detail": str(exc)}),
                exc.status_code,
            )

        return jsonify(payload)

    @app.get("/api/dashboard")
    def dashboard_proxy():
        city = request.args.get("city", "").strip().lower()

        if not city:
            return (
                jsonify(
                    {
                        "detail": "The city parameter is required.",
                    }
                ),
                422,
            )

        raw_hours = request.args.get("hours", "24")

        try:
            hours = int(raw_hours)
        except ValueError:
            return (
                jsonify(
                    {
                        "detail": "Hours must be an integer.",
                    }
                ),
                422,
            )

        if hours not in ALLOWED_HISTORY_PERIODS:
            return (
                jsonify(
                    {
                        "detail": "Hours must be either 12 or 24.",
                    }
                ),
                422,
            )

        try:
            payload = backend_client.get_dashboard(
                city=city,
                hours=hours,
            )
        except BackendServiceError as exc:
            return (
                jsonify({"detail": str(exc)}),
                exc.status_code,
            )

        return jsonify(payload)

    return app


app = create_app()