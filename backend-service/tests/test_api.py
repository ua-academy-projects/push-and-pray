import asyncio
from datetime import datetime, timedelta, timezone

import httpx
import respx
from fastapi.testclient import TestClient

from app.schemas.persistence import WeatherUpsertRequest
from app.services import persistence_service
from tests.factories import build_daily, build_daily_forecast, build_hourly_day, build_upsert_payload, kyiv_today

FETCHER_BASE = "http://fetcher-service.test"


def _seed(db_session, **kwargs):
    payload = WeatherUpsertRequest(**build_upsert_payload(**kwargs))
    return persistence_service.upsert_weather(db_session, payload)


def _client(monkeypatch) -> TestClient:
    monkeypatch.setenv("FETCHER_SERVICE_BASE_URL", FETCHER_BASE)
    from app.config import get_settings

    get_settings.cache_clear()
    from app.main import app

    return TestClient(app)


def test_get_weather_returns_persisted_data(db_session, monkeypatch):
    _seed(db_session, current={"temperature": 24.5})

    with _client(monkeypatch) as client:
        response = client.get("/api/weather")

    assert response.status_code == 200
    body = response.json()
    assert body["current"]["temperature"] == 24.5
    assert body["data_source"] == "Open-Meteo"


def test_get_weather_stale_flag_reflects_sync_age(db_session, monkeypatch):
    monkeypatch.setenv("WEATHER_DATA_MAX_AGE_MINUTES", "1")
    old_sync = (datetime.now(timezone.utc) - timedelta(minutes=90)).isoformat()
    _seed(db_session, sync={"started_at": old_sync, "completed_at": old_sync})

    with _client(monkeypatch) as client:
        response = client.get("/api/weather")

    body = response.json()
    assert body["is_stale"] is True
    assert body["stale_reason"] == "synchronization overdue"


def test_get_weather_with_no_data_returns_clear_no_data_response(monkeypatch):
    with _client(monkeypatch) as client:
        response = client.get("/api/weather")

    assert response.status_code == 200
    body = response.json()
    assert body["location"] is None
    assert body["current"] is None
    assert body["is_stale"] is True
    assert body["stale_reason"] == "synchronization time unavailable"


def test_get_weather_daily_returns_persisted_rows_newest_first(db_session, monkeypatch):
    today = kyiv_today()
    for offset in range(5):
        day = today.fromordinal(today.toordinal() - offset)
        _seed(db_session, daily=[build_daily(day, temperature_max=float(20 + offset))], hourly=[])

    with _client(monkeypatch) as client:
        response = client.get("/api/weather/daily", params={"from": today.fromordinal(today.toordinal() - 4).isoformat(), "to": today.isoformat()})

    assert response.status_code == 200
    body = response.json()["daily"]
    dates = [row["weather_date"] for row in body]
    assert dates == sorted(dates, reverse=True)
    assert dates[0] == today.isoformat()
    assert body[0]["average_temperature_method"] == "min_max_fallback"  # seeded with hourly=[]


def test_get_weather_daily_with_no_range_returns_all_available_data(db_session, monkeypatch):
    """The 'All available data' acceptance criterion: omitting from/to returns every stored
    date, not capped at 10 (or any other number)."""
    today = kyiv_today()
    for offset in range(35):
        day = today.fromordinal(today.toordinal() - offset)
        _seed(db_session, daily=[build_daily(day)], hourly=[])

    with _client(monkeypatch) as client:
        response = client.get("/api/weather/daily")

    assert len(response.json()["daily"]) == 35


def test_get_weather_daily_invalid_range_is_rejected(monkeypatch):
    with _client(monkeypatch) as client:
        response = client.get("/api/weather/daily", params={"from": "2026-07-20", "to": "2026-07-01"})

    assert response.status_code == 400


def test_get_weather_daily_by_date_returns_single_row(db_session, monkeypatch):
    today = kyiv_today()
    _seed(db_session, daily=[build_daily(today, temperature_max=27.0)], hourly=[])

    with _client(monkeypatch) as client:
        response = client.get(f"/api/weather/daily/{today.isoformat()}")

    assert response.status_code == 200
    assert response.json()["temperature_max"] == 27.0


