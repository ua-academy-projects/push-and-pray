from fastapi import APIRouter

from app.config import get_settings
from app.schemas.sync import SchedulerStatusResponse, SyncResult
from app.scheduler.weather_scheduler import JOB_ID, scheduler
from app.services.fetch_sync_service import is_sync_in_progress, run_fetch_sync

router = APIRouter(prefix="/internal", tags=["internal"])


@router.post("/fetch", response_model=SyncResult)
async def trigger_fetch() -> SyncResult:
    """Manually runs the same fetch+push cycle the scheduler uses. Called by an admin/curl
    directly, or by the Backend's POST /api/sync/trigger proxy on behalf of the UI's manual
    refresh button -- the UI itself must never call this endpoint.
    Skips (does not queue) if a fetch is already in progress."""
    return await run_fetch_sync("internal_endpoint")


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
