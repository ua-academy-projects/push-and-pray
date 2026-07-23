from datetime import date

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.database.session import get_db
from app.schemas.weather import WeatherHistoryResponse, WeatherHourlyResponse, WeatherLatestResponse, WeatherUpsertRequest
from app.services import persistence_service, weather_query_service

router = APIRouter(prefix="/internal/weather", tags=["weather"])


@router.put("", response_model=WeatherLatestResponse)
def put_weather(payload: WeatherUpsertRequest, db: Session = Depends(get_db)):
    return persistence_service.upsert_weather(db, payload)


@router.get("/latest", response_model=WeatherLatestResponse)
def get_latest(db: Session = Depends(get_db)):
    return weather_query_service.build_latest_response(db)


@router.get("/history", response_model=WeatherHistoryResponse)
def get_history(
    days: int = Query(
        weather_query_service.DEFAULT_HISTORY_DAYS,
        ge=1,
        le=weather_query_service.MAX_HISTORY_DAYS,
        description="Number of previous days to include, in addition to today.",
    ),
    db: Session = Depends(get_db),
):
    return weather_query_service.get_history(db, days)


@router.get("/hourly", response_model=WeatherHourlyResponse)
def get_hourly(
    date_: date | None = Query(None, alias="date", description="Defaults to today in Europe/Kyiv."),
    db: Session = Depends(get_db),
):
    return weather_query_service.get_hourly(db, date_)
