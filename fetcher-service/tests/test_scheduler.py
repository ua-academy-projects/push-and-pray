from datetime import datetime, timedelta, timezone

import httpx
import pytest
import respx

from app.scheduler import weather_scheduler
from tests.fixtures import build_open_meteo_response, make_settings

BACKEND_BASE = "http://backend-service.test"
OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"


@pytest.fixture(autouse=True)
async def _reset_scheduler():
    # Async on purpose: AsyncIOScheduler.shutdown() needs the same event loop it was
    # started on, and pytest-asyncio gives each test its own loop that closes right after
    # the test body -- a sync fixture's teardown would run too late, against a closed loop.
    yield
    if weather_scheduler.scheduler.running:
        weather_scheduler.scheduler.shutdown(wait=False)


async def test_configure_scheduler_starts_and_schedules_job_when_enabled():
    # AsyncIOScheduler.start() requires a running event loop, hence `async def` here.
    settings = make_settings(weather_sync_enabled=True, weather_sync_interval_minutes=60)

    weather_scheduler.configure_scheduler(settings)

    assert weather_scheduler.scheduler.running
    job = weather_scheduler.scheduler.get_job(weather_scheduler.JOB_ID)
    assert job is not None
    assert job.next_run_time is not None


async def test_configure_scheduler_does_nothing_when_disabled():
    settings = make_settings(weather_sync_enabled=False)

    weather_scheduler.configure_scheduler(settings)

    assert weather_scheduler.scheduler.running is False


@respx.mock
async def test_startup_sync_skipped_when_backend_reports_recent_successful_data():
    recent = (datetime.now(timezone.utc) - timedelta(minutes=10)).isoformat()
    respx.get(f"{BACKEND_BASE}/api/sync-status").mock(
        return_value=httpx.Response(200, json={"last_synchronized_at": recent})
    )
    open_meteo_route = respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))

    settings = make_settings(weather_sync_on_startup=True, weather_sync_startup_freshness_minutes=60)
    await weather_scheduler.maybe_run_startup_sync(settings)

    assert not open_meteo_route.called


@respx.mock
async def test_startup_sync_runs_when_backend_reports_no_recent_data():
    respx.get(f"{BACKEND_BASE}/api/sync-status").mock(
        return_value=httpx.Response(200, json={"last_synchronized_at": None})
    )
    open_meteo_route = respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))
    respx.put(f"{BACKEND_BASE}/internal/weather/sync").mock(
        return_value=httpx.Response(
            200, json={"status": "success", "daily_records": 11, "forecast_records": 10, "hourly_records": 24}
        )
    )

    settings = make_settings(weather_sync_on_startup=True)
    await weather_scheduler.maybe_run_startup_sync(settings)

    assert open_meteo_route.called


@respx.mock
async def test_startup_sync_runs_anyway_when_backend_unreachable():
    """Fail-open: unlike Stage 1's equivalent check against PostgreSQL (a Backend-internal
    precondition), the Backend being unreachable has no bearing on whether the Fetcher can
    still do its own job, so a failed freshness check must not block the fetch."""
    respx.get(f"{BACKEND_BASE}/api/sync-status").mock(side_effect=httpx.ConnectError("refused"))
    open_meteo_route = respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))
    respx.put(f"{BACKEND_BASE}/internal/weather/sync").mock(
        return_value=httpx.Response(
            200, json={"status": "success", "daily_records": 11, "forecast_records": 10, "hourly_records": 24}
        )
    )

    settings = make_settings(weather_sync_on_startup=True)
    await weather_scheduler.maybe_run_startup_sync(settings)

    assert open_meteo_route.called


@respx.mock
async def test_startup_sync_skipped_entirely_when_disabled():
    open_meteo_route = respx.get(OPEN_METEO_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))

    settings = make_settings(weather_sync_on_startup=False)
    await weather_scheduler.maybe_run_startup_sync(settings)

    assert not open_meteo_route.called
