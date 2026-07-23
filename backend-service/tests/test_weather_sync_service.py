import asyncio

import httpx
import pytest
import respx

from app.services import weather_sync_service
from tests.fixtures import build_open_meteo_response, make_settings

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"
HISTORY_BASE = "http://history-service.test"


@respx.mock
async def test_run_weather_sync_success_persists_normalized_payload_and_records_metadata():
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))
    put_route = respx.put(f"{HISTORY_BASE}/internal/weather").mock(
        return_value=httpx.Response(200, json={"location": {}, "current": {}, "daily": [], "hourly": []})
    )

    result = await weather_sync_service.run_weather_sync("scheduler", settings=make_settings())

    assert result.status == "success"
    assert result.trigger_type == "scheduler"
    assert result.daily_records == 11
    assert result.hourly_records == 24
    assert put_route.called

    sent_payload = put_route.calls.last.request.content
    import json

    body = json.loads(sent_payload)
    assert body["location"]["name"] == "Ivano-Frankivsk"
    assert body["sync"]["trigger_type"] == "scheduler"
    assert body["sync"]["open_meteo_status_code"] == 200
    assert body["sync"]["open_meteo_request_url"].startswith(OPEN_METEO_URL)
    assert isinstance(body["sync"]["open_meteo_duration_ms"], int)


@respx.mock
async def test_run_weather_sync_open_meteo_failure_records_failure_and_returns_failed():
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(503))
    failure_route = respx.post(f"{HISTORY_BASE}/internal/syncs/failure").mock(
        return_value=httpx.Response(201, json={"status": "failed"})
    )

    result = await weather_sync_service.run_weather_sync("scheduler", settings=make_settings())

    assert result.status == "failed"
    assert failure_route.called
    import json

    body = json.loads(failure_route.calls.last.request.content)
    assert body["open_meteo_status_code"] == 503
    assert body["trigger_type"] == "scheduler"


@respx.mock
async def test_run_weather_sync_open_meteo_timeout_records_null_status_code():
    respx.get(OPEN_METEO_URL).mock(side_effect=httpx.TimeoutException("timed out"))
    failure_route = respx.post(f"{HISTORY_BASE}/internal/syncs/failure").mock(
        return_value=httpx.Response(201, json={"status": "failed"})
    )

    result = await weather_sync_service.run_weather_sync("scheduler", settings=make_settings())

    assert result.status == "failed"
    import json

    body = json.loads(failure_route.calls.last.request.content)
    assert body["open_meteo_status_code"] is None
    assert body["open_meteo_duration_ms"] is not None


@respx.mock
async def test_run_weather_sync_history_service_unavailable_returns_failed_without_crashing():
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))
    respx.put(f"{HISTORY_BASE}/internal/weather").mock(side_effect=httpx.ConnectError("refused"))

    result = await weather_sync_service.run_weather_sync("scheduler", settings=make_settings())

    assert result.status == "failed"


@respx.mock
async def test_run_weather_sync_history_service_timeout_returns_failed():
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))
    respx.put(f"{HISTORY_BASE}/internal/weather").mock(side_effect=httpx.TimeoutException("timed out"))

    result = await weather_sync_service.run_weather_sync("scheduler", settings=make_settings())

    assert result.status == "failed"


@respx.mock
async def test_overlapping_synchronization_is_prevented():
    async def slow_response(request):
        await asyncio.sleep(0.2)
        return httpx.Response(200, json=build_open_meteo_response())

    route = respx.get(OPEN_METEO_URL).mock(side_effect=slow_response)
    respx.put(f"{HISTORY_BASE}/internal/weather").mock(
        return_value=httpx.Response(200, json={"location": {}, "current": {}, "daily": [], "hourly": []})
    )

    settings = make_settings()
    first, second = await asyncio.gather(
        weather_sync_service.run_weather_sync("scheduler", settings=settings),
        weather_sync_service.run_weather_sync("internal_endpoint", settings=settings),
    )

    statuses = {first.status, second.status}
    assert statuses == {"success", "skipped"}
    assert route.call_count == 1  # only the winner ever called Open-Meteo


async def test_is_sync_in_progress_reflects_lock_state():
    assert weather_sync_service.is_sync_in_progress() is False
