from flask import Flask, jsonify, render_template, request

from app.clients.backend import (
    BackendClient,
    BackendServiceError,
)
from app.config import get_settings


ALLOWED_HISTORY_PERIODS = {12, 24}


def create_app() -> Flask:
    """Create and configure the Frontend Service."""

    app = Flask(__name__)

    settings = get_settings()
    backend_client = BackendClient(settings)

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
        if not backend_client.is_ready():
            return (
                jsonify(
                    {
                        "detail": "Backend Service is unavailable",
                    }
                ),
                503,
            )

        return jsonify(
            {
                "service": "frontend-service",
                "status": "ready",
                "backend_service": "connected",
            }
        )

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