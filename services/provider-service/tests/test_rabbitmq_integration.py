"""Provider RabbitMQ integration tests.

Run with RUN_RABBITMQ_TESTS=1 and TEST_RABBITMQ_HOST,
TEST_RABBITMQ_USER, and TEST_RABBITMQ_PASSWORD. TEST_RABBITMQ_PORT and
TEST_RABBITMQ_VHOST are optional. Every test uses UUID-scoped topology.
"""

import os
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import aio_pika
import pytest
from aio_pika import ExchangeType
from provider_service.blacklist_worker import BlacklistPollingWorker
from provider_service.config import Settings
from provider_service.outbox import BlacklistOutbox
from provider_service.polling_policy import PollingPolicy
from provider_service.rabbitmq_publisher import (
    AioPikaBlacklistPublisher,
    BlacklistPublishingUnroutableError,
)
from provider_service.schemas import (
    BlacklistProviderResult,
    BlacklistSnapshotMessage,
    RateLimitMetadata,
)

pytestmark = [pytest.mark.rabbitmq, pytest.mark.anyio]


def broker_config() -> dict[str, object]:
    if os.getenv("RUN_RABBITMQ_TESTS") != "1":
        pytest.skip("Set RUN_RABBITMQ_TESTS=1 for RabbitMQ integration tests.")
    required = {
        name: os.getenv(name)
        for name in (
            "TEST_RABBITMQ_HOST",
            "TEST_RABBITMQ_USER",
            "TEST_RABBITMQ_PASSWORD",
        )
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        pytest.skip(f"Missing RabbitMQ test settings: {', '.join(missing)}")
    return {
        "host": required["TEST_RABBITMQ_HOST"],
        "port": int(os.getenv("TEST_RABBITMQ_PORT", "5672")),
        "login": required["TEST_RABBITMQ_USER"],
        "password": required["TEST_RABBITMQ_PASSWORD"],
        "virtualhost": os.getenv("TEST_RABBITMQ_VHOST", "/"),
        "timeout": 3,
    }


def names() -> tuple[str, str, str]:
    suffix = uuid4().hex
    return (
        f"aegis.test.provider.{suffix}",
        f"aegis.test.provider.{suffix}.queue",
        f"aegis.test.provider.{suffix}.route",
    )


def settings(exchange: str, routing_key: str, *, port: int | None = None) -> Settings:
    config = broker_config()
    return Settings(
        _env_file=None,
        abuseipdb_api_key="integration-test",
        rabbitmq_host=str(config["host"]),
        rabbitmq_port=port or int(config["port"]),
        rabbitmq_virtual_host=str(config["virtualhost"]),
        rabbitmq_username=str(config["login"]),
        rabbitmq_password=str(config["password"]),
        rabbitmq_exchange_name=exchange,
        rabbitmq_routing_key=routing_key,
        rabbitmq_connection_timeout_seconds=3,
        rabbitmq_publish_timeout_seconds=3,
    )


def snapshot_message() -> BlacklistSnapshotMessage:
    now = datetime.now(UTC)
    identifier = uuid4()
    return BlacklistSnapshotMessage.model_validate(
        {
            "schema_version": 1,
            "message_type": "blacklist.snapshot.complete",
            "delivery_id": str(identifier),
            "correlation_id": str(identifier),
            "producer": "aegis-provider-service",
            "provider": "AbuseIPDB",
            "created_at": now.isoformat(),
            "snapshot": {
                "provider": "AbuseIPDB",
                "generated_at": now.isoformat(),
                "fetched_at": now.isoformat(),
                "request": {"confidence_minimum": 90, "limit": 1000},
                "rate_limit": {},
                "items": [],
            },
        }
    )


async def cleanup(exchange_name: str, queue_name: str) -> None:
    connection = await aio_pika.connect_robust(**broker_config())
    try:
        channel = await connection.channel()
        queue = await channel.declare_queue(queue_name, passive=True)
        await queue.delete(if_unused=False, if_empty=False)
        exchange = await channel.declare_exchange(exchange_name, passive=True)
        await exchange.delete(if_unused=False)
    finally:
        await connection.close()


@pytest.mark.parametrize("bind_queue", [True, False])
async def test_provider_confirmation_and_mandatory_routing(
    bind_queue: bool,
) -> None:
    exchange_name, queue_name, routing_key = names()
    connection = await aio_pika.connect_robust(**broker_config())
    channel = await connection.channel()
    exchange = await channel.declare_exchange(
        exchange_name, ExchangeType.DIRECT, durable=True
    )
    if bind_queue:
        queue = await channel.declare_queue(queue_name, durable=True)
        await queue.bind(exchange, routing_key)
    await connection.close()

    publisher = AioPikaBlacklistPublisher(settings(exchange_name, routing_key))
    try:
        await publisher.connect()
        if bind_queue:
            await publisher.publish(snapshot_message())
        else:
            with pytest.raises(BlacklistPublishingUnroutableError):
                await publisher.publish(snapshot_message())
    finally:
        await publisher.close()
        if bind_queue:
            await cleanup(exchange_name, queue_name)
        else:
            connection = await aio_pika.connect_robust(**broker_config())
            channel = await connection.channel()
            exchange = await channel.declare_exchange(exchange_name, passive=True)
            await exchange.delete(if_unused=False)
            await connection.close()


class Provider:
    async def blacklist(
        self, confidence_minimum: int, limit: int
    ) -> BlacklistProviderResult:
        now = datetime.now(UTC)
        return BlacklistProviderResult(
            generated_at=now,
            rate_limit=RateLimitMetadata(),
            items=[],
        )


class Clock:
    def __init__(self) -> None:
        self.now = datetime.now(UTC)

    def __call__(self) -> datetime:
        return self.now


async def test_outbox_retains_during_outage_and_publishes_after_recovery(
    tmp_path: Path,
) -> None:
    exchange_name, queue_name, routing_key = names()
    clock = Clock()
    outbox_path = tmp_path / "outbox.sqlite3"
    unavailable = AioPikaBlacklistPublisher(
        settings(exchange_name, routing_key, port=1)
    )
    outbox = BlacklistOutbox(outbox_path)
    failed_worker = BlacklistPollingWorker(
        provider=Provider(),
        publisher=unavailable,
        outbox=outbox,
        policy=PollingPolicy(
            interval_seconds=21600,
            publish_initial_seconds=1,
            publish_maximum_seconds=2,
        ),
        clock=clock,
    )
    await failed_worker.tick()
    assert outbox.pending_count() == 1
    outbox.close()

    connection = await aio_pika.connect_robust(**broker_config())
    channel = await connection.channel()
    exchange = await channel.declare_exchange(
        exchange_name, ExchangeType.DIRECT, durable=True
    )
    queue = await channel.declare_queue(queue_name, durable=True)
    await queue.bind(exchange, routing_key)
    await connection.close()

    clock.now += timedelta(seconds=1)
    publisher = AioPikaBlacklistPublisher(settings(exchange_name, routing_key))
    await publisher.connect()
    recovered = BlacklistOutbox(outbox_path)
    restarted = BlacklistPollingWorker(
        provider=Provider(),
        publisher=publisher,
        outbox=recovered,
        policy=PollingPolicy(
            interval_seconds=21600,
            publish_initial_seconds=1,
            publish_maximum_seconds=2,
        ),
        clock=clock,
    )
    try:
        await restarted.tick()
        assert recovered.pending_count() == 0
        connection = await aio_pika.connect_robust(**broker_config())
        channel = await connection.channel()
        queue = await channel.declare_queue(queue_name, passive=True)
        incoming = await queue.get(no_ack=False, fail=True)
        assert BlacklistSnapshotMessage.model_validate_json(incoming.body)
        await incoming.ack()
        await connection.close()
    finally:
        recovered.close()
        await publisher.close()
        await cleanup(exchange_name, queue_name)
