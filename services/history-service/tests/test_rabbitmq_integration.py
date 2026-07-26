"""History broker integration tests.

Enable with RUN_RABBITMQ_TESTS=1 and dedicated TEST_RABBITMQ_HOST,
TEST_RABBITMQ_USER, and TEST_RABBITMQ_PASSWORD values. Optional variables are
TEST_RABBITMQ_PORT and TEST_RABBITMQ_VHOST. Names are UUID-scoped per test.
"""

import asyncio
import json
import os
from datetime import UTC, datetime
from typing import Any
from unittest.mock import Mock
from uuid import uuid4

import aio_pika
import pytest
from aio_pika import DeliveryMode, Message
from history_service.blacklist_consumer import (
    RETRY_ATTEMPT_HEADER,
    BlacklistMessageHandler,
    HistoryBlacklistConsumer,
)
from history_service.config import Settings
from history_service.service import HistoryUnavailableError

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


def settings() -> Settings:
    suffix = uuid4().hex
    prefix = f"aegis.test.history.{suffix}"
    config = broker_config()
    return Settings(
        _env_file=None,
        mariadb_database="unused",
        mariadb_user="unused",
        mariadb_password="unused",
        rabbitmq_host=str(config["host"]),
        rabbitmq_port=int(config["port"]),
        rabbitmq_virtual_host=str(config["virtualhost"]),
        rabbitmq_username=str(config["login"]),
        rabbitmq_password=str(config["password"]),
        rabbitmq_exchange_name=f"{prefix}.main",
        rabbitmq_queue_name=f"{prefix}.queue",
        rabbitmq_retry_exchange_name=f"{prefix}.retry",
        rabbitmq_dead_letter_exchange_name=f"{prefix}.dead",
        rabbitmq_dead_letter_queue_name=f"{prefix}.dead.queue",
        rabbitmq_routing_key=f"{prefix}.route",
        rabbitmq_connection_timeout_seconds=3,
        rabbitmq_publish_timeout_seconds=3,
        rabbitmq_shutdown_timeout_seconds=2,
    )


def body() -> bytes:
    now = datetime.now(UTC)
    identifier = uuid4()

    return json.dumps(
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
    ).encode()


def message(payload: bytes, *, headers: dict[str, Any] | None = None) -> Message:
    envelope = json.loads(payload)
    return Message(
        payload,
        headers=headers,
        content_type="application/json",
        content_encoding="utf-8",
        delivery_mode=DeliveryMode.PERSISTENT,
        message_id=envelope["delivery_id"],
        correlation_id=envelope["correlation_id"],
        timestamp=datetime.fromisoformat(envelope["created_at"]),
        type=envelope["message_type"],
        app_id=envelope["producer"],
    )


async def declare_topology(config: Settings) -> None:
    stop = asyncio.Event()
    stop.set()
    handler = BlacklistMessageHandler(
        session_factory=Mock(),
        ingestion_service=Mock(),
    )
    await HistoryBlacklistConsumer(config, handler).run(stop)


async def cleanup(config: Settings) -> None:
    connection = await aio_pika.connect_robust(**broker_config())
    try:
        channel = await connection.channel()
        for delay in (300, 900, 1800, 3600):
            queue = await channel.declare_queue(
                f"{config.rabbitmq_queue_name}.retry.{delay}", passive=True
            )
            await queue.delete(if_unused=False, if_empty=False)
        for name in (
            config.rabbitmq_queue_name,
            config.rabbitmq_dead_letter_queue_name,
        ):
            queue = await channel.declare_queue(name, passive=True)
            await queue.delete(if_unused=False, if_empty=False)
        for name in (
            config.rabbitmq_exchange_name,
            config.rabbitmq_retry_exchange_name,
            config.rabbitmq_dead_letter_exchange_name,
        ):
            exchange = await channel.declare_exchange(name, passive=True)
            await exchange.delete(if_unused=False)
    finally:
        await connection.close()


async def wait_for_message(queue: aio_pika.abc.AbstractQueue):
    async with asyncio.timeout(5):
        while True:
            incoming = await queue.get(no_ack=False, fail=False)
            if incoming is not None:
                return incoming
            await asyncio.sleep(0.05)


