from datetime import datetime

from pydantic import BaseModel, ConfigDict

from app.models import SyncStatus, TriggerType
from app.schemas.location import LocationIn


class SyncCallMetadata(BaseModel):
    """Metadata about the actual Backend -> Open-Meteo call for this sync attempt."""

    trigger_type: TriggerType
    started_at: datetime
    completed_at: datetime | None = None
    open_meteo_request_url: str | None = None
    open_meteo_status_code: int | None = None
    open_meteo_duration_ms: int | None = None


class SyncFailureRequest(BaseModel):
    """Body of POST /internal/syncs/failure -- recorded when the Backend never got valid data to PUT."""

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
    hourly_records_received: int | None
    error_message: str | None
    created_at: datetime
