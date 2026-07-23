import logging
from datetime import datetime, timezone

from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.exceptions import PersistenceError
from app.models import CurrentWeather, DailyWeather, HourlyWeather, Location, SyncStatus, WeatherSync
from app.schemas.location import LocationIn
from app.schemas.sync import SyncFailureRequest
from app.schemas.weather import WeatherUpsertRequest
from app.services.weather_query_service import build_latest_response

logger = logging.getLogger(__name__)


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


def _upsert_daily_weather(db: Session, location_id: int, rows, source: str) -> int:
    if not rows:
        return 0
    table = DailyWeather.__table__
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
        daily_count = _upsert_daily_weather(db, location.id, payload.daily, payload.source)
        hourly_count = _upsert_hourly_weather(db, location.id, payload.hourly)
        logger.info("daily rows upserted: %d, hourly rows upserted: %d", daily_count, hourly_count)

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
            records_received=1 + daily_count + hourly_count,
            daily_records_received=daily_count,
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
