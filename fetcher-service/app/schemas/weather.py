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
    """One normalized daily row -- covers both the "observed" (past/today) and "forecast"
    (future) halves of the requested window uniformly. `fetch_sync_service` splits the list
    into two payloads by comparing `weather_date` to today in `WEATHER_TIMEZONE` before
    sending to the Backend; the normalizer itself doesn't know or care which half a row is in."""

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
    precipitation_probability_max: float | None = None
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
