from datetime import datetime

from app.clients.history_service_client import HistoryServiceClient
from app.config import Settings, get_settings
from app.exceptions import HistoryServiceError
from app.schemas.sync import SyncStatusResponse
from app.schemas.weather import WeatherHistoryResponse, WeatherHourlyResponse, WeatherResponse
from app.services.freshness_service import compute_freshness

DATA_SOURCE = "Open-Meteo"


async def get_weather(settings: Settings | None = None) -> WeatherResponse:
    """GET /api/weather. Reads only -- never calls Open-Meteo, never triggers a sync."""
    settings = settings or get_settings()
    client = HistoryServiceClient(settings)

    try:
        data = await client.get_latest()
    except HistoryServiceError:
        # The History Service being unreachable is not the same as "no data yet" -- but from
        # the UI's point of view both look like "nothing to show, clearly marked as such".
        return WeatherResponse(is_stale=True, stale_reason="synchronization time unavailable")

    if data.get("location") is None:
        return WeatherResponse(is_stale=True, stale_reason="synchronization time unavailable")

    latest_success = data.get("latest_success_sync")
    latest_attempt = data.get("latest_attempt_sync")

    last_success_at = _parse_datetime(latest_success.get("completed_at")) if latest_success else None
    is_stale, stale_reason = compute_freshness(
        last_success_at,
        latest_attempt.get("status") if latest_attempt else None,
        settings.weather_data_max_age_minutes,
    )

    return WeatherResponse(
        location=data.get("location"),
        current=data.get("current"),
        daily=data.get("daily", []),
        hourly=data.get("hourly", []),
        data_source=DATA_SOURCE if data.get("current") else None,
        last_synchronized_at=last_success_at,
        synchronization_status=latest_attempt.get("status") if latest_attempt else None,
        is_stale=is_stale,
        stale_reason=stale_reason,
    )


async def get_history(days: int, settings: Settings | None = None) -> WeatherHistoryResponse:
    settings = settings or get_settings()
    client = HistoryServiceClient(settings)
    data = await client.get_history(days)
    return WeatherHistoryResponse(location=data.get("location"), daily=data.get("daily", []))


async def get_hourly(settings: Settings | None = None) -> WeatherHourlyResponse:
    settings = settings or get_settings()
    client = HistoryServiceClient(settings)
    data = await client.get_hourly()
    return WeatherHourlyResponse(location=data.get("location"), date=data["date"], hourly=data.get("hourly", []))


async def get_sync_status(settings: Settings | None = None) -> SyncStatusResponse:
    # Local imports -- avoids a module-import cycle (scheduler/sync_service both depend on
    # settings/clients, and this module is a natural place for the *composition* of their
    # state, not for owning any of it).
    from app.scheduler.weather_scheduler import JOB_ID, scheduler
    from app.services.weather_sync_service import is_sync_in_progress

    settings = settings or get_settings()
    client = HistoryServiceClient(settings)

    try:
        data = await client.get_latest()
    except HistoryServiceError:
        return SyncStatusResponse(
            sync_in_progress=is_sync_in_progress(),
            is_stale=True,
            stale_reason="synchronization time unavailable",
        )

    latest_success = data.get("latest_success_sync")
    latest_attempt = data.get("latest_attempt_sync")
    last_success_at = _parse_datetime(latest_success.get("completed_at")) if latest_success else None
    is_stale, stale_reason = compute_freshness(
        last_success_at,
        latest_attempt.get("status") if latest_attempt else None,
        settings.weather_data_max_age_minutes,
    )

    job = scheduler.get_job(JOB_ID) if scheduler.running else None

    return SyncStatusResponse(
        synchronization_status=latest_attempt.get("status") if latest_attempt else None,
        last_synchronized_at=last_success_at,
        last_attempted_at=_parse_datetime(latest_attempt.get("started_at")) if latest_attempt else None,
        next_scheduled_at=job.next_run_time if job else None,
        sync_in_progress=is_sync_in_progress(),
        is_stale=is_stale,
        stale_reason=stale_reason,
    )


def _parse_datetime(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value) if value else None
