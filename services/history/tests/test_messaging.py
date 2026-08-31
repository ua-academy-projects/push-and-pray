import asyncio

import pytest

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


def test_consumer_becomes_ready_only_after_successful_queue_poll(
    monkeypatch,
) -> None:
    consumer = messaging.PGMQConsumer(Settings())

    monkeypatch.setattr(
        consumer,
        "_process_next_message",
        lambda: False,
    )

    async def stop_after_poll(_: float) -> None:
        raise asyncio.CancelledError

    monkeypatch.setattr(messaging.asyncio, "sleep", stop_after_poll)

    with pytest.raises(asyncio.CancelledError):
        asyncio.run(consumer._run())

    assert consumer.ready is True


def test_consumer_is_not_ready_when_queue_poll_fails(
    monkeypatch,
) -> None:
    consumer = messaging.PGMQConsumer(Settings())

    def fail_poll() -> bool:
        raise RuntimeError("queue is unavailable")

    monkeypatch.setattr(consumer, "_process_next_message", fail_poll)

    async def stop_after_failure(_: float) -> None:
        raise asyncio.CancelledError

    monkeypatch.setattr(messaging.asyncio, "sleep", stop_after_failure)

    with pytest.raises(asyncio.CancelledError):
        asyncio.run(consumer._run())

    assert consumer.ready is False
