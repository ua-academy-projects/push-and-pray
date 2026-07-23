import asyncio
import logging
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from app.clients.backend_client import BackendClient
from app.clients.open_meteo_client import OpenMeteoCallResult, fetch_forecast
from app.config import Settings, get_settings
from app.exceptions import BackendServiceError, OpenMeteoError
from app.normalization.open_meteo_normalizer import normalize_open_meteo_response
from app.schemas.sync import SyncResult

logger = logging.getLogger(__name__)

# Single in-process lock shared by the scheduler, the internal endpoint, and (indirectly,
# through it) the Backend's manual-refresh proxy -- whichever gets here first wins; everyone
# else is skipped, never queued.
_sync_lock = asyncio.Lock()


def is_sync_in_progress() -> bool:
    return _sync_lock.locked()


async def run_fetch_sync(trigger_type: str, settings: Settings | None = None) -> SyncResult:
    """The one function that performs a full fetch cycle: overlap check -> fetch Open-Meteo ->
    normalize -> split observed/forecast -> push to the Backend -> record outcome. Called
    identically by the scheduler, POST /internal/fetch, and (indirectly, since the Backend
    just forwards to that same endpoint) the UI's manual refresh button."""
    if _sync_lock.locked():
        logger.info("fetch skipped: overlapping execution prevented (trigger=%s)", trigger_type)
        return SyncResult(status="skipped", trigger_type=trigger_type, message="A fetch is already in progress")

    async with _sync_lock:
        settings = settings or get_settings()
        logger.info("fetch started: trigger=%s", trigger_type)
        started_at = datetime.now(timezone.utc)

        try:
            call_result = await fetch_forecast(settings)
            logger.info(
                "open-meteo request completed: status=%s duration_ms=%s",
                call_result.status_code,
                call_result.duration_ms,
            )
        except OpenMeteoError as exc:
            logger.warning("fetch failed: open-meteo error: %s", exc)
            await _record_failure(settings, trigger_type, started_at, exc)
            return SyncResult(status="failed", trigger_type=trigger_type, message=str(exc))

        try:
            normalized = normalize_open_meteo_response(call_result.data, settings)
        except OpenMeteoError as exc:
            logger.warning("fetch failed: normalization error: %s", exc)
            await _record_failure(settings, trigger_type, started_at, exc, call_result=call_result)
            return SyncResult(status="failed", trigger_type=trigger_type, message=str(exc))

        today = _today_in(settings.weather_timezone)
        observed_daily = [row for row in normalized.daily if row.weather_date <= today]
        forecast_daily = [row for row in normalized.daily if row.weather_date > today]
        logger.info(
            "normalization completed: observed_daily=%d forecast_daily=%d hourly=%d",
            len(observed_daily),
            len(forecast_daily),
            len(normalized.hourly),
        )

        payload = {
            "location": normalized.location.model_dump(mode="json"),
            "current": normalized.current.model_dump(mode="json"),
            "daily": [row.model_dump(mode="json") for row in observed_daily],
            "daily_forecast": [row.model_dump(mode="json") for row in forecast_daily],
            "hourly": [row.model_dump(mode="json") for row in normalized.hourly],
            "source": normalized.source,
            "sync": {
                "trigger_type": trigger_type,
                "started_at": started_at.isoformat(),
                "completed_at": datetime.now(timezone.utc).isoformat(),
                "open_meteo_request_url": call_result.request_url,
                "open_meteo_status_code": call_result.status_code,
                "open_meteo_duration_ms": call_result.duration_ms,
            },
        }

        client = BackendClient(settings)
        try:
            await client.put_weather_sync(payload)
        except BackendServiceError as exc:
            logger.error("fetch failed: backend service error: %s", exc)
            return SyncResult(status="failed", trigger_type=trigger_type, message=str(exc))

        logger.info("backend persistence completed")
        logger.info("fetch succeeded: trigger=%s", trigger_type)
        return SyncResult(
            status="success",
            trigger_type=trigger_type,
            daily_records=len(observed_daily),
            forecast_records=len(forecast_daily),
            hourly_records=len(normalized.hourly),
        )


def _today_in(tz_name: str):
    return datetime.now(ZoneInfo(tz_name)).date()


async def _record_failure(
    settings: Settings,
    trigger_type: str,
    started_at: datetime,
    exc: OpenMeteoError,
    call_result: OpenMeteoCallResult | None = None,
) -> None:
    """Best-effort: if the Backend is also unreachable, there's nowhere to record the failure
    except the local logs above -- that's expected and not itself an error."""
    request_url = call_result.request_url if call_result else exc.request_url
    status_code = call_result.status_code if call_result else exc.status_code
    duration_ms = call_result.duration_ms if call_result else exc.duration_ms

    payload = {
        "location": {
            "name": settings.weather_location_name,
            "country": settings.weather_country,
            "latitude": settings.weather_latitude,
            "longitude": settings.weather_longitude,
            "timezone": settings.weather_timezone,
        },
        "trigger_type": trigger_type,
        "started_at": started_at.isoformat(),
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "error_message": str(exc),
        "open_meteo_request_url": request_url,
        "open_meteo_status_code": status_code,
        "open_meteo_duration_ms": duration_ms,
    }

    client = BackendClient(settings)
    try:
        await client.post_sync_failure(payload)
        logger.info("fetch failure recorded in backend")
    except BackendServiceError:
        logger.warning("could not record fetch failure -- backend service unreachable")
