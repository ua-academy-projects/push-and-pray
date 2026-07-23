import logging
from collections import defaultdict
from datetime import datetime, timezone

from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.exceptions import PersistenceError
from app.models import (
    AverageTemperatureMethod,
    CurrentWeather,
    DailyForecast,
    DailyWeather,
    HourlyWeather,
    Location,
    SyncStatus,
    WeatherSync,
)
from app.schemas.location import LocationIn
from app.schemas.persistence import WeatherUpsertRequest
from app.schemas.sync import SyncFailureRequest
from app.services.weather_query_service import build_latest_response

logger = logging.getLogger(__name__)


def _mean(values: list[float]) -> float | None:
    values = [v for v in values if v is not None]
    return sum(values) / len(values) if values else None


def _hourly_by_local_date(hourly_rows):
    """Groups hourly rows by the calendar date each `weather_time` carries. Hourly timestamps
    are parsed (by the Fetcher's normalizer) with the location's own configured timezone
    attached, not converted to UTC before being sent -- so `.date()` on the still-aware value
    received here already gives the correct local calendar date, with no separate lookup of
    the location's timezone needed."""
    by_date = defaultdict(list)
    for row in hourly_rows:
        by_date[row.weather_time.date()].append(row)
    return by_date


def _compute_daily_averages(row, hourly_rows_for_date: list) -> dict:
    """average_temperature and average_apparent_temperature: derived from that date's hourly
    rows when at least one exists, else a (min+max)/2 fallback -- the two fields always share
    one method, since they'd have hourly data available (or not) in lockstep. Humidity/wind/
    cloud cover have no fallback source and stay NULL without hourly data."""
    avg_temp = _mean([h.temperature for h in hourly_rows_for_date])
    avg_apparent = _mean([h.apparent_temperature for h in hourly_rows_for_date])
    if avg_temp is not None:
        method = AverageTemperatureMethod.HOURLY
    else:
        method = AverageTemperatureMethod.MIN_MAX_FALLBACK
        avg_temp = (row.temperature_min + row.temperature_max) / 2
        avg_apparent = (row.apparent_temperature_min + row.apparent_temperature_max) / 2

    return {
        "average_temperature": avg_temp,
        "average_temperature_method": method,
        "average_apparent_temperature": avg_apparent,
        "average_humidity": _mean([h.humidity for h in hourly_rows_for_date]),
        "average_wind_speed": _mean([h.wind_speed for h in hourly_rows_for_date]),
        "average_cloud_cover": _mean([h.cloud_cover for h in hourly_rows_for_date]),
    }


def _find_or_create_location(db: Session, data: LocationIn) -> Location:
    """One row per (latitude, longitude). Re-syncing refreshes name/country/timezone in place."""
    table = Location.__table__
    stmt = pg_insert(table).values(
        name=data.name,
        country=data.country,
        latitude=data.latitude,
        longitude=data.longitude,
        timezone=data.timezone,
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=[table.c.latitude, table.c.longitude],
        set_={
            "name": stmt.excluded.name,
            "country": stmt.excluded.country,
            "timezone": stmt.excluded.timezone,
            "updated_at": func.now(),
        },
    ).returning(table.c.id)
    location_id = db.execute(stmt).scalar_one()
    return db.get(Location, location_id)


def _upsert_current_weather(db: Session, location_id: int, data, source: str) -> None:
    table = CurrentWeather.__table__
    values = {
        "location_id": location_id,
        "observed_at": data.observed_at,
        "temperature": data.temperature,
        "apparent_temperature": data.apparent_temperature,
        "humidity": data.humidity,
        "precipitation": data.precipitation,
        "weather_code": data.weather_code,
        "cloud_cover": data.cloud_cover,
        "wind_speed": data.wind_speed,
        "wind_direction": data.wind_direction,
        "surface_pressure": data.surface_pressure,
        "is_day": data.is_day,
        "source": source,
        "synchronized_at": func.now(),
    }
    stmt = pg_insert(table).values(**values)
    update_cols = {k: stmt.excluded[k] for k in values if k != "location_id"}
    update_cols["updated_at"] = func.now()
    stmt = stmt.on_conflict_do_update(index_elements=[table.c.location_id], set_=update_cols)
    db.execute(stmt)


def _upsert_daily_weather(db: Session, location_id: int, rows, hourly_rows, source: str) -> int:
    if not rows:
        return 0
    table = DailyWeather.__table__
    hourly_by_date = _hourly_by_local_date(hourly_rows)
    values_list = [
        {
            "location_id": location_id,
            "weather_date": row.weather_date,
            "weather_code": row.weather_code,
            "temperature_max": row.temperature_max,
            "temperature_min": row.temperature_min,
            "apparent_temperature_max": row.apparent_temperature_max,
            "apparent_temperature_min": row.apparent_temperature_min,
            "sunrise": row.sunrise,
            "sunset": row.sunset,
            "precipitation_sum": row.precipitation_sum,
            "rain_sum": row.rain_sum,
            "snowfall_sum": row.snowfall_sum,
            "precipitation_hours": row.precipitation_hours,
            "wind_speed_max": row.wind_speed_max,
            "wind_gusts_max": row.wind_gusts_max,
            **_compute_daily_averages(row, hourly_by_date.get(row.weather_date, [])),
            "source": source,
            "synchronized_at": func.now(),
        }
        for row in rows
    ]
    stmt = pg_insert(table).values(values_list)
    update_cols = {k: stmt.excluded[k] for k in values_list[0] if k not in ("location_id", "weather_date")}
    update_cols["updated_at"] = func.now()
    stmt = stmt.on_conflict_do_update(index_elements=[table.c.location_id, table.c.weather_date], set_=update_cols)
    db.execute(stmt)
    return len(rows)


