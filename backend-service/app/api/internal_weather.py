from fastapi import APIRouter

from app.config import get_settings
from app.schemas.sync import SchedulerStatusResponse, SyncResult
from app.scheduler.weather_scheduler import JOB_ID, scheduler
from app.services.weather_sync_service import is_sync_in_progress, run_weather_sync

router = APIRouter(prefix="/internal", tags=["internal"])


@router.post("/weather/sync", response_model=SyncResult)
async def trigger_sync() -> SyncResult:
    """Local testing / admin / future cron / K8s CronJob use. Never called by the UI.
    Skips (does not queue) if a synchronization is already in progress."""
    return await run_weather_sync("internal_endpoint")


@router.get("/scheduler/status", response_model=SchedulerStatusResponse)
async def scheduler_status() -> SchedulerStatusResponse:
    settings = get_settings()
    job = scheduler.get_job(JOB_ID) if scheduler.running else None
    return SchedulerStatusResponse(
        enabled=settings.weather_sync_enabled,
        running=scheduler.running,
        interval_minutes=settings.weather_sync_interval_minutes,
        next_run_time=job.next_run_time if job else None,
        sync_in_progress=is_sync_in_progress(),
    )
