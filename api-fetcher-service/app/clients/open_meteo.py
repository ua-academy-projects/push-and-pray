from typing import Any

import httpx

from app.config import Settings
from app.exceptions import (
    ExternalServiceResponseError,
    ExternalServiceTimeoutError,
)
from app.schemas import (
    AirQualityMeasurementCreate,
    City,
)

from datetime import datetime, timezone


CURRENT_VARIABLES = (
    "european_aqi",
    "us_aqi",
    "pm2_5",
    "pm10",
    "nitrogen_dioxide",
    "ozone",
    "carbon_monoxide",
    "uv_index",
)


class OpenMeteoClient:
    """Client for the Open-Meteo Air Quality API."""

    def __init__(self, settings: Settings) -> None:
        self._url = settings.open_meteo_air_quality_url
        self._timeout = settings.http_timeout_seconds

    async def fetch_current_measurement(
        self,
        city: City,
    ) -> AirQualityMeasurementCreate:
        params = {
            "latitude": city.latitude,
            "longitude": city.longitude,
            "current": ",".join(CURRENT_VARIABLES),
            "timezone": "UTC",
        }

        payload = await self._get_json(params)

        current = payload.get("current")

        if not isinstance(current, dict):
            raise ExternalServiceResponseError(
                "Open-Meteo response does not contain current data"
            )

        observed_at_raw = current.get("time")

        if not isinstance(observed_at_raw, str) or not observed_at_raw:
            raise ExternalServiceResponseError(
                "Open-Meteo response does not contain observation time"
            )

        try:
            observed_at = datetime.fromisoformat(
                observed_at_raw.replace("Z", "+00:00")
            )

            if observed_at.tzinfo is None:
                observed_at = observed_at.replace(
                    tzinfo=timezone.utc
                )

        except ValueError as exc:
            raise ExternalServiceResponseError(
                "Open-Meteo returned an invalid observation time"
            ) from exc

        try:
            return AirQualityMeasurementCreate(
                city_code=city.code,
                observed_at=observed_at,
                european_aqi=current.get("european_aqi"),
                us_aqi=current.get("us_aqi"),
                pm2_5=current.get("pm2_5"),
                pm10=current.get("pm10"),
                nitrogen_dioxide=current.get("nitrogen_dioxide"),
                ozone=current.get("ozone"),
                carbon_monoxide=current.get("carbon_monoxide"),
                uv_index=current.get("uv_index"),
                source="open-meteo",
                source_status_code=200,
            )

        except ValueError as exc:
            raise ExternalServiceResponseError(
                "Open-Meteo returned invalid measurement values"
            ) from exc

    async def _get_json(
        self,
        params: dict[str, Any],
    ) -> dict[str, Any]:
        try:
            async with httpx.AsyncClient(
                timeout=self._timeout,
            ) as client:
                response = await client.get(
                    self._url,
                    params=params,
                )

                response.raise_for_status()

        except httpx.TimeoutException as exc:
            raise ExternalServiceTimeoutError(
                "Open-Meteo request timed out"
            ) from exc

        except httpx.HTTPStatusError as exc:
            raise ExternalServiceResponseError(
                f"Open-Meteo returned HTTP "
                f"{exc.response.status_code}"
            ) from exc

        except httpx.RequestError as exc:
            raise ExternalServiceResponseError(
                "Could not connect to Open-Meteo"
            ) from exc

        try:
            payload = response.json()
        except ValueError as exc:
            raise ExternalServiceResponseError(
                "Open-Meteo returned invalid JSON"
            ) from exc

        if not isinstance(payload, dict):
            raise ExternalServiceResponseError(
                "Open-Meteo returned an unexpected response"
            )

        return payload