from datetime import date as date_type
from datetime import timedelta

from sqlalchemy.orm import Session

from app.models import CurrentWeather, DailyForecast, DailyWeather, HourlyWeather, Location, SyncStatus, WeatherSync
from app.schemas.location import LocationOut
from app.schemas.persistence import (
    CurrentWeatherOut,
    DailyForecastOut,
    DailyWeatherOut,
    HourlyWeatherOut,
    WeatherForecastResponse,
    WeatherHistoryResponse,
    WeatherHourlyResponse,
    WeatherLatestResponse,
)
from app.schemas.sync import SyncOut
from app.services.time_utils import kyiv_date_to_utc_range, kyiv_today

DEFAULT_HISTORY_DAYS = 10


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


def get_daily_range_by_dates(
    db: Session, location_id: int, from_date: date_type | None, to_date: date_type | None
) -> list[DailyWeather]:
    """Ascending by date, no cap -- unlike `_get_daily_range` (last-N-days, newest first, used
    by the legacy `/api/weather` and `/api/weather/history`), this backs statistics/charts and
    must be able to return every stored date. `from_date`/`to_date` are both optional and
    independently unbounded -- omit both to get all stored history."""
    query = db.query(DailyWeather).filter(DailyWeather.location_id == location_id)
    if from_date is not None:
        query = query.filter(DailyWeather.weather_date >= from_date)
    if to_date is not None:
        query = query.filter(DailyWeather.weather_date <= to_date)
    return query.order_by(DailyWeather.weather_date.asc()).all()


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


def get_daily(db: Session, from_date: date_type | None, to_date: date_type | None) -> WeatherHistoryResponse:
    """GET /api/weather/daily -- replaces GET /api/weather/history from Stage 1: no artificial
    day cap, `from`/`to` instead of a `days` count, so "all available data" is directly
    expressible (omit both). Kept newest-first, matching the old history endpoint's
    convention for a record listing (as opposed to /api/weather/charts, which is
    ascending -- charts and listings have different natural reading orders)."""
    location = get_current_location(db)
    if location is None:
        return WeatherHistoryResponse()

    daily = get_daily_range_by_dates(db, location.id, from_date, to_date)
    daily.reverse()  # get_daily_range_by_dates is ascending; this endpoint reads newest-first
    return WeatherHistoryResponse(
        location=LocationOut.model_validate(location),
        daily=[DailyWeatherOut.model_validate(d) for d in daily],
    )


def get_daily_by_date(db: Session, target_date: date_type) -> DailyWeatherOut | None:
    location = get_current_location(db)
    if location is None:
        return None
    row = (
        db.query(DailyWeather)
        .filter(DailyWeather.location_id == location.id, DailyWeather.weather_date == target_date)
        .one_or_none()
    )
    return DailyWeatherOut.model_validate(row) if row else None


def get_forecast(db: Session, days: int) -> WeatherForecastResponse:
    """GET /api/weather/forecast -- reads exclusively from daily_forecast, never daily_weather.
    Ascending by date (nearest-first makes more sense for "what's coming" than newest-first)."""
    location = get_current_location(db)
    if location is None:
        return WeatherForecastResponse()

    rows = (
        db.query(DailyForecast)
        .filter(DailyForecast.location_id == location.id)
        .order_by(DailyForecast.weather_date.asc())
        .limit(days)
        .all()
    )
    return WeatherForecastResponse(
        location=LocationOut.model_validate(location),
        forecast=[DailyForecastOut.model_validate(r) for r in rows],
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
