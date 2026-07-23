import time
from dataclasses import dataclass
from typing import Any

import httpx

from app.config import Settings
from app.exceptions import OpenMeteoConnectionError, OpenMeteoResponseError, OpenMeteoTimeoutError

CURRENT_FIELDS = (
    "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,"
    "weather_code,cloud_cover,wind_speed_10m,wind_direction_10m,surface_pressure,is_day"
)
HOURLY_FIELDS = (
    "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation_probability,"
    "precipitation,weather_code,cloud_cover,visibility,wind_speed_10m,wind_direction_10m"
)
DAILY_FIELDS = (
    "weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,"
    "apparent_temperature_min,sunrise,sunset,precipitation_sum,rain_sum,snowfall_sum,"
    "precipitation_hours,wind_speed_10m_max,wind_gusts_10m_max"
)


@dataclass
class OpenMeteoCallResult:
    data: dict[str, Any]
    request_url: str
    status_code: int
    duration_ms: int


def _build_params(settings: Settings) -> dict[str, Any]:
    return {
        "latitude": settings.weather_latitude,
        "longitude": settings.weather_longitude,
        "timezone": settings.weather_timezone,
        "past_days": 10,
        "forecast_days": 1,
        "current": CURRENT_FIELDS,
        "hourly": HOURLY_FIELDS,
        "daily": DAILY_FIELDS,
    }


async def fetch_forecast(settings: Settings) -> OpenMeteoCallResult:
    """Calls Open-Meteo and returns the raw JSON plus call metadata (URL/status/duration) --
    the metadata is needed even on failure, so it's captured as close to the httpx call as
    possible rather than reconstructed later."""
    params = _build_params(settings)
    started = time.monotonic()
    request_url = str(httpx.Request("GET", settings.open_meteo_base_url, params=params).url)

    try:
        async with httpx.AsyncClient(timeout=settings.http_timeout_seconds) as client:
            response = await client.get(settings.open_meteo_base_url, params=params)
    except httpx.TimeoutException as exc:
        duration_ms = int((time.monotonic() - started) * 1000)
        raise OpenMeteoTimeoutError(
            "Open-Meteo request timed out", request_url=request_url, duration_ms=duration_ms
        ) from exc
    except httpx.ConnectError as exc:
        duration_ms = int((time.monotonic() - started) * 1000)
        raise OpenMeteoConnectionError(
            "Could not connect to Open-Meteo", request_url=request_url, duration_ms=duration_ms
        ) from exc
    except httpx.HTTPError as exc:
        duration_ms = int((time.monotonic() - started) * 1000)
        raise OpenMeteoConnectionError(
            f"Open-Meteo request failed: {exc}", request_url=request_url, duration_ms=duration_ms
        ) from exc

    duration_ms = int((time.monotonic() - started) * 1000)
    request_url = str(response.request.url)

    if response.status_code < 200 or response.status_code >= 300:
        raise OpenMeteoResponseError(
            f"Open-Meteo returned status {response.status_code}",
            request_url=request_url,
            status_code=response.status_code,
            duration_ms=duration_ms,
        )

    try:
        data = response.json()
    except ValueError as exc:
        raise OpenMeteoResponseError(
            "Open-Meteo response was not valid JSON",
            request_url=request_url,
            status_code=response.status_code,
            duration_ms=duration_ms,
        ) from exc

    return OpenMeteoCallResult(data=data, request_url=request_url, status_code=response.status_code, duration_ms=duration_ms)
