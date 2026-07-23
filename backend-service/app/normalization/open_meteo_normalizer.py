from datetime import datetime
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.config import Settings
from app.exceptions import OpenMeteoDataError
from app.schemas.weather import CurrentWeather, DailyWeather, HourlyWeather, Location, NormalizedWeather

REQUIRED_CURRENT_FIELDS = (
    "time",
    "temperature_2m",
    "apparent_temperature",
    "relative_humidity_2m",
    "precipitation",
    "weather_code",
    "cloud_cover",
    "wind_speed_10m",
    "wind_direction_10m",
    "surface_pressure",
    "is_day",
)
REQUIRED_HOURLY_FIELDS = (
    "time",
    "temperature_2m",
    "apparent_temperature",
    "relative_humidity_2m",
    "precipitation_probability",
    "precipitation",
    "weather_code",
    "cloud_cover",
    "visibility",
    "wind_speed_10m",
    "wind_direction_10m",
)
REQUIRED_DAILY_FIELDS = (
    "time",
    "weather_code",
    "temperature_2m_max",
    "temperature_2m_min",
    "apparent_temperature_max",
    "apparent_temperature_min",
    "sunrise",
    "sunset",
    "precipitation_sum",
    "rain_sum",
    "snowfall_sum",
    "precipitation_hours",
    "wind_speed_10m_max",
    "wind_gusts_10m_max",
)


def normalize_open_meteo_response(data: dict[str, Any], settings: Settings) -> NormalizedWeather:
    """Converts a raw Open-Meteo forecast response into the app's internal shape. This is the
    only place in the codebase that ever reads an Open-Meteo field name -- everything
    downstream (History Service payload, public API) only ever sees the normalized shape."""
    try:
        tz = ZoneInfo(settings.weather_timezone)
    except ZoneInfoNotFoundError as exc:
        raise OpenMeteoDataError(f"Unknown timezone configured: {settings.weather_timezone!r}") from exc

    current_raw = data.get("current")
    hourly_raw = data.get("hourly")
    daily_raw = data.get("daily")
    if not isinstance(current_raw, dict) or not isinstance(hourly_raw, dict) or not isinstance(daily_raw, dict):
        raise OpenMeteoDataError("Open-Meteo response is missing 'current', 'hourly', or 'daily'")

    _require_fields(current_raw, REQUIRED_CURRENT_FIELDS, "current")
    _require_fields(hourly_raw, REQUIRED_HOURLY_FIELDS, "hourly")
    _require_fields(daily_raw, REQUIRED_DAILY_FIELDS, "daily")

    hourly_length = _consistent_length(hourly_raw, REQUIRED_HOURLY_FIELDS, "hourly")
    daily_length = _consistent_length(daily_raw, REQUIRED_DAILY_FIELDS, "daily")
    if hourly_length == 0 or daily_length == 0:
        raise OpenMeteoDataError("Open-Meteo response contains empty 'hourly' or 'daily' data")

    current = _build_current(current_raw, tz)
    hourly = [_build_hourly_row(hourly_raw, i, tz) for i in range(hourly_length)]
    daily = [_build_daily_row(daily_raw, i, tz) for i in range(daily_length)]

    location = Location(
        name=settings.weather_location_name,
        country=settings.weather_country,
        latitude=settings.weather_latitude,
        longitude=settings.weather_longitude,
        timezone=settings.weather_timezone,
    )

    return NormalizedWeather(location=location, current=current, daily=daily, hourly=hourly, source="Open-Meteo")


def _require_fields(block: dict[str, Any], fields: tuple[str, ...], name: str) -> None:
    missing = [field for field in fields if field not in block]
    if missing:
        raise OpenMeteoDataError(f"Open-Meteo '{name}' block is missing fields: {missing}")


def _consistent_length(block: dict[str, Any], fields: tuple[str, ...], name: str) -> int:
    try:
        lengths = {field: len(block[field]) for field in fields}
    except TypeError as exc:
        raise OpenMeteoDataError(f"Open-Meteo '{name}' fields must be arrays") from exc
    if len(set(lengths.values())) > 1:
        raise OpenMeteoDataError(f"Open-Meteo '{name}' arrays have inconsistent lengths: {lengths}")
    return next(iter(lengths.values()))


