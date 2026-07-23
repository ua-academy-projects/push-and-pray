from datetime import date

from pydantic import BaseModel


class DailyStatisticsResponse(BaseModel):
    """GET /api/weather/statistics/daily/{date}."""

    date: date
    average_temperature: float
    average_temperature_method: str
    minimum_temperature: float
    maximum_temperature: float
    average_apparent_temperature: float
    average_humidity: float | None = None
    total_precipitation: float
    average_wind_speed: float | None = None
    maximum_wind_speed: float
    average_cloud_cover: float | None = None
    dominant_weather_condition: str


class PeriodStatisticsResponse(BaseModel):
    """GET /api/weather/statistics?from=&to= and GET /api/weather/statistics/all -- same
    shape; "all time" is just a period with no from/to bound. Uses every stored date in
    range, never capped at 10. An empty range (no stored dates in [from, to]) is a valid,
    non-error response with available_days=0 and every other field null/zero -- not a 404."""

    period_start: date | None = None
    period_end: date | None = None
    available_days: int
    average_temperature: float | None = None
    average_daily_minimum_temperature: float | None = None
    average_daily_maximum_temperature: float | None = None
    lowest_temperature: float | None = None
    highest_temperature: float | None = None
    average_humidity: float | None = None
    total_precipitation: float | None = None
    average_daily_precipitation: float | None = None
    rainy_days: int = 0
    snowy_days: int = 0
    clear_days: int = 0
    cloudy_days: int = 0
    average_wind_speed: float | None = None
    maximum_wind_speed: float | None = None
    warmest_day: date | None = None
    coldest_day: date | None = None
    most_common_weather_condition: str | None = None
