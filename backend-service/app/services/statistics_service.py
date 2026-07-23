from collections import Counter
from datetime import date as date_type

from sqlalchemy.orm import Session

from app.schemas.statistics import DailyStatisticsResponse, PeriodStatisticsResponse
from app.services.weather_condition import bucket_for_code
from app.services.weather_query_service import get_current_location, get_daily_range_by_dates


def _mean(values: list[float]) -> float | None:
    values = [v for v in values if v is not None]
    return sum(values) / len(values) if values else None


def get_daily_statistics(db: Session, target_date: date_type) -> DailyStatisticsResponse | None:
    """GET /api/weather/statistics/daily/{date}. Returns None (-> 404 at the API layer) if
    there's no stored daily_weather row for that date -- distinct from an empty *period*,
    which is a valid zeroed response, not a 404, since a single day either has a record or
    it doesn't."""
    location = get_current_location(db)
    if location is None:
        return None
    rows = get_daily_range_by_dates(db, location.id, target_date, target_date)
    if not rows:
        return None
    row = rows[0]
    return DailyStatisticsResponse(
        date=row.weather_date,
        average_temperature=row.average_temperature,
        average_temperature_method=row.average_temperature_method,
        minimum_temperature=row.temperature_min,
        maximum_temperature=row.temperature_max,
        average_apparent_temperature=row.average_apparent_temperature,
        average_humidity=row.average_humidity,
        total_precipitation=row.precipitation_sum,
        average_wind_speed=row.average_wind_speed,
        maximum_wind_speed=row.wind_speed_max,
        average_cloud_cover=row.average_cloud_cover,
        dominant_weather_condition=bucket_for_code(row.weather_code),
    )


def _period_statistics(rows, period_start: date_type | None, period_end: date_type | None) -> PeriodStatisticsResponse:
    if not rows:
        return PeriodStatisticsResponse(period_start=period_start, period_end=period_end, available_days=0)

    conditions = Counter(bucket_for_code(r.weather_code) for r in rows)
    warmest = max(rows, key=lambda r: r.temperature_max)
    coldest = min(rows, key=lambda r: r.temperature_min)
    precip_total = sum(r.precipitation_sum for r in rows)

    return PeriodStatisticsResponse(
        period_start=period_start if period_start is not None else rows[0].weather_date,
        period_end=period_end if period_end is not None else rows[-1].weather_date,
        available_days=len(rows),
        average_temperature=_mean([r.average_temperature for r in rows]),
        average_daily_minimum_temperature=_mean([r.temperature_min for r in rows]),
        average_daily_maximum_temperature=_mean([r.temperature_max for r in rows]),
        lowest_temperature=min(r.temperature_min for r in rows),
        highest_temperature=max(r.temperature_max for r in rows),
        average_humidity=_mean([r.average_humidity for r in rows]),
        total_precipitation=precip_total,
        average_daily_precipitation=precip_total / len(rows),
        rainy_days=conditions.get("rain", 0),
        snowy_days=conditions.get("snow", 0),
        clear_days=conditions.get("clear", 0),
        cloudy_days=conditions.get("cloudy", 0),
        average_wind_speed=_mean([r.average_wind_speed for r in rows]),
        maximum_wind_speed=max(r.wind_speed_max for r in rows),
        warmest_day=warmest.weather_date,
        coldest_day=coldest.weather_date,
        most_common_weather_condition=conditions.most_common(1)[0][0],
    )


def get_period_statistics(db: Session, from_date: date_type, to_date: date_type) -> PeriodStatisticsResponse:
    """GET /api/weather/statistics?from=&to=. Caller (the API route) is responsible for
    rejecting from_date > to_date with a 400 before calling this -- this function only
    handles the "valid range, maybe empty" case."""
    location = get_current_location(db)
    rows = get_daily_range_by_dates(db, location.id, from_date, to_date) if location else []
    return _period_statistics(rows, from_date, to_date)


def get_all_time_statistics(db: Session) -> PeriodStatisticsResponse:
    """GET /api/weather/statistics/all -- every stored date, no bounds."""
    location = get_current_location(db)
    rows = get_daily_range_by_dates(db, location.id, None, None) if location else []
    return _period_statistics(rows, None, None)
