import asyncio
import json
from datetime import datetime
from zoneinfo import ZoneInfo

import httpx
import respx

from app.services import fetch_sync_service
from tests.fixtures import build_open_meteo_response, make_settings

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"
BACKEND_BASE = "http://backend-service.test"
TODAY = datetime.now(ZoneInfo("Europe/Kyiv")).date().isoformat()


@respx.mock
async def test_run_fetch_sync_success_splits_observed_and_forecast_and_pushes_to_backend():
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response(days=21, past_days=10)))
    put_route = respx.put(f"{BACKEND_BASE}/internal/weather/sync").mock(
        return_value=httpx.Response(
            200, json={"status": "success", "daily_records": 11, "forecast_records": 10, "hourly_records": 24}
        )
    )

    result = await fetch_sync_service.run_fetch_sync("scheduler", settings=make_settings())

    assert result.status == "success"
    assert result.trigger_type == "scheduler"
    assert result.daily_records == 11  # today + 10 past days
    assert result.forecast_records == 10
    assert result.hourly_records == 24
    assert put_route.called

    body = json.loads(put_route.calls.last.request.content)
    assert len(body["daily"]) == 11
    assert len(body["daily_forecast"]) == 10
    assert all(row["weather_date"] <= TODAY for row in body["daily"])
    assert all(row["weather_date"] > TODAY for row in body["daily_forecast"])
    assert body["sync"]["trigger_type"] == "scheduler"
    assert body["sync"]["open_meteo_status_code"] == 200


@respx.mock
async def test_run_fetch_sync_open_meteo_failure_reports_failure_and_returns_failed():
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(503))
    failure_route = respx.post(f"{BACKEND_BASE}/internal/weather/sync-failure").mock(
        return_value=httpx.Response(201, json={"status": "failed"})
    )

    result = await fetch_sync_service.run_fetch_sync("scheduler", settings=make_settings())

    assert result.status == "failed"
    assert failure_route.called
    body = json.loads(failure_route.calls.last.request.content)
    assert body["open_meteo_status_code"] == 503
    assert body["trigger_type"] == "scheduler"


@respx.mock
async def test_run_fetch_sync_open_meteo_timeout_records_null_status_code():
    respx.get(OPEN_METEO_URL).mock(side_effect=httpx.TimeoutException("timed out"))
    failure_route = respx.post(f"{BACKEND_BASE}/internal/weather/sync-failure").mock(
        return_value=httpx.Response(201, json={"status": "failed"})
    )

    result = await fetch_sync_service.run_fetch_sync("scheduler", settings=make_settings())

    assert result.status == "failed"
    body = json.loads(failure_route.calls.last.request.content)
    assert body["open_meteo_status_code"] is None
    assert body["open_meteo_duration_ms"] is not None


@respx.mock
async def test_run_fetch_sync_backend_unavailable_returns_failed_without_crashing():
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))
    respx.put(f"{BACKEND_BASE}/internal/weather/sync").mock(side_effect=httpx.ConnectError("refused"))

    result = await fetch_sync_service.run_fetch_sync("scheduler", settings=make_settings())

    assert result.status == "failed"


@respx.mock
async def test_run_fetch_sync_backend_timeout_returns_failed():
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))
    respx.put(f"{BACKEND_BASE}/internal/weather/sync").mock(side_effect=httpx.TimeoutException("timed out"))

    result = await fetch_sync_service.run_fetch_sync("scheduler", settings=make_settings())

    assert result.status == "failed"


@respx.mock
async def test_overlapping_fetch_is_prevented():
    async def slow_response(request):
        await asyncio.sleep(0.2)
        return httpx.Response(200, json=build_open_meteo_response())

    route = respx.get(OPEN_METEO_URL).mock(side_effect=slow_response)
    respx.put(f"{BACKEND_BASE}/internal/weather/sync").mock(
        return_value=httpx.Response(
            200, json={"status": "success", "daily_records": 11, "forecast_records": 10, "hourly_records": 24}
        )
    )

    settings = make_settings()
    first, second = await asyncio.gather(
        fetch_sync_service.run_fetch_sync("scheduler", settings=settings),
        fetch_sync_service.run_fetch_sync("internal_endpoint", settings=settings),
    )

    statuses = {first.status, second.status}
    assert statuses == {"success", "skipped"}
    assert route.call_count == 1  # only the winner ever called Open-Meteo


async def test_is_sync_in_progress_reflects_lock_state():
    assert fetch_sync_service.is_sync_in_progress() is False
