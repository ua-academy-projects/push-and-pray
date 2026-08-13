import asyncio
import json

from history_service import messaging
from history_service.config import Settings


def valid_event() -> dict:
    return {
        "schema_version": 1,
        "observations": [
            {
                "instrument_code": "WTI_USD_BBL",
                "instrument_name": "WTI Crude Oil",
                "category": "crude_oil",
                "price": "68.42",
                "currency": "USD",
                "unit": "USD per barrel",
                "source": "OilPriceAPI",
                "source_series_id": "WTI_USD",
                "source_period": "2026-07-27",
                "source_observed_at": "2026-07-27T05:59:00Z",
                "scheduled_for": "2026-07-27T06:00:00Z",
                "fetched_at": "2026-07-27T06:00:02Z",
                "source_url": "https://api.oilpriceapi.com/v1/prices/latest",
                "raw_data": {"code": "WTI_USD", "price": "68.42"},
            }
        ],
    }


class FakeMessage:
    def __init__(self, body: bytes) -> None:
        self.body = body
        self.message_id = "test-message"
        self.acked = False
        self.rejected = False
        self.nacked = False
        self.requeue: bool | None = None

    async def ack(self) -> None:
        self.acked = True

    async def reject(self, requeue: bool = False) -> None:
        self.rejected = True
        self.requeue = requeue

    async def nack(self, requeue: bool = True) -> None:
        self.nacked = True
        self.requeue = requeue


def test_consumer_acknowledges_only_after_persistence(monkeypatch) -> None:
    message = FakeMessage(json.dumps(valid_event()).encode())
    monkeypatch.setattr(messaging, "_persist_event", lambda _: (1, 0))

    asyncio.run(messaging.RabbitConsumer(Settings())._handle(message))

    assert message.acked is True
    assert message.rejected is False
    assert message.nacked is False


def test_consumer_rejects_invalid_schema_without_requeue() -> None:
    payload = valid_event()
    payload["schema_version"] = 99
    message = FakeMessage(json.dumps(payload).encode())

    asyncio.run(messaging.RabbitConsumer(Settings())._handle(message))

    assert message.rejected is True
    assert message.requeue is False
    assert message.acked is False


def test_consumer_requeues_transient_persistence_failure(monkeypatch) -> None:
    message = FakeMessage(json.dumps(valid_event()).encode())

    def fail_persistence(_):
        raise RuntimeError("database is temporarily unavailable")

    monkeypatch.setattr(messaging, "_persist_event", fail_persistence)
    asyncio.run(messaging.RabbitConsumer(Settings())._handle(message))

    assert message.nacked is True
    assert message.requeue is True
    assert message.acked is False
