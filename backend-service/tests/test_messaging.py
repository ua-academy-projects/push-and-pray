from datetime import UTC, datetime
from decimal import Decimal

import httpx
import pytest

from app.clients import HistoryClient
from app.config import Settings
from app.models import Rate


class Publisher:
    def __init__(self, error: Exception | None = None):
        self.error = error
        self.messages = []

    async def publish(self, observation, request_id, idempotency_key):
        if self.error:
            raise self.error
        self.messages.append((observation, request_id, idempotency_key))


def rate() -> Rate:
    timestamp = datetime(2026, 7, 20, 8, 0, tzinfo=UTC)
    return Rate(
        instrument_id="crypto:bitcoin:usd",
        kind="crypto",
        base="BTC",
        quote="USD",
        name="Bitcoin",
        price=Decimal("64226.1234"),
        source="coingecko",
        source_timestamp=timestamp,
        requested_at=timestamp,
        sparkline_7d=[Decimal("1"), Decimal("2")],
    )


@pytest.mark.asyncio
async def test_history_save_publishes_without_sparkline():
    publisher = Publisher()
    async with httpx.AsyncClient() as http:
        client = HistoryClient(http, Settings(), publisher)
        status = await client.save(rate(), "request-id")

    assert status == "queued"
    observation, request_id, idempotency_key = publisher.messages[0]
    assert request_id == "request-id"
    assert "sparkline_7d" not in observation
    assert idempotency_key.startswith("coingecko:crypto:bitcoin:usd:")


@pytest.mark.asyncio
async def test_history_save_falls_back_to_http_when_publish_fails():
    publisher = Publisher(RuntimeError("broker unavailable"))

    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/internal/v1/observations"
        return httpx.Response(201, json={"created": True})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as http:
        client = HistoryClient(http, Settings(history_service_url="http://history"), publisher)
        status = await client.save(rate(), "request-id")

    assert status == "saved"
