"""HTTP client for History Service's application-facing API."""

import asyncio
import logging
from datetime import datetime

import httpx
from fastapi import Request
from pydantic import BaseModel, ValidationError

from ui_service.schemas import (
    ApplicationErrorResponse,
    BlacklistAnalytics,
    BlacklistPage,
    BlacklistRequestSeries,
    BlacklistStatus,
    BlacklistTurnover,
    CheckResult,
    HistoryPage,
    ReadinessResponse,
)
from ui_service.security_logging import log_sanitized_exception, redact_sensitive_text

logger = logging.getLogger(__name__)


class ApplicationClientError(Exception):
    """A readable and safe application-service failure for page rendering."""


class ApplicationClient:
    """Call only History Service's documented application API."""

    def __init__(
        self, client: httpx.AsyncClient, *, operation_timeout_seconds: float = 10.0
    ) -> None:
        self.client = client
        self.operation_timeout_seconds = operation_timeout_seconds

    async def check(
        self, *, ip_address: str, max_age_days: int, request_id: str
    ) -> CheckResult:
        response = await self._request(
            "POST",
            "/api/v1/checks",
            request_id=request_id,
            json={"ip_address": ip_address, "max_age_days": max_age_days},
        )
        result = self._validated_response(response, CheckResult, request_id=request_id)
        if str(result.request_id) != request_id:
            raise ApplicationClientError(
                "Application service returned an invalid response."
            )
        return result

    async def recent_history(self, *, request_id: str) -> HistoryPage:
        response = await self._request(
            "GET",
            "/api/v1/checks",
            request_id=request_id,
            params={"limit": 20, "offset": 0},
        )
        return self._validated_response(response, HistoryPage, request_id=request_id)

    async def history_record(self, history_id: int, *, request_id: str) -> CheckResult:
        response = await self._request(
            "GET",
            f"/api/v1/checks/{history_id}",
            request_id=request_id,
        )
        return self._validated_response(response, CheckResult, request_id=request_id)

    async def blacklist_status(self, *, request_id: str) -> BlacklistStatus:
        response = await self._request(
            "GET", "/api/v1/blacklist/status", request_id=request_id
        )
        return self._validated_response(
            response, BlacklistStatus, request_id=request_id
        )

    async def blacklist(
        self, *, limit: int, offset: int, request_id: str
    ) -> BlacklistPage:
        response = await self._request(
            "GET",
            "/api/v1/blacklist",
            request_id=request_id,
            params={"limit": limit, "offset": offset},
        )
        return self._validated_response(response, BlacklistPage, request_id=request_id)

    async def blacklist_analytics(
        self, *, pair_limit: int, request_id: str
    ) -> BlacklistAnalytics:
        response = await self._request(
            "GET",
            "/api/v1/blacklist/analytics",
            request_id=request_id,
            params={"pair_limit": pair_limit},
        )
        return self._validated_response(
            response, BlacklistAnalytics, request_id=request_id
        )

    async def blacklist_turnover(
        self,
        *,
        from_: datetime | None = None,
        to: datetime | None = None,
        period: str | None = None,
        interval: str = "auto",
        request_id: str,
    ) -> BlacklistTurnover:
        params: dict[str, int | str] = {"interval": interval}
        if from_ is not None:
            params["from"] = from_.isoformat().replace("+00:00", "Z")
        if to is not None:
            params["to"] = to.isoformat().replace("+00:00", "Z")
        if period is not None:
            params["period"] = period
        response = await self._request(
            "GET",
            "/api/v1/blacklist/analytics/turnover",
            request_id=request_id,
            params=params,
        )
        return self._validated_response(
            response, BlacklistTurnover, request_id=request_id
        )

    async def blacklist_request_series(
        self, *, limit: int, request_id: str
    ) -> BlacklistRequestSeries:
        response = await self._request(
            "GET",
            "/api/v1/blacklist/analytics/requests",
            request_id=request_id,
            params={"limit": limit},
        )
        return self._validated_response(
            response, BlacklistRequestSeries, request_id=request_id
        )

    async def ready(self, *, request_id: str) -> None:
        response = await self._request("GET", "/health/ready", request_id=request_id)
        self._validated_response(response, ReadinessResponse, request_id=request_id)

    async def _request(
        self,
        method: str,
        path: str,
        *,
        request_id: str,
        params: dict[str, int | str] | None = None,
        json: object | None = None,
    ) -> httpx.Response:
        try:
            async with asyncio.timeout(self.operation_timeout_seconds):
                return await self.client.request(
                    method,
                    path,
                    params=params,
                    json=json,
                    headers={"X-Request-ID": request_id},
                )
        except (httpx.RequestError, TimeoutError) as error:
            log_sanitized_exception(
                logger, "history_http_request_failed", error, request_id=request_id
            )
            raise ApplicationClientError(
                "Application service is unavailable. Please try again."
            ) from error

    @staticmethod
    def _validated_response[Model: BaseModel](
        response: httpx.Response,
        model: type[Model],
        *,
        request_id: str,
    ) -> Model:
        if response.headers.get("X-Request-ID") != request_id:
            raise ApplicationClientError(
                "Application service returned an invalid response."
            )
        if response.status_code >= 400:
            try:
                error = ApplicationErrorResponse.model_validate(response.json())
            except ValueError, ValidationError:
                raise ApplicationClientError(
                    "Application service returned an unexpected error."
                ) from None
            if error.error.request_id != request_id:
                raise ApplicationClientError(
                    "Application service returned an invalid response."
                )
            raise ApplicationClientError(redact_sensitive_text(error.error.message))
        try:
            return model.model_validate(response.json())
        except ValueError, ValidationError:
            raise ApplicationClientError(
                "Application service returned an invalid response."
            ) from None


async def get_application_client(request: Request) -> ApplicationClient:
    return request.app.state.application_client
