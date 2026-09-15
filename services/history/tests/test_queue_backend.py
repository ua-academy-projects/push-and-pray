import asyncio
import json

import pytest

from history_service import messaging
from history_service.config import Settings


def valid_event() -> dict:
    return {
        "schema_version": 1,
        "event_key": "oil-prices:2026-08-18T12:00:00Z",
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
                "source_period": "2026-08-18",
                "source_observed_at": "2026-08-18T11:59:00Z",
                "scheduled_for": "2026-08-18T12:00:00Z",
                "fetched_at": "2026-08-18T12:00:02Z",
                "source_url": "https://api.oilpriceapi.com/v1/prices/latest",
                "raw_data": {
                    "code": "WTI_USD",
                    "price": "68.42",
                },
            }
        ],
    }


def test_pgmq_is_the_default_backend() -> None:
    consumer = messaging.create_consumer(Settings())

    assert isinstance(consumer, messaging.PGMQConsumer)


def test_amqp_backend_is_selected_by_setting() -> None:
    consumer = messaging.create_consumer(Settings(queue_backend="amqp"))

    assert isinstance(consumer, messaging.AMQPConsumer)


def test_unknown_backend_is_rejected() -> None:
    with pytest.raises(ValueError):
        Settings(queue_backend="kafka")


class FakeIncomingMessage:
    def __init__(self, body: bytes, delivery_count: int | None = None) -> None:
        self.body = body
        self.message_id = "test-message"
        self.headers = {} if delivery_count is None else {"x-delivery-count": delivery_count}
        self.outcome: str | None = None

    async def ack(self) -> None:
        self.outcome = "ack"

    async def nack(self, requeue: bool) -> None:
        self.outcome = f"nack(requeue={requeue})"

    async def reject(self, requeue: bool) -> None:
        self.outcome = f"reject(requeue={requeue})"


def amqp_consumer() -> messaging.AMQPConsumer:
    return messaging.AMQPConsumer(Settings(queue_backend="amqp", amqp_retry_delay_seconds=0))


def test_amqp_consumer_acks_only_after_persistence(monkeypatch) -> None:
    persisted: list[dict] = []

    def persist(message):
        persisted.append(message)
        return messaging.ObservationEvent.model_validate(message), 1, 0

    monkeypatch.setattr(messaging, "persist_event", persist)

    message = FakeIncomingMessage(json.dumps(valid_event()).encode())

    asyncio.run(amqp_consumer()._handle_message(message))

    assert message.outcome == "ack"
    assert len(persisted) == 1


def test_amqp_consumer_dead_letters_invalid_schema(monkeypatch) -> None:
    payload = valid_event()
    payload["schema_version"] = 99

    message = FakeIncomingMessage(json.dumps(payload).encode())

    asyncio.run(amqp_consumer()._handle_message(message))

    assert message.outcome == "reject(requeue=False)"


def test_amqp_consumer_dead_letters_malformed_body() -> None:
    message = FakeIncomingMessage(b"not json at all")

    asyncio.run(amqp_consumer()._handle_message(message))

    assert message.outcome == "reject(requeue=False)"


def test_amqp_consumer_requeues_transient_failure(monkeypatch) -> None:
    def fail_persistence(message):
        raise RuntimeError("database is temporarily unavailable")

    monkeypatch.setattr(messaging, "persist_event", fail_persistence)

    message = FakeIncomingMessage(json.dumps(valid_event()).encode(), delivery_count=2)

    asyncio.run(amqp_consumer()._handle_message(message))

    assert message.outcome == "nack(requeue=True)"


def test_delivery_attempt_counts_from_one() -> None:
    assert messaging.delivery_attempt(FakeIncomingMessage(b"{}")) == 1
    assert messaging.delivery_attempt(FakeIncomingMessage(b"{}", delivery_count=3)) == 4
