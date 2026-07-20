from flask import Flask, jsonify, render_template, request

from app.clients.api_service import (
    ApiServiceClient,
    ApiServiceError,
)
from app.config import get_settings


def create_app() -> Flask:
    """Create and configure the Flask application."""

    app = Flask(__name__)

    settings = get_settings()
    api_client = ApiServiceClient(settings)

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
        if not api_client.is_ready():
            return (
                jsonify(
                    {
                        "detail": "API Service is unavailable",
                    }
                ),
                503,
            )

        return jsonify(
            {
                "service": "frontend-service",
                "status": "ready",
                "api_service": "connected",
            }
        )

    @app.get("/api/air-quality")
    def air_quality_proxy():
        city = request.args.get("city", "").strip()

        if len(city) < 2:
            return (
                jsonify(
                    {
                        "detail": (
                            "City must contain at least "
                            "two non-space characters"
                        )
                    }
                ),
                422,
            )

        try:
            payload = api_client.get_air_quality(city)
        except ApiServiceError as exc:
            return (
                jsonify({"detail": str(exc)}),
                exc.status_code,
            )

        return jsonify(payload)

    @app.get("/api/history")
    def history_proxy():
        limit = _parse_integer_query_parameter(
            "limit",
            default=20,
            minimum=1,
            maximum=100,
        )

        if isinstance(limit, tuple):
            return limit

        offset = _parse_integer_query_parameter(
            "offset",
            default=0,
            minimum=0,
        )

        if isinstance(offset, tuple):
            return offset

        try:
            payload = api_client.list_history(
                limit=limit,
                offset=offset,
            )
        except ApiServiceError as exc:
            return (
                jsonify({"detail": str(exc)}),
                exc.status_code,
            )

        return jsonify(payload)

    @app.get("/api/history/<int:record_id>")
    def history_record_proxy(record_id: int):
        try:
            payload = api_client.get_history_record(record_id)
        except ApiServiceError as exc:
            return (
                jsonify({"detail": str(exc)}),
                exc.status_code,
            )

        return jsonify(payload)

    return app


def _parse_integer_query_parameter(
    name: str,
    *,
    default: int,
    minimum: int,
    maximum: int | None = None,
):
    raw_value = request.args.get(name)

    if raw_value is None:
        return default

    try:
        value = int(raw_value)
    except ValueError:
        return (
            jsonify(
                {
                    "detail": f"{name} must be an integer",
                }
            ),
            422,
        )

    if value < minimum:
        return (
            jsonify(
                {
                    "detail": (
                        f"{name} must be greater than "
                        f"or equal to {minimum}"
                    )
                }
            ),
            422,
        )

    if maximum is not None and value > maximum:
        return (
            jsonify(
                {
                    "detail": (
                        f"{name} must be less than "
                        f"or equal to {maximum}"
                    )
                }
            ),
            422,
        )

    return value


app = create_app()