from datetime import date, datetime

from pydantic import BaseModel


class Location(BaseModel):
    name: str
    country: str
    latitude: float
    longitude: float
    timezone: str


class CurrentWeather(BaseModel):
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


class DailyWeather(BaseModel):
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


class HourlyWeather(BaseModel):
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


class NormalizedWeather(BaseModel):
    """Output of the normalization layer -- the only shape the rest of the app knows about.
    Open-Meteo's field names never appear outside app/normalization/."""

    location: Location
    current: CurrentWeather
    daily: list[DailyWeather]
    hourly: list[HourlyWeather]
    source: str = "Open-Meteo"


class WeatherResponse(BaseModel):
    """GET /api/weather. `daily[0]` is today; the rest are the previous days, newest first."""

    location: Location | None = None
    current: CurrentWeather | None = None
    daily: list[DailyWeather] = []
    hourly: list[HourlyWeather] = []
    data_source: str | None = None
    last_synchronized_at: datetime | None = None
    synchronization_status: str | None = None
    is_stale: bool = True
    stale_reason: str | None = None


class WeatherHistoryResponse(BaseModel):
    location: Location | None = None
    daily: list[DailyWeather] = []


class WeatherHourlyResponse(BaseModel):
    location: Location | None = None
    date: date
    hourly: list[HourlyWeather] = []
