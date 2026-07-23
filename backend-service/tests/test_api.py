from datetime import datetime, timedelta, timezone

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from tests.fixtures import build_open_meteo_response

HISTORY_BASE = "http://history-service.test"
OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("HISTORY_SERVICE_BASE_URL", HISTORY_BASE)
    # Keep these API tests isolated from the scheduler/startup-sync lifespan behavior --
    # that's covered separately in test_scheduler.py.
    monkeypatch.setenv("WEATHER_SYNC_ENABLED", "false")

    from app.config import get_settings

    get_settings.cache_clear()

    from app.main import app

    with TestClient(app) as test_client:
        yield test_client

    get_settings.cache_clear()


def _sample_location():
    return {
        "name": "Ivano-Frankivsk",
        "country": "Ukraine",
        "latitude": 48.9226,
        "longitude": 24.7111,
        "timezone": "Europe/Kyiv",
    }


def _sample_daily_row(weather_date="2026-07-20"):
    return {
        "weather_date": weather_date,
        "weather_code": 1,
        "temperature_max": 25.0,
        "temperature_min": 15.0,
        "apparent_temperature_max": 26.0,
        "apparent_temperature_min": 14.0,
        "sunrise": "2026-07-20T05:00:00+03:00",
        "sunset": "2026-07-20T21:00:00+03:00",
        "precipitation_sum": 0.0,
        "rain_sum": 0.0,
        "snowfall_sum": 0.0,
        "precipitation_hours": 0.0,
        "wind_speed_max": 10.0,
        "wind_gusts_max": 15.0,
    }


def _sample_history_latest_response():
    recent = (datetime.now(timezone.utc) - timedelta(minutes=10)).isoformat()
    return {
        "location": {
            "name": "Ivano-Frankivsk",
            "country": "Ukraine",
            "latitude": 48.9226,
            "longitude": 24.7111,
            "timezone": "Europe/Kyiv",
        },
        "current": {
            "observed_at": "2026-07-20T14:00:00+03:00",
            "temperature": 24.5,
            "apparent_temperature": 25.1,
            "humidity": 61,
            "precipitation": 0.0,
            "weather_code": 1,
            "cloud_cover": 20,
            "wind_speed": 8.5,
            "wind_direction": 220,
            "surface_pressure": 1008.0,
            "is_day": True,
        },
        "daily": [],
        "hourly": [],
        "latest_success_sync": {"status": "success", "completed_at": recent},
        "latest_attempt_sync": {"status": "success", "completed_at": recent},
    }


@respx.mock
def test_get_weather_returns_persisted_data_and_never_calls_open_meteo(client):
    respx.get(f"{HISTORY_BASE}/internal/weather/latest").mock(
        return_value=httpx.Response(200, json=_sample_history_latest_response())
    )
    open_meteo_route = respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))

    response = client.get("/api/weather")

    assert response.status_code == 200
    body = response.json()
    assert body["current"]["temperature"] == 24.5
    assert body["data_source"] == "Open-Meteo"
    assert not open_meteo_route.called


@respx.mock
def test_get_weather_stale_flag_reflects_sync_age(client, monkeypatch):
    monkeypatch.setenv("WEATHER_DATA_MAX_AGE_MINUTES", "1")
    from app.config import get_settings

    get_settings.cache_clear()

    respx.get(f"{HISTORY_BASE}/internal/weather/latest").mock(
        return_value=httpx.Response(200, json=_sample_history_latest_response())
    )

    response = client.get("/api/weather")

    body = response.json()
    assert body["is_stale"] is True
    assert body["stale_reason"] == "synchronization overdue"


@respx.mock
def test_get_weather_with_no_data_returns_clear_no_data_response(client):
    respx.get(f"{HISTORY_BASE}/internal/weather/latest").mock(
        return_value=httpx.Response(200, json={"location": None, "current": None, "daily": [], "hourly": []})
    )
    open_meteo_route = respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))

    response = client.get("/api/weather")

    assert response.status_code == 200
    body = response.json()
    assert body["location"] is None
    assert body["current"] is None
    assert body["is_stale"] is True
    assert body["stale_reason"] == "synchronization time unavailable"
    assert not open_meteo_route.called


@respx.mock
def test_get_weather_history_proxies_history_service_and_never_calls_open_meteo(client):
    route = respx.get(f"{HISTORY_BASE}/internal/weather/history").mock(
        return_value=httpx.Response(200, json={"location": _sample_location(), "daily": [_sample_daily_row()]})
    )
    open_meteo_route = respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))

    response = client.get("/api/weather/history", params={"days": 5})

    assert response.status_code == 200
    assert route.calls.last.request.url.params["days"] == "5"
    assert not open_meteo_route.called


def test_get_weather_history_days_out_of_range_is_rejected(client):
    assert client.get("/api/weather/history", params={"days": 0}).status_code == 422
    assert client.get("/api/weather/history", params={"days": 999}).status_code == 422


@respx.mock
def test_get_weather_hourly_proxies_history_service(client):
    respx.get(f"{HISTORY_BASE}/internal/weather/hourly").mock(
        return_value=httpx.Response(200, json={"location": _sample_location(), "date": "2026-07-20", "hourly": []})
    )
    open_meteo_route = respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))

    response = client.get("/api/weather/hourly")

    assert response.status_code == 200
    assert response.json()["date"] == "2026-07-20"
    assert not open_meteo_route.called


@respx.mock
def test_sync_status_reports_freshness_and_scheduler_state(client):
    respx.get(f"{HISTORY_BASE}/internal/weather/latest").mock(
        return_value=httpx.Response(200, json=_sample_history_latest_response())
    )

    response = client.get("/api/sync-status")

    assert response.status_code == 200
    body = response.json()
    assert body["synchronization_status"] == "success"
    assert body["sync_in_progress"] is False
    assert body["is_stale"] is False


@respx.mock
def test_internal_sync_endpoint_actually_calls_open_meteo_and_history_service(client):
    open_meteo_route = respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))
    put_route = respx.put(f"{HISTORY_BASE}/internal/weather").mock(
        return_value=httpx.Response(200, json={"location": {}, "current": {}, "daily": [], "hourly": []})
    )

    response = client.post("/internal/weather/sync")

    assert response.status_code == 200
    assert response.json()["status"] == "success"
    assert open_meteo_route.called
    assert put_route.called
    # the internal endpoint never returns the raw Open-Meteo payload
    assert "temperature_2m" not in response.text


def test_scheduler_status_reflects_disabled_config(client):
    response = client.get("/internal/scheduler/status")

    assert response.status_code == 200
    body = response.json()
    assert body["enabled"] is False
    assert body["running"] is False


@respx.mock
def test_health_reports_history_service_reachable(client):
    respx.get(f"{HISTORY_BASE}/health").mock(return_value=httpx.Response(200, json={"status": "ok"}))

    response = client.get("/api/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["history_service_reachable"] is True


@respx.mock
def test_health_reports_history_service_unreachable_without_crashing(client):
    respx.get(f"{HISTORY_BASE}/health").mock(side_effect=httpx.ConnectError("refused"))

    response = client.get("/api/health")

    assert response.status_code == 200
    assert response.json()["history_service_reachable"] is False