def test_get_weather_daily_by_date_missing_returns_404(monkeypatch):
    with _client(monkeypatch) as client:
        response = client.get("/api/weather/daily/2020-01-01")

    assert response.status_code == 404


def test_get_weather_hourly_returns_todays_persisted_rows(db_session, monkeypatch):
    _seed(db_session, hourly=build_hourly_day())

    with _client(monkeypatch) as client:
        response = client.get("/api/weather/hourly")

    assert response.status_code == 200
    body = response.json()
    assert body["date"] == kyiv_today().isoformat()
    assert len(body["hourly"]) == 24


def test_sync_status_reports_freshness_and_manual_trigger_state(db_session, monkeypatch):
    _seed(db_session)

    with _client(monkeypatch) as client:
        response = client.get("/api/sync-status")

    assert response.status_code == 200
    body = response.json()
    assert body["synchronization_status"] == "success"
    assert body["sync_in_progress"] is False
    assert body["is_stale"] is False
    # no scheduler of its own as of Stage 2 -- that state lives in the Fetcher now
    assert body["next_scheduled_at"] is None


@respx.mock
def test_sync_trigger_calls_fetcher_once_and_returns_summary(monkeypatch):
    fetch_route = respx.post(f"{FETCHER_BASE}/internal/fetch").mock(
        return_value=httpx.Response(
            200, json={"status": "success", "trigger_type": "internal_endpoint", "daily_records": 11, "forecast_records": 10, "hourly_records": 24}
        )
    )

    with _client(monkeypatch) as client:
        response = client.post("/api/sync/trigger")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "success"
    assert body["daily_records"] == 11
    assert body["forecast_records"] == 10
    assert fetch_route.call_count == 1


@respx.mock
def test_sync_trigger_relays_fetcher_unreachable_as_failed(monkeypatch):
    respx.post(f"{FETCHER_BASE}/internal/fetch").mock(side_effect=httpx.ConnectError("refused"))

    with _client(monkeypatch) as client:
        response = client.post("/api/sync/trigger")

    assert response.status_code == 200  # never a 500 -- a Fetcher outage is a reported failure, not a crash
    body = response.json()
    assert body["status"] == "failed"


@respx.mock
async def test_sync_trigger_second_concurrent_call_does_not_duplicate_fetch(monkeypatch):
    monkeypatch.setenv("FETCHER_SERVICE_BASE_URL", FETCHER_BASE)
    from app.api.sync_trigger import trigger_sync
    from app.config import get_settings

    get_settings.cache_clear()

    async def slow_response(request):
        await asyncio.sleep(0.2)
        return httpx.Response(
            200, json={"status": "success", "trigger_type": "internal_endpoint", "daily_records": 11, "forecast_records": 10, "hourly_records": 24}
        )

    fetch_route = respx.post(f"{FETCHER_BASE}/internal/fetch").mock(side_effect=slow_response)

    first, second = await asyncio.gather(trigger_sync(), trigger_sync())

    statuses = {first.status, second.status}
    assert statuses == {"success", "skipped"}
    assert fetch_route.call_count == 1  # only the winner ever reached the Fetcher

    get_settings.cache_clear()


def test_sync_history_returns_recent_syncs_newest_first_with_trigger_types(db_session, monkeypatch):
    _seed(db_session, sync={"trigger_type": "scheduler"})
    _seed(db_session, sync={"trigger_type": "internal_endpoint"})

    with _client(monkeypatch) as client:
        response = client.get("/api/sync/history")

    assert response.status_code == 200
    rows = response.json()
    assert len(rows) == 2
    assert [row["trigger_type"] for row in rows] == ["internal_endpoint", "scheduler"]  # newest first


def test_sync_history_respects_limit(db_session, monkeypatch):
    for _ in range(3):
        _seed(db_session)

    with _client(monkeypatch) as client:
        response = client.get("/api/sync/history", params={"limit": 2})

    assert len(response.json()) == 2


