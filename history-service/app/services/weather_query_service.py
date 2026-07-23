from datetime import date as date_type
from datetime import timedelta

from sqlalchemy.orm import Session

from app.models import CurrentWeather, DailyWeather, HourlyWeather, Location, SyncStatus, WeatherSync
from app.schemas.location import LocationOut
from app.schemas.sync import SyncOut
from app.schemas.weather import (
    CurrentWeatherOut,
    DailyWeatherOut,
    HourlyWeatherOut,
    WeatherHistoryResponse,
    WeatherHourlyResponse,
    WeatherLatestResponse,
)
from app.services.time_utils import kyiv_date_to_utc_range, kyiv_today

DEFAULT_HISTORY_DAYS = 10
MAX_HISTORY_DAYS = 30


def get_current_location(db: Session) -> Location | None:
    """v1 has exactly one location -- no location picker, so reads never need a location filter."""
    return db.query(Location).order_by(Location.id).first()


def _get_current(db: Session, location_id: int) -> CurrentWeather | None:
    return db.query(CurrentWeather).filter_by(location_id=location_id).one_or_none()


def _get_daily_range(db: Session, location_id: int, days: int) -> list[DailyWeather]:
    today = kyiv_today()
    start = today - timedelta(days=days)
    return (
        db.query(DailyWeather)
        .filter(
            DailyWeather.location_id == location_id,
            DailyWeather.weather_date >= start,
            DailyWeather.weather_date <= today,
        )
        .order_by(DailyWeather.weather_date.desc())
        .all()
    )


def _get_hourly_for_date(db: Session, location_id: int, day: date_type) -> list[HourlyWeather]:
    start_utc, end_utc = kyiv_date_to_utc_range(day)
    return (
        db.query(HourlyWeather)
        .filter(
            HourlyWeather.location_id == location_id,
            HourlyWeather.weather_time >= start_utc,
            HourlyWeather.weather_time < end_utc,
        )
        .order_by(HourlyWeather.weather_time.asc())
        .all()
    )


def _latest_sync(db: Session, location_id: int, status: SyncStatus | None = None) -> WeatherSync | None:
    query = db.query(WeatherSync).filter(WeatherSync.location_id == location_id)
    if status is not None:
        query = query.filter(WeatherSync.status == status)
    return query.order_by(WeatherSync.started_at.desc()).first()


def build_latest_response(db: Session) -> WeatherLatestResponse:
    location = get_current_location(db)
    if location is None:
        return WeatherLatestResponse()

    current = _get_current(db, location.id)
    daily = _get_daily_range(db, location.id, DEFAULT_HISTORY_DAYS)
    hourly = _get_hourly_for_date(db, location.id, kyiv_today())
    latest_success = _latest_sync(db, location.id, SyncStatus.SUCCESS)
    latest_attempt = _latest_sync(db, location.id)

    return WeatherLatestResponse(
        location=LocationOut.model_validate(location),
        current=CurrentWeatherOut.model_validate(current) if current else None,
        hourly=[HourlyWeatherOut.model_validate(h) for h in hourly],
        daily=[DailyWeatherOut.model_validate(d) for d in daily],
        latest_success_sync=SyncOut.model_validate(latest_success) if latest_success else None,
        latest_attempt_sync=SyncOut.model_validate(latest_attempt) if latest_attempt else None,
    )


def get_history(db: Session, days: int) -> WeatherHistoryResponse:
    location = get_current_location(db)
    if location is None:
        return WeatherHistoryResponse()

    daily = _get_daily_range(db, location.id, days)
    return WeatherHistoryResponse(
        location=LocationOut.model_validate(location),
        daily=[DailyWeatherOut.model_validate(d) for d in daily],
    )


def get_hourly(db: Session, day: date_type | None) -> WeatherHourlyResponse:
    target_date = day or kyiv_today()
    location = get_current_location(db)
    if location is None:
        return WeatherHourlyResponse(date=target_date)

    hourly = _get_hourly_for_date(db, location.id, target_date)
    return WeatherHourlyResponse(
        location=LocationOut.model_validate(location),
        date=target_date,
        hourly=[HourlyWeatherOut.model_validate(h) for h in hourly],
    )


def list_syncs(db: Session, limit: int) -> list[SyncOut]:
    location = get_current_location(db)
    if location is None:
        return []

    rows = (
        db.query(WeatherSync)
        .filter(WeatherSync.location_id == location.id)
        .order_by(WeatherSync.started_at.desc())
        .limit(limit)
        .all()
    )
    return [SyncOut.model_validate(r) for r in rows]
