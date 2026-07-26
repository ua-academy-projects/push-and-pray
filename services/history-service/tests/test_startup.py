from fastapi import FastAPI
from history_service.main import app


def test_application_starts_with_liveness_route() -> None:
    assert isinstance(app, FastAPI)
    assert "/health/live" in app.openapi()["paths"]


def test_obsolete_http_snapshot_ingestion_route_is_absent() -> None:
    assert "/internal/v1/blacklist/snapshots" not in app.openapi()["paths"]
