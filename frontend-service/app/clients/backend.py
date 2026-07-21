from typing import Any

import httpx

from app.config import Settings


class BackendServiceError(Exception):
    """Raised when a Backend Service request fails."""

    def __init__(
        self,
        message: str,
        *,
        status_code: int = 503,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code


class BackendClient:
    """HTTP client for the AirAware Backend Service."""

    def __init__(self, settings: Settings) -> None:
        self._base_url = settings.backend_service_url.rstrip("/")
        self._timeout = settings.http_timeout_seconds

    def list_cities(self) -> list[dict[str, Any]]:
        payload = self._request_json(
            "GET",
            "/api/cities",
        )

        if not isinstance(payload, list):
            raise BackendServiceError(
                "Backend Service returned an invalid city list.",
                status_code=502,
            )

        return payload

    def get_dashboard(
        self,
        *,
        city: str,
        hours: int,
    ) -> dict[str, Any]:
        payload = self._request_json(
            "GET",
            "/api/dashboard",
            params={
                "city": city,
                "hours": hours,
            },
        )

        if not isinstance(payload, dict):
            raise BackendServiceError(
                "Backend Service returned invalid dashboard data.",
                status_code=502,
            )

        return payload

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
    ) -> Any:
        try:
            with httpx.Client(timeout=self._timeout) as client:
                response = client.request(
                    method,
                    f"{self._base_url}{path}",
                    params=params,
                )

        except httpx.TimeoutException as exc:
            raise BackendServiceError(
                "The Backend Service request timed out.",
                status_code=504,
            ) from exc

        except httpx.RequestError as exc:
            raise BackendServiceError(
                "Could not connect to the Backend Service.",
                status_code=503,
            ) from exc

        if not response.is_success:
            raise BackendServiceError(
                self._extract_error_message(response),
                status_code=response.status_code,
            )

        try:
            return response.json()
        except ValueError as exc:
            raise BackendServiceError(
                "The Backend Service returned invalid JSON.",
                status_code=502,
            ) from exc

    @staticmethod
    def _extract_error_message(
        response: httpx.Response,
    ) -> str:
        try:
            payload = response.json()
        except ValueError:
            return "The Backend Service request failed."

        if isinstance(payload, dict):
            detail = payload.get("detail")

            if isinstance(detail, str):
                return detail

            if isinstance(detail, list):
                return "The request contains invalid input."

        return "The Backend Service request failed."