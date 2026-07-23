from typing import Any

import httpx

from app.config import Settings
from app.exceptions import BackendServiceResponseError, BackendServiceTimeoutError, BackendServiceUnavailableError


class BackendClient:
    """The only way the Fetcher ever talks to the Backend -- always HTTP, never a direct
    import of its code or models. Used for the push half of a sync (PUT/POST) and, for the
    startup-freshness check only, one read against the Backend's public sync-status endpoint."""

    def __init__(self, settings: Settings):
        self._base_url = settings.backend_internal_base_url
        self._timeout = settings.http_timeout_seconds

    async def _request(self, method: str, path: str, **kwargs) -> httpx.Response:
        try:
            async with httpx.AsyncClient(base_url=self._base_url, timeout=self._timeout) as client:
                response = await client.request(method, path, **kwargs)
        except httpx.TimeoutException as exc:
            raise BackendServiceTimeoutError(f"Backend Service timed out on {method} {path}") from exc
        except httpx.ConnectError as exc:
            raise BackendServiceUnavailableError(f"Backend Service unreachable for {method} {path}") from exc
        except httpx.HTTPError as exc:
            raise BackendServiceUnavailableError(f"Backend Service request failed for {method} {path}: {exc}") from exc

        if response.status_code >= 400:
            raise BackendServiceResponseError(
                f"Backend Service returned {response.status_code} for {method} {path}",
                status_code=response.status_code,
            )
        return response

    async def put_weather_sync(self, payload: dict[str, Any]) -> dict[str, Any]:
        response = await self._request("PUT", "/internal/weather/sync", json=payload)
        return response.json()

    async def post_sync_failure(self, payload: dict[str, Any]) -> dict[str, Any]:
        response = await self._request("POST", "/internal/weather/sync-failure", json=payload)
        return response.json()

    async def get_sync_status(self) -> dict[str, Any]:
        response = await self._request("GET", "/api/sync-status")
        return response.json()
