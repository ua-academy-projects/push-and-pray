from datetime import date, datetime

from pydantic import BaseModel, ConfigDict

from app.schemas.location import LocationIn, LocationOut
from app.schemas.sync import SyncCallMetadata, SyncOut


class CurrentWeatherIn(BaseModel):
    observed_at: datetime
    temperature: float
    apparent_temperature: float
    humidity: float
    precipitation: float
    weather_code: int
    cloud_cover: float
    wind_speed: float
    wind_direction: float
    surface_pressure: float
    is_day: bool


class CurrentWeatherOut(CurrentWeatherIn):
    model_config = ConfigDict(from_attributes=True)

    id: int
    location_id: int
    source: str
    synchronized_at: datetime
    created_at: datetime
    updated_at: datetime


class DailyWeatherIn(BaseModel):
    weather_date: date
    weather_code: int
    temperature_max: float
    temperature_min: float
    apparent_temperature_max: float
    apparent_temperature_min: float
    sunrise: datetime
    sunset: datetime
    precipitation_sum: float
    rain_sum: float
    snowfall_sum: float
    precipitation_hours: float
    wind_speed_max: float
    wind_gusts_max: float


class DailyWeatherOut(DailyWeatherIn):
    model_config = ConfigDict(from_attributes=True)

    id: int
    location_id: int
    average_temperature: float
    average_temperature_method: str
    average_apparent_temperature: float
    average_humidity: float | None = None
    average_wind_speed: float | None = None
    average_cloud_cover: float | None = None
    source: str
    synchronized_at: datetime
    created_at: datetime
    updated_at: datetime


class HourlyWeatherIn(BaseModel):
    weather_time: datetime
    temperature: float
    apparent_temperature: float
    humidity: float
    precipitation_probability: float | None = None
    precipitation: float
    weather_code: int
    cloud_cover: float
    visibility: float | None = None
    wind_speed: float
    wind_direction: float


class HourlyWeatherOut(HourlyWeatherIn):
    model_config = ConfigDict(from_attributes=True)

    id: int
    location_id: int
    synchronized_at: datetime
    created_at: datetime
    updated_at: datetime


class DailyForecastIn(BaseModel):
    weather_date: date
    weather_code: int
    temperature_min: float
    temperature_max: float
    apparent_temperature_min: float
    apparent_temperature_max: float
    precipitation_probability_max: float | None = None


class DailyForecastOut(DailyForecastIn):
    model_config = ConfigDict(from_attributes=True)

    id: int
    location_id: int
    source: str
    synchronized_at: datetime
    created_at: datetime
    updated_at: datetime


class WeatherUpsertRequest(BaseModel):
    """Body of a weather.sync RabbitMQ message -- one full normalized dataset from one
    successful Fetcher sync attempt. Consumed by app/broker/consumer.py on the Backend's
    worker process, not received over HTTP."""

    location: LocationIn
    current: CurrentWeatherIn
    daily: list[DailyWeatherIn]
    daily_forecast: list[DailyForecastIn] = []
    hourly: list[HourlyWeatherIn]
    source: str = "Open-Meteo"
    sync: SyncCallMetadata


class WeatherLatestResponse(BaseModel):
    location: LocationOut | None = None
    current: CurrentWeatherOut | None = None
    hourly: list[HourlyWeatherOut] = []
    daily: list[DailyWeatherOut] = []
    latest_success_sync: SyncOut | None = None
    latest_attempt_sync: SyncOut | None = None


class WeatherHistoryResponse(BaseModel):
    location: LocationOut | None = None
    daily: list[DailyWeatherOut] = []


class WeatherHourlyResponse(BaseModel):
    location: LocationOut | None = None
    date: date
    hourly: list[HourlyWeatherOut] = []


class WeatherForecastResponse(BaseModel):
    location: LocationOut | None = None
    forecast: list[DailyForecastOut] = []
