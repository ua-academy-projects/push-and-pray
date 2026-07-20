from typing import Any

import httpx

from app.config import Settings
from app.schemas import (
    HistoryCreatePayload,
    HistoryRecordCreated,
    HistoryRecordDetail,
    HistoryRecordList,
)


class HistoryClientError(Exception):
    """Raised when the History Service cannot complete a request."""


class HistoryClient:
    """HTTP client for the internal History Service."""

    def __init__(self, settings: Settings) -> None:
        self._base_url = settings.history_service_url.rstrip("/")
        self._timeout = settings.http_timeout_seconds

    async def save_record(
        self,
        payload: HistoryCreatePayload,
    ) -> HistoryRecordCreated:
        response_data = await self._request_json(
            "POST",
            "/history",
            json=payload.model_dump(mode="json"),
        )

        return HistoryRecordCreated.model_validate(response_data)

    async def list_records(
        self,
        *,
        limit: int,
        offset: int,
    ) -> HistoryRecordList:
        response_data = await self._request_json(
            "GET",
            "/history",
            params={
                "limit": limit,
                "offset": offset,
            },
        )

        return HistoryRecordList.model_validate(response_data)

    async def get_record(
        self,
        record_id: int,
    ) -> HistoryRecordDetail:
        response_data = await self._request_json(
            "GET",
            f"/history/{record_id}",
        )

        return HistoryRecordDetail.model_validate(response_data)

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
        *,
        params: dict[str, Any] | None = None,
        json: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        try:
            async with httpx.AsyncClient(
                timeout=self._timeout,
            ) as client:
                response = await client.request(
                    method,
                    f"{self._base_url}{path}",
                    params=params,
                    json=json,
                )

                response.raise_for_status()

        except httpx.TimeoutException as exc:
            raise HistoryClientError(
                "History Service request timed out"
            ) from exc

        except httpx.HTTPStatusError as exc:
            raise HistoryClientError(
                f"History Service returned HTTP "
                f"{exc.response.status_code}"
            ) from exc

        except httpx.RequestError as exc:
            raise HistoryClientError(
                "Could not connect to History Service"
            ) from exc

        try:
            payload = response.json()
        except ValueError as exc:
            raise HistoryClientError(
                "History Service returned invalid JSON"
            ) from exc

        if not isinstance(payload, dict):
            raise HistoryClientError(
                "History Service returned an unexpected response"
            )

        return payload