def test_weather_forecast_reads_exclusively_from_daily_forecast(db_session, monkeypatch):
    today = kyiv_today()
    future_date = today + timedelta(days=3)
    _seed(db_session, daily=[build_daily(today)], daily_forecast=[build_daily_forecast(future_date, temperature_max=21.0)], hourly=[])

    with _client(monkeypatch) as client:
        forecast_response = client.get("/api/weather/forecast")
        daily_response = client.get(f"/api/weather/daily/{future_date.isoformat()}")

    assert forecast_response.status_code == 200
    forecast_dates = [row["weather_date"] for row in forecast_response.json()["forecast"]]
    assert future_date.isoformat() in forecast_dates
    # the future date only exists in daily_forecast -- /weather/daily must not find it there
    assert daily_response.status_code == 404


def test_weather_statistics_daily_for_recorded_date(db_session, monkeypatch):
    today = kyiv_today()
    _seed(db_session, daily=[build_daily(today, weather_code=0, temperature_max=25.0, temperature_min=15.0)], hourly=[])

    with _client(monkeypatch) as client:
        response = client.get(f"/api/weather/statistics/daily/{today.isoformat()}")

    assert response.status_code == 200
    body = response.json()
    assert body["dominant_weather_condition"] == "clear"
    assert body["maximum_temperature"] == 25.0


def test_weather_statistics_daily_missing_date_is_404(monkeypatch):
    with _client(monkeypatch) as client:
        response = client.get("/api/weather/statistics/daily/2020-01-01")

    assert response.status_code == 404


def test_weather_statistics_period_uses_all_stored_dates(db_session, monkeypatch):
    today = kyiv_today()
    for offset in range(12):
        day = today - timedelta(days=offset)
        _seed(db_session, daily=[build_daily(day)], hourly=[])

    with _client(monkeypatch) as client:
        response = client.get(
            "/api/weather/statistics", params={"from": (today - timedelta(days=11)).isoformat(), "to": today.isoformat()}
        )

    assert response.status_code == 200
    assert response.json()["available_days"] == 12  # not capped at 10


def test_weather_statistics_period_invalid_range_is_400(monkeypatch):
    with _client(monkeypatch) as client:
        response = client.get("/api/weather/statistics", params={"from": "2026-07-20", "to": "2026-07-01"})

    assert response.status_code == 400


def test_weather_statistics_period_empty_range_returns_zeroed_response(monkeypatch):
    with _client(monkeypatch) as client:
        response = client.get("/api/weather/statistics", params={"from": "2020-01-01", "to": "2020-01-05"})

    assert response.status_code == 200
    body = response.json()
    assert body["available_days"] == 0
    assert body["average_temperature"] is None


def test_weather_statistics_all_time(db_session, monkeypatch):
    today = kyiv_today()
    for offset in range(20):
        day = today - timedelta(days=offset)
        _seed(db_session, daily=[build_daily(day)], hourly=[])

    with _client(monkeypatch) as client:
        response = client.get("/api/weather/statistics/all")

    assert response.status_code == 200
    assert response.json()["available_days"] == 20


def test_weather_charts_span_more_than_ten_days(db_session, monkeypatch):
    today = kyiv_today()
    for offset in range(30):
        day = today - timedelta(days=offset)
        _seed(db_session, daily=[build_daily(day)], hourly=[])

    with _client(monkeypatch) as client:
        response = client.get("/api/weather/charts")

    assert response.status_code == 200
    body = response.json()
    assert body["period"]["available_days"] == 30
    assert len(body["temperature"]) == 30
    dates = [p["date"] for p in body["temperature"]]
    assert dates == sorted(dates)  # ascending


def test_weather_charts_invalid_range_is_400(monkeypatch):
    with _client(monkeypatch) as client:
        response = client.get("/api/weather/charts", params={"from": "2026-07-20", "to": "2026-07-01"})

    assert response.status_code == 400


def test_health_reports_ok_and_database_connected(monkeypatch):
    with _client(monkeypatch) as client:
        response = client.get("/api/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["database_connected"] is True
