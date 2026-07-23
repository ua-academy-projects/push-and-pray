import asyncio
import logging
from datetime import datetime, timezone

from app.clients.history_service_client import HistoryServiceClient
from app.clients.open_meteo_client import OpenMeteoCallResult, fetch_forecast
from app.config import Settings, get_settings
from app.exceptions import HistoryServiceError, OpenMeteoError
from app.normalization.open_meteo_normalizer import normalize_open_meteo_response
from app.schemas.sync import SyncResult

logger = logging.getLogger(__name__)

# Single in-process lock shared by the scheduler, the internal endpoint, and startup --
# whichever gets here first wins; everyone else is skipped, never queued.
_sync_lock = asyncio.Lock()


def is_sync_in_progress() -> bool:
    return _sync_lock.locked()


async def run_weather_sync(trigger_type: str, settings: Settings | None = None) -> SyncResult:
    """The one function that actually performs a synchronization: overlap check -> fetch ->
    normalize -> persist -> record outcome. Called identically by the scheduler, the internal
    HTTP endpoint, and (conceptually) any future cron/Kubernetes CronJob -- none of them
    contain sync logic of their own."""
    if _sync_lock.locked():
        logger.info("synchronization skipped: overlapping execution prevented (trigger=%s)", trigger_type)
        return SyncResult(status="skipped", trigger_type=trigger_type, message="A synchronization is already in progress")

    async with _sync_lock:
        settings = settings or get_settings()
        logger.info("synchronization started: trigger=%s", trigger_type)
        started_at = datetime.now(timezone.utc)

        try:
            call_result = await fetch_forecast(settings)
            logger.info(
                "open-meteo request completed: status=%s duration_ms=%s",
                call_result.status_code,
                call_result.duration_ms,
            )
        except OpenMeteoError as exc:
            logger.warning("synchronization failed: open-meteo error: %s", exc)
            await _record_open_meteo_failure(settings, trigger_type, started_at, exc)
            return SyncResult(status="failed", trigger_type=trigger_type, message=str(exc))

        try:
            normalized = normalize_open_meteo_response(call_result.data, settings)
        except OpenMeteoError as exc:
            logger.warning("synchronization failed: normalization error: %s", exc)
            await _record_open_meteo_failure(settings, trigger_type, started_at, exc, call_result=call_result)
            return SyncResult(status="failed", trigger_type=trigger_type, message=str(exc))

        logger.info("normalization completed: daily=%d hourly=%d", len(normalized.daily), len(normalized.hourly))

        payload = normalized.model_dump(mode="json")
        payload["sync"] = {
            "trigger_type": trigger_type,
            "started_at": started_at.isoformat(),
            "completed_at": datetime.now(timezone.utc).isoformat(),
            "open_meteo_request_url": call_result.request_url,
            "open_meteo_status_code": call_result.status_code,
            "open_meteo_duration_ms": call_result.duration_ms,
        }

        client = HistoryServiceClient(settings)
        try:
            await client.put_weather(payload)
        except HistoryServiceError as exc:
            logger.error("synchronization failed: history service error: %s", exc)
            return SyncResult(status="failed", trigger_type=trigger_type, message=str(exc))

        logger.info("history service persistence completed")
        logger.info("synchronization succeeded: trigger=%s", trigger_type)
        return SyncResult(
            status="success",
            trigger_type=trigger_type,
            daily_records=len(normalized.daily),
            hourly_records=len(normalized.hourly),
        )


async def _record_open_meteo_failure(
    settings: Settings,
    trigger_type: str,
    started_at: datetime,
    exc: OpenMeteoError,
    call_result: OpenMeteoCallResult | None = None,
) -> None:
    """Best-effort: if the History Service is also unreachable, there's nowhere to record the
    failure except the local logs above -- that's expected and not itself an error."""
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

    client = HistoryServiceClient(settings)
    try:
        await client.post_sync_failure(payload)
        logger.info("synchronization failure recorded in history service")
    except HistoryServiceError:
        logger.warning("could not record synchronization failure -- history service unreachable")
