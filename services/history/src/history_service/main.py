from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from datetime import datetime
from typing import Annotated, Literal

from fastapi import Depends, FastAPI, Query, Response, status
from sqlalchemy import text
from sqlalchemy.orm import Session

from . import models  # noqa: F401
from .config import get_settings
from .database import Base, engine, get_db
from .models import PriceObservation
from .repository import insert_batch, latest_observations, list_instruments, list_observations
from .schemas import BatchResult, InstrumentRead, ObservationBatch, ObservationRead
from .worker import PostgresEventWorker

settings = get_settings()
logging.basicConfig(
    level=settings.log_level,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI):
    Base.metadata.create_all(bind=engine)
    logger.info("database schema is ready")
    yield


app = FastAPI(
    title="Oil Price Tracker — History Service",
    version="2.0.0",
    description="Owns persistence and serves timestamped market price snapshots.",
    lifespan=lifespan,
)


@app.get("/health", tags=["operations"])
def health(db: Annotated[Session, Depends(get_db)]) -> dict[str, str]:
    db.execute(text("SELECT 1"))
    return {"status": "ok", "database": "connected"}


@app.post(
    "/v1/observations/batch",
    response_model=BatchResult,
    status_code=status.HTTP_201_CREATED,
    tags=["ingestion"],
)
def create_observation_batch(
    payload: ObservationBatch,
    response: Response,
    db: Annotated[Session, Depends(get_db)],
) -> BatchResult:
    inserted, duplicates = insert_batch(db, payload.observations)
    if inserted == 0:
        response.status_code = status.HTTP_200_OK
    return BatchResult(inserted=inserted, duplicates=duplicates)


@app.get("/v1/observations", response_model=list[ObservationRead], tags=["history"])
def get_observations(
    db: Annotated[Session, Depends(get_db)],
    instrument: str | None = None,
    category: Literal["crude_oil", "gasoline"] | None = None,
    date_from: datetime | None = None,
    date_to: datetime | None = None,
    limit: Annotated[int, Query(ge=1, le=5000)] = 1000,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> list[PriceObservation]:
    return list_observations(db, instrument, category, date_from, date_to, limit, offset)


@app.get("/v1/observations/latest", response_model=list[ObservationRead], tags=["history"])
def get_latest(db: Annotated[Session, Depends(get_db)]) -> list[PriceObservation]:
    return latest_observations(db)


@app.get("/v1/instruments", response_model=list[InstrumentRead], tags=["history"])
def get_instruments(db: Annotated[Session, Depends(get_db)]) -> list[dict[str, str]]:
    return list_instruments(db)