async def wait_for_consumer(config: Settings) -> None:
    async with asyncio.timeout(5):
        while True:
            connection = await aio_pika.connect_robust(**broker_config())
            try:
                channel = await connection.channel()
                queue = await channel.declare_queue(
                    config.rabbitmq_queue_name, passive=True
                )
                if queue.declaration_result.consumer_count:
                    return
            except Exception:
                pass
            finally:
                await connection.close()
            await asyncio.sleep(0.05)


async def test_durable_declarations_survive_reconnect() -> None:
    config = settings()
    try:
        await declare_topology(config)
        connection = await aio_pika.connect_robust(**broker_config())
        channel = await connection.channel()
        await channel.declare_exchange(config.rabbitmq_exchange_name, passive=True)
        await channel.declare_queue(config.rabbitmq_queue_name, passive=True)
        await connection.close()
    finally:
        await cleanup(config)


async def test_persistent_message_survives_consumer_reconnect() -> None:
    config = settings()
    await declare_topology(config)
    connection = await aio_pika.connect_robust(**broker_config())
    channel = await connection.channel(publisher_confirms=True)
    exchange = await channel.declare_exchange(
        config.rabbitmq_exchange_name, passive=True
    )
    await exchange.publish(message(body()), config.rabbitmq_routing_key, mandatory=True)
    await connection.close()
    try:
        connection = await aio_pika.connect_robust(**broker_config())
        channel = await connection.channel()
        queue = await channel.declare_queue(config.rabbitmq_queue_name, passive=True)
        incoming = await wait_for_message(queue)
        await incoming.ack()
        await connection.close()
    finally:
        await cleanup(config)


async def test_consumer_restart_redelivers_unacknowledged_message() -> None:
    config = settings()
    await declare_topology(config)
    connection = await aio_pika.connect_robust(**broker_config())
    channel = await connection.channel(publisher_confirms=True)
    exchange = await channel.declare_exchange(
        config.rabbitmq_exchange_name, passive=True
    )
    await exchange.publish(message(body()), config.rabbitmq_routing_key, mandatory=True)
    queue = await channel.declare_queue(config.rabbitmq_queue_name, passive=True)
    first = await wait_for_message(queue)
    assert not first.processed
    await connection.close()
    try:
        connection = await aio_pika.connect_robust(**broker_config())
        channel = await connection.channel()
        queue = await channel.declare_queue(config.rabbitmq_queue_name, passive=True)
        redelivered = await wait_for_message(queue)
        assert redelivered.redelivered is True
        await redelivered.ack()
        await connection.close()
    finally:
        await cleanup(config)


@pytest.mark.parametrize(
    ("payload", "headers"),
    [
        (b"{not-json", None),
        (body(), {RETRY_ATTEMPT_HEADER: 4}),
    ],
)
async def test_invalid_or_exhausted_message_reaches_dlq(
    payload: bytes, headers: dict[str, Any] | None
) -> None:
    config = settings()
    service = Mock()
    if headers is not None:
        service.ingest.side_effect = HistoryUnavailableError
    handler = BlacklistMessageHandler(
        session_factory=lambda: Mock(),
        ingestion_service=service,
    )
    consumer = HistoryBlacklistConsumer(config, handler)
    stop = asyncio.Event()
    task = asyncio.create_task(consumer.run(stop))
    await wait_for_consumer(config)
    connection = await aio_pika.connect_robust(**broker_config())
    channel = await connection.channel(publisher_confirms=True)
    exchange = await channel.declare_exchange(
        config.rabbitmq_exchange_name, passive=True
    )
    await exchange.publish(
        message(payload, headers=headers),
        config.rabbitmq_routing_key,
        mandatory=True,
    )
    dead_queue = await channel.declare_queue(
        config.rabbitmq_dead_letter_queue_name, passive=True
    )
    incoming = await wait_for_message(dead_queue)
    assert incoming.body == payload
    await incoming.ack()
    stop.set()
    await task
    await connection.close()
    await cleanup(config)
