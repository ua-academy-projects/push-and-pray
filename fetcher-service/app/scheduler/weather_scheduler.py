import logging
from datetime import datetime, timezone

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app.clients.backend_client import BackendClient
from app.config import Settings
from app.exceptions import BackendServiceError
from app.services.fetch_sync_service import run_fetch_sync

logger = logging.getLogger(__name__)

JOB_ID = "weather_fetch"

# Configuration only -- the job callback below is `run_fetch_sync` itself, imported
# unmodified from app.services.fetch_sync_service. No fetch logic lives in this module.
scheduler = AsyncIOScheduler()


def configure_scheduler(settings: Settings) -> None:
    if not settings.weather_sync_enabled:
        logger.info("scheduler disabled: WEATHER_SYNC_ENABLED=false")
        return

    scheduler.add_job(
        run_fetch_sync,
        trigger=IntervalTrigger(minutes=settings.weather_sync_interval_minutes),
        args=["scheduler"],
        id=JOB_ID,
        max_instances=1,
        coalesce=True,
        replace_existing=True,
        misfire_grace_time=60,
    )
    scheduler.start()
    logger.info("scheduler started: interval=%d minutes", settings.weather_sync_interval_minutes)


def shutdown_scheduler() -> None:
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("scheduler stopped")


async def maybe_run_startup_sync(settings: Settings) -> None:
    """Runs once at startup. Skips the initial fetch if the Backend already has recent
    successful data, so restarting the Fetcher during development doesn't force an
    unnecessary Open-Meteo call every time.

    Reads the Backend's *public* `GET /api/sync-status` for this -- a lightweight read, not
    part of the write-only internal contract (`PUT /internal/weather/sync` /
    `POST /internal/weather/sync-failure`). If the Backend can't be reached to answer this
    freshness question, that's not a reason to skip fetching -- unlike Stage 1's equivalent
    check against PostgreSQL (a Backend-internal precondition), the Backend being temporarily
    unreachable has no bearing on whether the Fetcher can still do its actual job, so this
    fails open and syncs anyway."""
    if not settings.weather_sync_enabled or not settings.weather_sync_on_startup:
        logger.info("startup fetch skipped: disabled")
        return

    client = BackendClient(settings)
    try:
        status = await client.get_sync_status()
    except BackendServiceError:
        logger.warning("startup: could not reach Backend to check freshness, fetching anyway")
        await run_fetch_sync("startup", settings=settings)
        return

    completed_at = status.get("last_synchronized_at")
    if completed_at:
        age_minutes = (datetime.now(timezone.utc) - datetime.fromisoformat(completed_at)).total_seconds() / 60
        if age_minutes < settings.weather_sync_startup_freshness_minutes:
            logger.info("startup fetch skipped: recent data exists (age=%.1f min)", age_minutes)
            return

    await run_fetch_sync("startup", settings=settings)
