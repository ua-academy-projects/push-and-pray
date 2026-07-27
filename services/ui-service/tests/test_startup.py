from fastapi import FastAPI
from ui_service.main import app


def test_application_starts_with_liveness_route() -> None:
    assert isinstance(app, FastAPI)
    assert "/health/live" in app.openapi()["paths"]


def test_theme_routes_are_documented() -> None:
    operations = app.openapi()["paths"]["/theme"]

    assert "get" in operations
    assert "post" in operations
