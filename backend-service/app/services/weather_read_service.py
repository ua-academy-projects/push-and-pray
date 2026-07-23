from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.schemas.sync import SyncStatusResponse
from app.schemas.weather import WeatherHourlyResponse, WeatherResponse
from app.services import weather_query_service
from app.services.freshness_service import compute_freshness

DATA_SOURCE = "Open-Meteo"


def get_weather(db: Session, settings: Settings | None = None) -> WeatherResponse:
    """GET /api/weather. Reads PostgreSQL directly -- never calls Open-Meteo, never triggers
    a sync. Plain sync function, not async: it does blocking SQLAlchemy work with no I/O worth
    awaiting, matching how the route above it is registered (see app/api/public_weather.py)."""
    settings = settings or get_settings()
    data = weather_query_service.build_latest_response(db)

    if data.location is None:
        return WeatherResponse(is_stale=True, stale_reason="synchronization time unavailable")

    last_success_at = data.latest_success_sync.completed_at if data.latest_success_sync else None
    is_stale, stale_reason = compute_freshness(
        last_success_at,
        data.latest_attempt_sync.status if data.latest_attempt_sync else None,
        settings.weather_data_max_age_minutes,
    )

    return WeatherResponse(
        location=data.location.model_dump(),
        current=data.current.model_dump() if data.current else None,
        daily=[row.model_dump() for row in data.daily],
        hourly=[row.model_dump() for row in data.hourly],
        data_source=DATA_SOURCE if data.current else None,
        last_synchronized_at=last_success_at,
        synchronization_status=data.latest_attempt_sync.status if data.latest_attempt_sync else None,
        is_stale=is_stale,
        stale_reason=stale_reason,
    )


def get_hourly(db: Session) -> WeatherHourlyResponse:
    data = weather_query_service.get_hourly(db, None)
    return WeatherHourlyResponse(
        location=data.location.model_dump() if data.location else None,
        date=data.date,
        hourly=[row.model_dump() for row in data.hourly],
    )


def get_sync_status(db: Session, settings: Settings | None = None) -> SyncStatusResponse:
    # Local import -- avoids a module-import cycle (sync_trigger/this module both depend on
    # settings/services, and this module is a natural place for the *composition* of their
    # state, not for owning any of it).
    from app.api.sync_trigger import is_manual_trigger_in_progress

    settings = settings or get_settings()
    data = weather_query_service.build_latest_response(db)

    last_success_at = data.latest_success_sync.completed_at if data.latest_success_sync else None
    is_stale, stale_reason = compute_freshness(
        last_success_at,
        data.latest_attempt_sync.status if data.latest_attempt_sync else None,
        settings.weather_data_max_age_minutes,
    )

    return SyncStatusResponse(
        synchronization_status=data.latest_attempt_sync.status if data.latest_attempt_sync else None,
        last_synchronized_at=last_success_at,
        last_attempted_at=data.latest_attempt_sync.started_at if data.latest_attempt_sync else None,
        next_scheduled_at=None,
        sync_in_progress=is_manual_trigger_in_progress(),
        is_stale=is_stale,
        stale_reason=stale_reason,
    )
