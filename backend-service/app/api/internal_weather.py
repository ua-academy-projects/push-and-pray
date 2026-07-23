from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.database.session import get_db
from app.schemas.persistence import PersistResult, WeatherUpsertRequest
from app.schemas.sync import SyncFailureRequest, SyncOut
from app.services import persistence_service

router = APIRouter(prefix="/internal/weather", tags=["internal"])


@router.put("/sync", response_model=PersistResult)
def put_weather_sync(payload: WeatherUpsertRequest, db: Session = Depends(get_db)) -> PersistResult:
    """The Fetcher-to-Backend internal contract (Stage 2 of the refactor). Called only by
    fetcher-service after a successful fetch+normalize cycle -- never by the UI. Persists in
    one transaction via persistence_service (unchanged from Stage 1); returns a lightweight
    ack, not the full persisted representation, since the Fetcher never reads weather data
    back."""
    persistence_service.upsert_weather(db, payload)
    return PersistResult(
        daily_records=len(payload.daily),
        forecast_records=len(payload.daily_forecast),
        hourly_records=len(payload.hourly),
    )


@router.post("/sync-failure", response_model=SyncOut, status_code=201)
def post_sync_failure(payload: SyncFailureRequest, db: Session = Depends(get_db)) -> SyncOut:
    """Recorded by the Fetcher when it couldn't get valid data to PUT -- an Open-Meteo failure
    or a normalization error. Never touches the weather tables, only adds an audit row."""
    return persistence_service.record_sync_failure(db, payload)
