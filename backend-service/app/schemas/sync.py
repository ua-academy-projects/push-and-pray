from datetime import datetime

from pydantic import BaseModel


class SyncResult(BaseModel):
    status: str  # success | failed | skipped
    trigger_type: str
    message: str | None = None
    daily_records: int | None = None
    hourly_records: int | None = None


class SchedulerStatusResponse(BaseModel):
    enabled: bool
    running: bool
    interval_minutes: int
    next_run_time: datetime | None = None
    sync_in_progress: bool


class SyncStatusResponse(BaseModel):
    synchronization_status: str | None = None
    last_synchronized_at: datetime | None = None
    last_attempted_at: datetime | None = None
    next_scheduled_at: datetime | None = None
    sync_in_progress: bool
    is_stale: bool
    stale_reason: str | None = None
