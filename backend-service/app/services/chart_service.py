from datetime import date as date_type

from sqlalchemy.orm import Session

from app.schemas.chart import ChartDataResponse, ChartPeriod, HumidityPoint, PrecipitationPoint, TemperaturePoint, WindPoint
from app.services.weather_query_service import get_current_location, get_daily_range_by_dates


def get_chart_data(db: Session, from_date: date_type | None, to_date: date_type | None) -> ChartDataResponse:
    """GET /api/weather/charts?from=&to=. Ordered strictly by date ascending -- every
    metric's points share the same date sequence, so the UI can zip them by index if it
    wants to, though each point also carries its own `date` for safety.

    Caller is responsible for rejecting from_date > to_date with a 400 before calling this."""
    location = get_current_location(db)
    rows = get_daily_range_by_dates(db, location.id, from_date, to_date) if location else []

    return ChartDataResponse(
        period=ChartPeriod(**{"from": from_date, "to": to_date, "available_days": len(rows)}),
        temperature=[
            TemperaturePoint(date=r.weather_date, average=r.average_temperature, minimum=r.temperature_min, maximum=r.temperature_max)
            for r in rows
        ],
        humidity=[HumidityPoint(date=r.weather_date, average=r.average_humidity) for r in rows],
        precipitation=[PrecipitationPoint(date=r.weather_date, total=r.precipitation_sum) for r in rows],
        wind=[WindPoint(date=r.weather_date, average=r.average_wind_speed, maximum=r.wind_speed_max) for r in rows],
    )