def _upsert_daily_forecast(db: Session, location_id: int, rows, source: str) -> int:
    """Unlike `_upsert_daily_weather`, this is a pure replace, not an accumulate-forever
    upsert -- a forecast for a given date is expected to be superseded by a later, more
    accurate one, and there is no guarantee about preserving older predictions."""
    if not rows:
        return 0
    table = DailyForecast.__table__
    values_list = [
        {
            "location_id": location_id,
            "weather_date": row.weather_date,
            "weather_code": row.weather_code,
            "temperature_min": row.temperature_min,
            "temperature_max": row.temperature_max,
            "apparent_temperature_min": row.apparent_temperature_min,
            "apparent_temperature_max": row.apparent_temperature_max,
            "precipitation_probability_max": row.precipitation_probability_max,
            "source": source,
            "synchronized_at": func.now(),
        }
        for row in rows
    ]
    stmt = pg_insert(table).values(values_list)
    update_cols = {k: stmt.excluded[k] for k in values_list[0] if k not in ("location_id", "weather_date")}
    update_cols["updated_at"] = func.now()
    stmt = stmt.on_conflict_do_update(index_elements=[table.c.location_id, table.c.weather_date], set_=update_cols)
    db.execute(stmt)
    return len(rows)


def _upsert_hourly_weather(db: Session, location_id: int, rows) -> int:
    if not rows:
        return 0
    table = HourlyWeather.__table__
    values_list = [
        {
            "location_id": location_id,
            "weather_time": row.weather_time,
            "temperature": row.temperature,
            "apparent_temperature": row.apparent_temperature,
            "humidity": row.humidity,
            "precipitation_probability": row.precipitation_probability,
            "precipitation": row.precipitation,
            "weather_code": row.weather_code,
            "cloud_cover": row.cloud_cover,
            "visibility": row.visibility,
            "wind_speed": row.wind_speed,
            "wind_direction": row.wind_direction,
            "synchronized_at": func.now(),
        }
        for row in rows
    ]
    stmt = pg_insert(table).values(values_list)
    update_cols = {k: stmt.excluded[k] for k in values_list[0] if k not in ("location_id", "weather_time")}
    update_cols["updated_at"] = func.now()
    stmt = stmt.on_conflict_do_update(index_elements=[table.c.location_id, table.c.weather_time], set_=update_cols)
    db.execute(stmt)
    return len(rows)


def upsert_weather(db: Session, payload: WeatherUpsertRequest):
    """The whole PUT /internal/weather operation, as one transaction: all writes succeed together or
    none of them do -- a malformed payload can never partially overwrite previously good data."""
    logger.info("persistence started: trigger_type=%s", payload.sync.trigger_type)
    try:
        location = _find_or_create_location(db, payload.location)
        logger.info("location resolved: id=%s", location.id)

        _upsert_current_weather(db, location.id, payload.current, payload.source)
        daily_count = _upsert_daily_weather(db, location.id, payload.daily, payload.hourly, payload.source)
        forecast_count = _upsert_daily_forecast(db, location.id, payload.daily_forecast, payload.source)
        hourly_count = _upsert_hourly_weather(db, location.id, payload.hourly)
        logger.info(
            "daily rows upserted: %d, forecast rows upserted: %d, hourly rows upserted: %d",
            daily_count,
            forecast_count,
            hourly_count,
        )

        sync = WeatherSync(
            location_id=location.id,
            started_at=payload.sync.started_at,
            completed_at=payload.sync.completed_at or datetime.now(timezone.utc),
            status=SyncStatus.SUCCESS,
            source=payload.source,
            trigger_type=payload.sync.trigger_type,
            open_meteo_request_url=payload.sync.open_meteo_request_url,
            open_meteo_status_code=payload.sync.open_meteo_status_code,
            open_meteo_duration_ms=payload.sync.open_meteo_duration_ms,
            records_received=1 + daily_count + forecast_count + hourly_count,
            daily_records_received=daily_count,
            forecast_records_received=forecast_count,
            hourly_records_received=hourly_count,
        )
        db.add(sync)
        db.commit()
        logger.info("transaction committed: synchronization succeeded")
    except Exception:
        db.rollback()
        logger.exception("transaction rolled back: persistence failed")
        raise PersistenceError("Failed to persist weather data") from None

    return build_latest_response(db)


def record_sync_failure(db: Session, payload: SyncFailureRequest):
    """Records a failed attempt. Never touches the weather tables -- only ever adds an audit row."""
    try:
        location = _find_or_create_location(db, payload.location)
        sync = WeatherSync(
            location_id=location.id,
            started_at=payload.started_at,
            completed_at=payload.completed_at or datetime.now(timezone.utc),
            status=SyncStatus.FAILED,
            source=payload.source,
            trigger_type=payload.trigger_type,
            open_meteo_request_url=payload.open_meteo_request_url,
            open_meteo_status_code=payload.open_meteo_status_code,
            open_meteo_duration_ms=payload.open_meteo_duration_ms,
            error_message=payload.error_message,
        )
        db.add(sync)
        db.commit()
        db.refresh(sync)
        logger.info("synchronization failure recorded: location_id=%s", location.id)
    except Exception:
        db.rollback()
        logger.exception("failed to record synchronization failure")
        raise PersistenceError("Failed to record synchronization failure") from None

    return sync
