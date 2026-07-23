from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.models import SyncStatus, TriggerType
from app.schemas.location import LocationIn


class SyncTriggerResult(BaseModel):
    """Response of POST /api/sync/trigger -- relays the Fetcher's result, never Open-Meteo's
    raw response or a stack trace."""

    status: str  # success | failed | skipped
    message: str | None = None
    daily_records: int | None = None
    forecast_records: int | None = None
    hourly_records: int | None = None


class SyncStatusResponse(BaseModel):
    synchronization_status: str | None = None
    last_synchronized_at: datetime | None = None
    last_attempted_at: datetime | None = None
    next_scheduled_at: datetime | None = None
    # As of Stage 2, this reflects only whether a manual refresh proxied through *this*
    # Backend (POST /api/sync/trigger) is currently in flight -- not the Fetcher's own
    # scheduler state, which the Backend has no visibility into without violating "Backend
    # calls Fetcher in exactly one case." `next_scheduled_at` is therefore also no longer
    # populated (it described this Backend's own APScheduler job, which moved to the Fetcher).
    sync_in_progress: bool
    is_stale: bool
    stale_reason: str | None = None


class SyncCallMetadata(BaseModel):
    """Metadata about the actual Backend -> Open-Meteo call for this sync attempt."""

    trigger_type: TriggerType
    started_at: datetime
    completed_at: datetime | None = None
    open_meteo_request_url: str | None = None
    open_meteo_status_code: int | None = None
    open_meteo_duration_ms: int | None = None


class SyncFailureRequest(BaseModel):
    """Recorded when the Backend never got valid data to persist."""

    location: LocationIn
    trigger_type: TriggerType
    started_at: datetime
    completed_at: datetime | None = None
    error_message: str
    source: str = "Open-Meteo"
    open_meteo_request_url: str | None = None
    open_meteo_status_code: int | None = None
    open_meteo_duration_ms: int | None = None


class SyncOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    location_id: int
    started_at: datetime
    completed_at: datetime | None
    status: SyncStatus
    source: str
    trigger_type: TriggerType
    open_meteo_request_url: str | None
    open_meteo_status_code: int | None
    open_meteo_duration_ms: int | None
    records_received: int | None
    daily_records_received: int | None
    forecast_records_received: int | None
    hourly_records_received: int | None
    error_message: str | None
    created_at: datetime
