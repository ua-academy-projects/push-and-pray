from typing import Any

import httpx

from app.config import Settings
from app.exceptions import (
    ExternalServiceResponseError,
    ExternalServiceTimeoutError,
    LocationNotFoundError,
)
from app.schemas import AirQualityData, Location


AIR_QUALITY_VARIABLES = (
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
    """HTTP client for Open-Meteo APIs."""

    def __init__(self, settings: Settings) -> None:
        self._geocoding_url = settings.open_meteo_geocoding_url
        self._air_quality_url = settings.open_meteo_air_quality_url
        self._timeout = settings.http_timeout_seconds

    async def geocode_city(self, city: str) -> Location:
        """Resolve a city name to coordinates."""

        params = {
            "name": city,
            "count": 1,
            "language": "en",
            "format": "json",
        }

        payload = await self._get_json(
            self._geocoding_url,
            params=params,
        )

        results = payload.get("results")

        if not isinstance(results, list) or not results:
            raise LocationNotFoundError(
                f"Location '{city}' was not found"
            )

        result = results[0]

        try:
            return Location(
                name=result["name"],
                country=result.get("country"),
                admin1=result.get("admin1"),
                latitude=result["latitude"],
                longitude=result["longitude"],
                timezone=result.get("timezone"),
            )
        except (KeyError, TypeError, ValueError) as exc:
            raise ExternalServiceResponseError(
                "Open-Meteo returned invalid geocoding data"
            ) from exc

    async def get_current_air_quality(
        self,
        location: Location,
    ) -> AirQualityData:
        """Retrieve current air-quality conditions."""

        params = {
            "latitude": location.latitude,
            "longitude": location.longitude,
            "current": ",".join(AIR_QUALITY_VARIABLES),
            "timezone": "auto",
        }

        payload = await self._get_json(
            self._air_quality_url,
            params=params,
        )

        current = payload.get("current")

        if not isinstance(current, dict):
            raise ExternalServiceResponseError(
                "Open-Meteo response does not contain current air-quality data"
            )

        observed_at = current.get("time")

        if not observed_at:
            raise ExternalServiceResponseError(
                "Open-Meteo response does not contain an observation time"
            )

        return AirQualityData(
            observed_at=observed_at,
            european_aqi=current.get("european_aqi"),
            us_aqi=current.get("us_aqi"),
            pm2_5=current.get("pm2_5"),
            pm10=current.get("pm10"),
            nitrogen_dioxide=current.get("nitrogen_dioxide"),
            ozone=current.get("ozone"),
            carbon_monoxide=current.get("carbon_monoxide"),
            uv_index=current.get("uv_index"),
        )

    async def _get_json(
        self,
        url: str,
        *,
        params: dict[str, Any],
    ) -> dict[str, Any]:
        try:
            async with httpx.AsyncClient(
                timeout=self._timeout,
            ) as client:
                response = await client.get(
                    url,
                    params=params,
                )

                response.raise_for_status()

        except httpx.TimeoutException as exc:
            raise ExternalServiceTimeoutError(
                "Open-Meteo request timed out"
            ) from exc

        except httpx.HTTPStatusError as exc:
            raise ExternalServiceResponseError(
                "Open-Meteo returned an unsuccessful status"
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