import httpx
import respx
from fastapi.testclient import TestClient

from tests.fixtures import build_open_meteo_response

BACKEND_BASE = "http://backend-service.test"
OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"


def _client(monkeypatch) -> TestClient:
    monkeypatch.setenv("BACKEND_INTERNAL_BASE_URL", BACKEND_BASE)
    monkeypatch.setenv("WEATHER_SYNC_ENABLED", "false")  # isolate from scheduler/startup-sync lifespan
    from app.config import get_settings

    get_settings.cache_clear()
    from app.main import app

    return TestClient(app)


@respx.mock
def test_internal_fetch_endpoint_actually_calls_open_meteo_and_pushes_to_backend(monkeypatch):
    open_meteo_route = respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))
    put_route = respx.put(f"{BACKEND_BASE}/internal/weather/sync").mock(
        return_value=httpx.Response(
            200, json={"status": "success", "daily_records": 11, "forecast_records": 10, "hourly_records": 24}
        )
    )

    with _client(monkeypatch) as client:
        response = client.post("/internal/fetch")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "success"
    assert open_meteo_route.called
    assert put_route.called
    # never leaks raw Open-Meteo field names
    assert "temperature_2m" not in response.text


def test_scheduler_status_reflects_disabled_config(monkeypatch):
    with _client(monkeypatch) as client:
        response = client.get("/internal/scheduler/status")

    assert response.status_code == 200
    body = response.json()
    assert body["enabled"] is False
    assert body["running"] is False


def test_health_reports_ok(monkeypatch):
    with _client(monkeypatch) as client:
        response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
