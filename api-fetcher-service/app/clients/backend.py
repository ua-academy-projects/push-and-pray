from typing import Any

import httpx

from app.config import Settings
from app.exceptions import BackendServiceError
from app.schemas import City


class BackendClient:
    """HTTP client used only for Backend request-response operations."""

    def __init__(self, settings: Settings) -> None:
        self._base_url = settings.backend_service_url.rstrip("/")
        self._timeout = settings.http_timeout_seconds

    async def list_cities(self) -> list[City]:
        payload = await self._request_json(
            "GET",
            "/api/cities",
        )

        if not isinstance(payload, list):
            raise BackendServiceError(
                "Backend returned an invalid city list"
            )

        try:
            return [City.model_validate(item) for item in payload]
        except ValueError as exc:
            raise BackendServiceError(
                "Backend returned invalid city data"
            ) from exc

    async def is_ready(self) -> bool:
        try:
            async with httpx.AsyncClient(
                timeout=self._timeout,
            ) as client:
                response = await client.get(
                    f"{self._base_url}/health/ready"
                )

            return response.status_code == 200

        except httpx.RequestError:
            return False

    async def _request_json(
        self,
        method: str,
        path: str,
    ) -> Any:
        try:
            async with httpx.AsyncClient(
                timeout=self._timeout,
            ) as client:
                response = await client.request(
                    method,
                    f"{self._base_url}{path}",
                )

                response.raise_for_status()

        except httpx.TimeoutException as exc:
            raise BackendServiceError(
                "Backend Service request timed out"
            ) from exc

        except httpx.HTTPStatusError as exc:
            detail = self._extract_error_detail(exc.response)
            raise BackendServiceError(
                f"Backend Service returned HTTP "
                f"{exc.response.status_code}: {detail}"
            ) from exc

        except httpx.RequestError as exc:
            raise BackendServiceError(
                "Could not connect to Backend Service"
            ) from exc

        try:
            return response.json()
        except ValueError as exc:
            raise BackendServiceError(
                "Backend Service returned invalid JSON"
            ) from exc

    @staticmethod
    def _extract_error_detail(response: httpx.Response) -> str:
        try:
            payload = response.json()
        except ValueError:
            return "unknown error"

        if isinstance(payload, dict):
            detail = payload.get("detail")
            if isinstance(detail, str):
                return detail

        return "unknown error"
