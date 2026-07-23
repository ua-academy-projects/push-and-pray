from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database.session import get_db
from app.schemas.sync import SyncFailureRequest, SyncOut
from app.services import persistence_service, weather_query_service

router = APIRouter(prefix="/internal/syncs", tags=["syncs"])


@router.post("/failure", response_model=SyncOut, status_code=201)
def post_sync_failure(payload: SyncFailureRequest, db: Session = Depends(get_db)):
    return persistence_service.record_sync_failure(db, payload)


@router.get("", response_model=list[SyncOut])
def list_syncs(limit: int = Query(20, ge=1, le=100), db: Session = Depends(get_db)):
    return weather_query_service.list_syncs(db, limit)
