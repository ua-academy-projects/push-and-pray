import asyncio
import logging

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.clients.fetcher_client import FetcherClient
from app.config import get_settings
from app.database.session import get_db
from app.exceptions import FetcherServiceError
from app.schemas.sync import SyncOut, SyncTriggerResult
from app.services import weather_query_service

logger = logging.getLogger(__name__)

router = APIRouter(tags=["public"])

# Scoped to this one route only -- prevents a double-click of the UI's "Refresh now" button
# from firing two proxy calls at once. Not the same lock as the Fetcher's own overlap-prevention
# lock (that one guards the actual fetch; this one guards the proxy hop in front of it).
_trigger_lock = asyncio.Lock()


def is_manual_trigger_in_progress() -> bool:
    return _trigger_lock.locked()


@router.post("/api/sync/trigger", response_model=SyncTriggerResult)
async def trigger_sync() -> SyncTriggerResult:
    """The **one deliberate exception** to "Backend never calls Fetcher" -- called only by the
    UI's manual "Refresh now" button. Proxies synchronously to the Fetcher's
    POST /internal/fetch and relays its result. Never returns Open-Meteo's raw response or a
    stack trace."""
    if _trigger_lock.locked():
        return SyncTriggerResult(status="skipped", message="A manual refresh is already in progress")

    async with _trigger_lock:
        client = FetcherClient(get_settings())
        try:
            result = await client.trigger_fetch()
        except FetcherServiceError as exc:
            logger.error("manual refresh failed: fetcher service error: %s", exc)
            return SyncTriggerResult(status="failed", message="Could not reach the Fetcher Service")

        return SyncTriggerResult(
            status=result.get("status", "failed"),
            message=result.get("message"),
            daily_records=result.get("daily_records"),
            forecast_records=result.get("forecast_records"),
            hourly_records=result.get("hourly_records"),
        )


@router.get("/api/sync/history", response_model=list[SyncOut])
def get_sync_history(limit: int = Query(20, ge=1, le=100), db: Session = Depends(get_db)) -> list[SyncOut]:
    """Recent synchronization attempts, newest first -- backs the UI's sync-history log.
    Thin read over the existing weather_syncs table/list_syncs query from Stage 1."""
    return weather_query_service.list_syncs(db, limit)
