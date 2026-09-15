from __future__ import annotations

import asyncio
import json
import os

import aio_pika
import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

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


DATABASE_URL = os.getenv("PGMQ_TEST_SQLALCHEMY_URL")
BROKER_URL = os.getenv("AMQP_TEST_URL")

SETTINGS = Settings(
    database_url=DATABASE_URL or "",
    queue_backend="amqp",
    amqp_url=BROKER_URL or "",
    amqp_exchange="oil.price.events.test",
    amqp_queue="history.price-observations.test",
    amqp_routing_key="prices.observed",
    amqp_max_attempts=3,
    amqp_retry_delay_seconds=0.05,
    amqp_reconnect_delay_seconds=0.1,
)


@pytest.fixture()
def database_engine(monkeypatch):
    if not DATABASE_URL or not BROKER_URL:
        pytest.skip("PGMQ_TEST_SQLALCHEMY_URL and AMQP_TEST_URL are not configured")

    engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_size=5, max_overflow=5)

    with engine.begin() as connection:
        connection.execute(text("TRUNCATE TABLE price_observations"))

    monkeypatch.setattr(
        messaging,
        "SessionLocal",
        sessionmaker(bind=engine, expire_on_commit=False),
    )

    asyncio.run(reset_broker())

    yield engine

    engine.dispose()


async def reset_broker() -> None:
    """Declare the test topology from scratch so every test starts empty."""
    connection = await aio_pika.connect_robust(BROKER_URL)

    async with connection:
        channel = await connection.channel()

        for name in (SETTINGS.amqp_queue, f"{SETTINGS.amqp_queue}.dead"):
            await channel.queue_delete(name)

        await messaging.declare_topology(channel, SETTINGS)


async def publish(payload: dict | bytes) -> None:
    connection = await aio_pika.connect_robust(BROKER_URL)

    async with connection:
        channel = await connection.channel()
        exchange = await channel.get_exchange(SETTINGS.amqp_exchange)

        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()

        await exchange.publish(
            aio_pika.Message(body, content_type="application/json"),
            routing_key=SETTINGS.amqp_routing_key,
        )


async def queue_depth(name: str) -> int:
    connection = await aio_pika.connect_robust(BROKER_URL)

    async with connection:
        channel = await connection.channel()
        queue = await channel.get_queue(name, ensure=False)
        declared = await queue.declare()

        return declared.message_count


async def run_consumer_until(predicate, timeout: float = 10.0) -> None:
    consumer = messaging.AMQPConsumer(SETTINGS)

    await consumer.start()

    try:
        deadline = asyncio.get_running_loop().time() + timeout

        while asyncio.get_running_loop().time() < deadline:
            if await asyncio.to_thread(predicate):
                return

            await asyncio.sleep(0.1)

        pytest.fail("the consumer did not reach the expected state in time")
    finally:
        await consumer.stop()


def observation_count(engine) -> int:
    with engine.connect() as connection:
        return connection.execute(text("SELECT COUNT(*) FROM price_observations")).scalar_one()


def test_history_persists_amqp_event_exactly_once(database_engine) -> None:
    payload = valid_event()

    asyncio.run(publish(payload))
    asyncio.run(publish(payload))

    asyncio.run(
        run_consumer_until(
            lambda: (
                observation_count(database_engine) == 1
                and asyncio.run(queue_depth(SETTINGS.amqp_queue)) == 0
            )
        )
    )

    assert observation_count(database_engine) == 1
    assert asyncio.run(queue_depth(f"{SETTINGS.amqp_queue}.dead")) == 0


def test_invalid_amqp_event_is_dead_lettered(database_engine) -> None:
    asyncio.run(publish(b"this is not an event"))

    asyncio.run(
        run_consumer_until(lambda: asyncio.run(queue_depth(f"{SETTINGS.amqp_queue}.dead")) == 1)
    )

    assert observation_count(database_engine) == 0
    assert asyncio.run(queue_depth(SETTINGS.amqp_queue)) == 0


def test_transient_failure_is_dead_lettered_after_the_limit(database_engine, monkeypatch) -> None:
    attempts: list[int] = []

    def fail_persistence(message):
        attempts.append(1)
        raise RuntimeError("database is temporarily unavailable")

    monkeypatch.setattr(messaging, "persist_event", fail_persistence)

    asyncio.run(publish(valid_event()))

    asyncio.run(
        run_consumer_until(lambda: asyncio.run(queue_depth(f"{SETTINGS.amqp_queue}.dead")) == 1)
    )

    # The delivery limit allows max_attempts redeliveries on top of the first.
    assert len(attempts) == SETTINGS.amqp_max_attempts + 1
    assert asyncio.run(queue_depth(SETTINGS.amqp_queue)) == 0
