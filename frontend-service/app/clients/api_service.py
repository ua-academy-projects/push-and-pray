from typing import Any

import httpx

from app.config import Settings


class ApiServiceError(Exception):
    """Raised when the API Service request fails."""

    def __init__(
        self,
        message: str,
        *,
        status_code: int = 503,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code


class ApiServiceClient:
    """HTTP client for the internal API Service."""

    def __init__(self, settings: Settings) -> None:
        self._base_url = settings.api_service_url.rstrip("/")
        self._timeout = settings.http_timeout_seconds

    def get_air_quality(self, city: str) -> dict[str, Any]:
        return self._request_json(
            "GET",
            "/api/air-quality",
            params={"city": city},
        )

    def list_history(
        self,
        *,
        limit: int,
        offset: int,
    ) -> dict[str, Any]:
        return self._request_json(
            "GET",
            "/api/history",
            params={
                "limit": limit,
                "offset": offset,
            },
        )

    def get_history_record(
        self,
        record_id: int,
    ) -> dict[str, Any]:
        return self._request_json(
            "GET",
            f"/api/history/{record_id}",
        )

    def is_ready(self) -> bool:
        try:
            with httpx.Client(timeout=self._timeout) as client:
                response = client.get(
                    f"{self._base_url}/health/ready"
                )

            return response.status_code == 200

        except httpx.RequestError:
            return False

    def _request_json(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        try:
            with httpx.Client(timeout=self._timeout) as client:
                response = client.request(
                    method,
                    f"{self._base_url}{path}",
                    params=params,
                )

        except httpx.TimeoutException as exc:
            raise ApiServiceError(
                "The API Service request timed out.",
                status_code=504,
            ) from exc

        except httpx.RequestError as exc:
            raise ApiServiceError(
                "Could not connect to the API Service.",
                status_code=503,
            ) from exc

        if not response.is_success:
            message = self._extract_error_message(response)

            raise ApiServiceError(
                message,
                status_code=response.status_code,
            )

        try:
            payload = response.json()
        except ValueError as exc:
            raise ApiServiceError(
                "The API Service returned invalid JSON.",
                status_code=502,
            ) from exc

        if not isinstance(payload, dict):
            raise ApiServiceError(
                "The API Service returned an unexpected response.",
                status_code=502,
            )

        return payload

    @staticmethod
    def _extract_error_message(
        response: httpx.Response,
    ) -> str:
        try:
            payload = response.json()
        except ValueError:
            return "The API Service request failed."

        if isinstance(payload, dict):
            detail = payload.get("detail")

            if isinstance(detail, str):
                return detail

            if isinstance(detail, list):
                return "The request contains invalid input."

        return "The API Service request failed."