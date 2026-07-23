import logging
from datetime import datetime, timezone

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app.clients.history_service_client import HistoryServiceClient
from app.config import Settings
from app.exceptions import HistoryServiceError
from app.services.weather_sync_service import run_weather_sync

logger = logging.getLogger(__name__)

JOB_ID = "weather_sync"

# Configuration only -- the job callback below is `run_weather_sync` itself, imported
# unmodified from app.services.weather_sync_service. No sync logic lives in this module.
scheduler = AsyncIOScheduler()


def configure_scheduler(settings: Settings) -> None:
    if not settings.weather_sync_enabled:
        logger.info("scheduler disabled: WEATHER_SYNC_ENABLED=false")
        return

    scheduler.add_job(
        run_weather_sync,
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
    """Runs once at startup. Skips the initial sync if recent successful data already exists,
    so restarting the Backend doesn't force an unnecessary Open-Meteo call."""
    if not settings.weather_sync_enabled or not settings.weather_sync_on_startup:
        logger.info("startup synchronization skipped: disabled")
        return

    client = HistoryServiceClient(settings)
    try:
        latest = await client.get_latest()
    except HistoryServiceError:
        logger.warning("startup: could not reach History Service to check freshness, syncing anyway")
        await run_weather_sync("startup", settings=settings)
        return

    latest_success = latest.get("latest_success_sync")
    completed_at = latest_success.get("completed_at") if latest_success else None
    if completed_at:
        age_minutes = (datetime.now(timezone.utc) - datetime.fromisoformat(completed_at)).total_seconds() / 60
        if age_minutes < settings.weather_sync_startup_freshness_minutes:
            logger.info("startup synchronization skipped: recent data exists (age=%.1f min)", age_minutes)
            return

    await run_weather_sync("startup", settings=settings)
