from typing import Any

import httpx

from app.config import Settings
from app.exceptions import FetcherServiceResponseError, FetcherServiceTimeoutError, FetcherServiceUnavailableError


class FetcherClient:
    """The Backend's *only* permitted call to the Fetcher Service -- used exclusively by
    POST /api/sync/trigger, proxying a UI-initiated manual refresh. No other code path in the
    Backend may use this client (see docs/architecture.md §4)."""

    def __init__(self, settings: Settings):
        self._base_url = settings.fetcher_service_base_url
        self._timeout = settings.http_timeout_seconds

    async def trigger_fetch(self) -> dict[str, Any]:
        try:
            async with httpx.AsyncClient(base_url=self._base_url, timeout=self._timeout) as client:
                response = await client.post("/internal/fetch")
        except httpx.TimeoutException as exc:
            raise FetcherServiceTimeoutError("Fetcher Service timed out on POST /internal/fetch") from exc
        except httpx.ConnectError as exc:
            raise FetcherServiceUnavailableError("Fetcher Service unreachable for POST /internal/fetch") from exc
        except httpx.HTTPError as exc:
            raise FetcherServiceUnavailableError(f"Fetcher Service request failed: {exc}") from exc

        if response.status_code >= 400:
            raise FetcherServiceResponseError(
                f"Fetcher Service returned {response.status_code} for POST /internal/fetch",
                status_code=response.status_code,
            )
        return response.json()
