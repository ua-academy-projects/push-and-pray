import asyncio
from datetime import datetime
from zoneinfo import ZoneInfo

import httpx
import respx

from app.exceptions import MessageBrokerPublishError, MessageBrokerUnavailableError
from app.services import fetch_sync_service
from tests.fixtures import build_open_meteo_response, make_settings, mock_publisher

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"
TODAY = datetime.now(ZoneInfo("Europe/Kyiv")).date().isoformat()


@respx.mock
async def test_run_fetch_sync_success_splits_observed_and_forecast_and_publishes_to_queue(monkeypatch):
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response(days=21, past_days=10)))
    sync_mock, _ = mock_publisher(monkeypatch)

    result = await fetch_sync_service.run_fetch_sync("scheduler", settings=make_settings())

    assert result.status == "success"
    assert result.trigger_type == "scheduler"
    assert result.daily_records == 11  # today + 10 past days
    assert result.forecast_records == 10
    assert result.hourly_records == 24
    assert sync_mock.await_count == 1

    body = sync_mock.await_args.args[0]
    assert len(body["daily"]) == 11
    assert len(body["daily_forecast"]) == 10
    assert all(row["weather_date"] <= TODAY for row in body["daily"])
    assert all(row["weather_date"] > TODAY for row in body["daily_forecast"])
    assert body["sync"]["trigger_type"] == "scheduler"
    assert body["sync"]["open_meteo_status_code"] == 200


@respx.mock
async def test_run_fetch_sync_open_meteo_failure_reports_failure_and_returns_failed(monkeypatch):
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(503))
    _, failure_mock = mock_publisher(monkeypatch)

    result = await fetch_sync_service.run_fetch_sync("scheduler", settings=make_settings())

    assert result.status == "failed"
    assert failure_mock.await_count == 1
    body = failure_mock.await_args.args[0]
    assert body["open_meteo_status_code"] == 503
    assert body["trigger_type"] == "scheduler"


@respx.mock
async def test_run_fetch_sync_open_meteo_timeout_records_null_status_code(monkeypatch):
    respx.get(OPEN_METEO_URL).mock(side_effect=httpx.TimeoutException("timed out"))
    _, failure_mock = mock_publisher(monkeypatch)

    result = await fetch_sync_service.run_fetch_sync("scheduler", settings=make_settings())

    assert result.status == "failed"
    body = failure_mock.await_args.args[0]
    assert body["open_meteo_status_code"] is None
    assert body["open_meteo_duration_ms"] is not None


@respx.mock
async def test_run_fetch_sync_broker_unavailable_returns_failed_without_crashing(monkeypatch):
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))
    mock_publisher(monkeypatch, fail_sync=MessageBrokerUnavailableError("could not connect to RabbitMQ"))

    result = await fetch_sync_service.run_fetch_sync("scheduler", settings=make_settings())

    assert result.status == "failed"


@respx.mock
async def test_run_fetch_sync_broker_publish_error_returns_failed(monkeypatch):
    respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))
    mock_publisher(monkeypatch, fail_sync=MessageBrokerPublishError("channel closed"))

    result = await fetch_sync_service.run_fetch_sync("scheduler", settings=make_settings())

    assert result.status == "failed"


@respx.mock
async def test_overlapping_fetch_is_prevented(monkeypatch):
    async def slow_response(request):
        await asyncio.sleep(0.2)
        return httpx.Response(200, json=build_open_meteo_response())

    route = respx.get(OPEN_METEO_URL).mock(side_effect=slow_response)
    mock_publisher(monkeypatch)

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