def _parse_local_datetime(value: Any, tz: ZoneInfo) -> datetime:
    """Open-Meteo returns local civil timestamps with no UTC offset (e.g. '2026-07-20T14:00')
    when a `timezone` param is given -- they must be interpreted as being in that timezone,
    not UTC and not the server's local time."""
    if not isinstance(value, str):
        raise OpenMeteoDataError(f"Invalid timestamp from Open-Meteo: {value!r}")
    try:
        naive = datetime.strptime(value, "%Y-%m-%dT%H:%M")
    except ValueError as exc:
        raise OpenMeteoDataError(f"Invalid timestamp from Open-Meteo: {value!r}") from exc
    return naive.replace(tzinfo=tz)


def _parse_local_date(value: Any):
    if not isinstance(value, str):
        raise OpenMeteoDataError(f"Invalid date from Open-Meteo: {value!r}")
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError as exc:
        raise OpenMeteoDataError(f"Invalid date from Open-Meteo: {value!r}") from exc


def _build_current(block: dict[str, Any], tz: ZoneInfo) -> CurrentWeather:
    try:
        return CurrentWeather(
            observed_at=_parse_local_datetime(block["time"], tz),
            temperature=block["temperature_2m"],
            apparent_temperature=block["apparent_temperature"],
            humidity=block["relative_humidity_2m"],
            precipitation=block["precipitation"],
            weather_code=block["weather_code"],
            cloud_cover=block["cloud_cover"],
            wind_speed=block["wind_speed_10m"],
            wind_direction=block["wind_direction_10m"],
            surface_pressure=block["surface_pressure"],
            is_day=bool(block["is_day"]),
        )
    except OpenMeteoDataError:
        raise
    except (TypeError, ValueError) as exc:
        raise OpenMeteoDataError(f"Malformed 'current' block from Open-Meteo: {exc}") from exc


def _build_hourly_row(block: dict[str, Any], index: int, tz: ZoneInfo) -> HourlyWeather:
    try:
        return HourlyWeather(
            weather_time=_parse_local_datetime(block["time"][index], tz),
            temperature=block["temperature_2m"][index],
            apparent_temperature=block["apparent_temperature"][index],
            humidity=block["relative_humidity_2m"][index],
            precipitation_probability=block["precipitation_probability"][index],
            precipitation=block["precipitation"][index],
            weather_code=block["weather_code"][index],
            cloud_cover=block["cloud_cover"][index],
            visibility=block["visibility"][index],
            wind_speed=block["wind_speed_10m"][index],
            wind_direction=block["wind_direction_10m"][index],
        )
    except OpenMeteoDataError:
        raise
    except (TypeError, ValueError, IndexError) as exc:
        raise OpenMeteoDataError(f"Malformed hourly row at index {index}: {exc}") from exc


def _build_daily_row(block: dict[str, Any], index: int, tz: ZoneInfo) -> DailyWeather:
    try:
        return DailyWeather(
            weather_date=_parse_local_date(block["time"][index]),
            weather_code=block["weather_code"][index],
            temperature_max=block["temperature_2m_max"][index],
            temperature_min=block["temperature_2m_min"][index],
            apparent_temperature_max=block["apparent_temperature_max"][index],
            apparent_temperature_min=block["apparent_temperature_min"][index],
            sunrise=_parse_local_datetime(block["sunrise"][index], tz),
            sunset=_parse_local_datetime(block["sunset"][index], tz),
            precipitation_sum=block["precipitation_sum"][index],
            rain_sum=block["rain_sum"][index],
            snowfall_sum=block["snowfall_sum"][index],
            precipitation_hours=block["precipitation_hours"][index],
            wind_speed_max=block["wind_speed_10m_max"][index],
            wind_gusts_max=block["wind_gusts_10m_max"][index],
        )
    except OpenMeteoDataError:
        raise
    except (TypeError, ValueError, IndexError) as exc:
        raise OpenMeteoDataError(f"Malformed daily row at index {index}: {exc}") from exc
