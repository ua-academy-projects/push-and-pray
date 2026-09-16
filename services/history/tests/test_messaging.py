import asyncio
import json

from history_service import messaging
from history_service.config import Settings


def valid_event() -> dict:
    return {
        "schema_version": 1,
        "event_key": "oil-prices:2026-07-27T06:00:00Z",
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
                "raw_data": {
                    "code": "WTI_USD",
                    "price": "68.42",
                },
            }
        ],
    }


def test_consumer_archives_only_after_persistence(
    monkeypatch,
) -> None:
    archived: list[int] = []

    monkeypatch.setattr(
        messaging,
        "insert_batch",
        lambda session, observations: (1, 0),
    )

    monkeypatch.setattr(
        messaging.PGMQConsumer,
        "_archive_message",
        lambda self, msg_id: archived.append(msg_id),
    )

    class FakeSession:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return None

    monkeypatch.setattr(
        messaging,
        "SessionLocal",
        lambda: FakeSession(),
    )

    consumer = messaging.PGMQConsumer(Settings())

    consumer._handle_message(
        msg_id=123,
        read_count=1,
        message=valid_event(),
    )

    assert archived == [123]


def test_consumer_archives_invalid_schema(
    monkeypatch,
) -> None:
    archived: list[int] = []

    monkeypatch.setattr(
        messaging.PGMQConsumer,
        "_archive_message",
        lambda self, msg_id: archived.append(msg_id),
    )

    payload = valid_event()
    payload["schema_version"] = 99

    consumer = messaging.PGMQConsumer(Settings())

    consumer._handle_message(
        msg_id=456,
        read_count=1,
        message=payload,
    )

    assert archived == [456]


def test_consumer_does_not_archive_transient_failure(
    monkeypatch,
) -> None:
    archived: list[int] = []

    def fail_persistence(session, observations):
        raise RuntimeError("database is temporarily unavailable")

    monkeypatch.setattr(
        messaging,
        "insert_batch",
        fail_persistence,
    )

    monkeypatch.setattr(
        messaging.PGMQConsumer,
        "_archive_message",
        lambda self, msg_id: archived.append(msg_id),
    )

    class FakeSession:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return None

    monkeypatch.setattr(
        messaging,
        "SessionLocal",
        lambda: FakeSession(),
    )

    consumer = messaging.PGMQConsumer(Settings(pgmq_max_attempts=5))

    consumer._handle_message(
        msg_id=789,
        read_count=2,
        message=valid_event(),
    )

    assert archived == []


def test_consumer_archives_after_retry_limit(
    monkeypatch,
) -> None:
    archived: list[int] = []

    def fail_persistence(session, observations):
        raise RuntimeError("database is still unavailable")

    monkeypatch.setattr(
        messaging,
        "insert_batch",
        fail_persistence,
    )

    monkeypatch.setattr(
        messaging.PGMQConsumer,
        "_archive_message",
        lambda self, msg_id: archived.append(msg_id),
    )

    class FakeSession:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return None

    monkeypatch.setattr(
        messaging,
        "SessionLocal",
        lambda: FakeSession(),
    )

    consumer = messaging.PGMQConsumer(Settings(pgmq_max_attempts=5))

    consumer._handle_message(
        msg_id=999,
        read_count=5,
        message=valid_event(),
    )

    assert archived == [999]


class FakeRabbitMessage:
    def __init__(self, body: bytes, headers: dict | None = None) -> None:
        self.body = body
        self.headers = headers or {}
        self.content_type = "application/json"
        self.message_id = "oil-prices:2026-07-27T06:00:00Z"
        self.type = "prices.observed.v1"
        self.acked = False
        self.rejected = False
        self.requeued = False

    async def ack(self) -> None:
        self.acked = True

    async def reject(self, *, requeue: bool) -> None:
        self.rejected = True
        self.requeued = requeue

    async def nack(self, *, requeue: bool) -> None:
        self.requeued = requeue


class FakeRabbitExchange:
    def __init__(self) -> None:
        self.published = []

    async def publish(self, message, *, routing_key: str, mandatory: bool) -> None:
        self.published.append((message, routing_key, mandatory))


def test_rabbit_consumer_acknowledges_after_persistence(monkeypatch) -> None:
    monkeypatch.setattr(messaging, "_persist_event", lambda event: (1, 0))
    message = FakeRabbitMessage(json.dumps(valid_event()).encode())
    consumer = messaging.RabbitMQConsumer(Settings())

    asyncio.run(consumer._handle(message))

    assert message.acked is True
    assert message.rejected is False


def test_rabbit_consumer_dead_letters_invalid_event() -> None:
    payload = valid_event()
    payload["schema_version"] = 99
    message = FakeRabbitMessage(json.dumps(payload).encode())
    consumer = messaging.RabbitMQConsumer(Settings())

    asyncio.run(consumer._handle(message))

    assert message.acked is False
    assert message.rejected is True
    assert message.requeued is False


def test_rabbit_consumer_republishes_transient_failure(monkeypatch) -> None:
    def fail_persistence(event):
        raise RuntimeError("database is temporarily unavailable")

    monkeypatch.setattr(messaging, "_persist_event", fail_persistence)
    message = FakeRabbitMessage(json.dumps(valid_event()).encode(), headers={"x-retry-count": 1})
    exchange = FakeRabbitExchange()
    consumer = messaging.RabbitMQConsumer(Settings(rabbitmq_max_attempts=5))
    consumer.exchange = exchange

    asyncio.run(consumer._handle(message))

    assert message.acked is True
    assert message.rejected is False
    assert len(exchange.published) == 1
    retried, routing_key, mandatory = exchange.published[0]
    assert retried.headers["x-retry-count"] == 2
    assert routing_key == "prices.observed"
    assert mandatory is True
