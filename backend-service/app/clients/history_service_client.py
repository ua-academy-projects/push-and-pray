from typing import Any

import httpx

from app.config import Settings
from app.exceptions import HistoryServiceResponseError, HistoryServiceTimeoutError, HistoryServiceUnavailableError


class HistoryServiceClient:
    """The only way the Backend ever talks to the History Service -- always HTTP, never a
    direct import of its code or models."""

    def __init__(self, settings: Settings):
        self._base_url = settings.history_service_base_url
        self._timeout = settings.http_timeout_seconds

    async def _request(self, method: str, path: str, **kwargs) -> httpx.Response:
        try:
            async with httpx.AsyncClient(base_url=self._base_url, timeout=self._timeout) as client:
                response = await client.request(method, path, **kwargs)
        except httpx.TimeoutException as exc:
            raise HistoryServiceTimeoutError(f"History Service timed out on {method} {path}") from exc
        except httpx.ConnectError as exc:
            raise HistoryServiceUnavailableError(f"History Service unreachable for {method} {path}") from exc
        except httpx.HTTPError as exc:
            raise HistoryServiceUnavailableError(f"History Service request failed for {method} {path}: {exc}") from exc

        if response.status_code >= 400:
            raise HistoryServiceResponseError(
                f"History Service returned {response.status_code} for {method} {path}",
                status_code=response.status_code,
            )
        return response

    async def put_weather(self, payload: dict[str, Any]) -> dict[str, Any]:
        response = await self._request("PUT", "/internal/weather", json=payload)
        return response.json()

    async def post_sync_failure(self, payload: dict[str, Any]) -> dict[str, Any]:
        response = await self._request("POST", "/internal/syncs/failure", json=payload)
        return response.json()

    async def get_latest(self) -> dict[str, Any]:
        response = await self._request("GET", "/internal/weather/latest")
        return response.json()

    async def get_history(self, days: int) -> dict[str, Any]:
        response = await self._request("GET", "/internal/weather/history", params={"days": days})
        return response.json()

    async def get_hourly(self, date: str | None = None) -> dict[str, Any]:
        params = {"date": date} if date else None
        response = await self._request("GET", "/internal/weather/hourly", params=params)
        return response.json()

    async def get_syncs(self, limit: int = 20) -> list[dict[str, Any]]:
        response = await self._request("GET", "/internal/syncs", params={"limit": limit})
        return response.json()

    async def health(self) -> dict[str, Any]:
        response = await self._request("GET", "/health")
        return response.json()
