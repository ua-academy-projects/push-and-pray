"""Combined RabbitMQ/MariaDB delivery tests.

These require both integration opt-ins and a dedicated, migrated MariaDB test
database. They never declare or delete production RabbitMQ topology names.
"""

import asyncio
import json
import os
from typing import Any
from uuid import UUID

import aio_pika
import pytest
from history_service.blacklist_consumer import (
    BlacklistMessageHandler,
    HistoryBlacklistConsumer,
    RabbitMQFailureStrategy,
)
from history_service.blacklist_ingestion import BlacklistIngestionService
from history_service.models import BlacklistSnapshot, BlacklistSnapshotEntry
from history_service.service import HistoryUnavailableError
from sqlalchemy import URL, create_engine, delete, func, select
from sqlalchemy.orm import Session, sessionmaker

from .test_rabbitmq_integration import (
    body,
    broker_config,
    cleanup,
    declare_topology,
    message,
    settings,
    wait_for_consumer,
    wait_for_message,
)

pytestmark = [pytest.mark.rabbitmq, pytest.mark.mariadb, pytest.mark.anyio]


def database_factory() -> tuple[sessionmaker[Session], Any]:
    if os.getenv("RUN_MARIADB_TESTS") != "1":
        pytest.skip("Set RUN_MARIADB_TESTS=1 for MariaDB integration tests.")
    required = {
        name: os.getenv(name)
        for name in (
            "TEST_MARIADB_DATABASE",
            "TEST_MARIADB_USER",
            "TEST_MARIADB_PASSWORD",
        )
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        pytest.skip(f"Missing MariaDB test settings: {', '.join(missing)}")
    engine = create_engine(
        URL.create(
            "mariadb+pymysql",
            username=required["TEST_MARIADB_USER"],
            password=required["TEST_MARIADB_PASSWORD"],
            host=os.getenv("TEST_MARIADB_HOST", "127.0.0.1"),
            port=int(os.getenv("TEST_MARIADB_PORT", "3306")),
            database=required["TEST_MARIADB_DATABASE"],
            query={"charset": "utf8mb4"},
        ),
        pool_pre_ping=True,
    )
    return sessionmaker(bind=engine, expire_on_commit=False), engine


class AckAfterCommit:
    def __init__(self, incoming: Any, committed: list[bool]) -> None:
        self._incoming = incoming
        self._committed = committed

    def __getattr__(self, name: str) -> Any:
        return getattr(self._incoming, name)

    async def ack(self, *args: Any, **kwargs: Any) -> None:
        assert self._committed == [True]
        await self._incoming.ack(*args, **kwargs)


async def publish_and_get(config, payload: bytes):
    connection = await aio_pika.connect_robust(**broker_config())
    channel = await connection.channel(publisher_confirms=True)
    exchange = await channel.declare_exchange(
        config.rabbitmq_exchange_name, passive=True
    )
    await exchange.publish(
        message(payload), config.rabbitmq_routing_key, mandatory=True
    )
    queue = await channel.declare_queue(config.rabbitmq_queue_name, passive=True)
    return connection, channel, await wait_for_message(queue)


async def test_running_history_consumer_persists_valid_message() -> None:
    config = settings()
    factory, engine = database_factory()
    payload = body()
    delivery_id = UUID(json.loads(payload)["delivery_id"])
    handler = BlacklistMessageHandler(
        session_factory=factory,
        ingestion_service=BlacklistIngestionService(),
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
        message(payload), config.rabbitmq_routing_key, mandatory=True
    )
    try:
        async with asyncio.timeout(5):
            while True:
                with factory() as session:
                    count = session.scalar(
                        select(func.count())
                        .select_from(BlacklistSnapshot)
                        .where(BlacklistSnapshot.delivery_id == str(delivery_id))
                    )
                if count == 1:
                    break
                await asyncio.sleep(0.05)
    finally:
        stop.set()
        await task
        with factory() as session:
            session.execute(
                delete(BlacklistSnapshot).where(
                    BlacklistSnapshot.delivery_id == str(delivery_id)
                )
            )
            session.commit()
        await connection.close()
        engine.dispose()
        await cleanup(config)


async def test_consumer_handler_commits_before_ack() -> None:
    config = settings()
    await declare_topology(config)
    factory, engine = database_factory()
    payload = body()
    delivery_id = UUID(json.loads(payload)["delivery_id"])
    committed: list[bool] = []

    class SignalingService(BlacklistIngestionService):
        def ingest(self, session, delivery):
            result = super().ingest(session, delivery)
            committed.append(True)
            return result

    connection, _, incoming = await publish_and_get(config, payload)
    handler = BlacklistMessageHandler(
        session_factory=factory,
        ingestion_service=SignalingService(),
    )
    try:
        await handler.handle(AckAfterCommit(incoming, committed))
        with factory() as session:
            assert (
                session.scalar(
                    select(func.count())
                    .select_from(BlacklistSnapshot)
                    .where(BlacklistSnapshot.delivery_id == str(delivery_id))
                )
                == 1
            )
    finally:
        with factory() as session:
            session.execute(
                delete(BlacklistSnapshot).where(
                    BlacklistSnapshot.delivery_id == str(delivery_id)
                )
            )
            session.commit()
        await connection.close()
        engine.dispose()
        await cleanup(config)


async def test_database_failure_moves_to_confirmed_retry() -> None:
    config = settings()
    await declare_topology(config)
    factory, engine = database_factory()
    connection, channel, incoming = await publish_and_get(config, body())
    strategy = RabbitMQFailureStrategy(config)
    retry_exchange = await channel.declare_exchange(
        config.rabbitmq_retry_exchange_name, passive=True
    )
    dead_exchange = await channel.declare_exchange(
        config.rabbitmq_dead_letter_exchange_name, passive=True
    )
    strategy.configure(
        retry_exchange=retry_exchange,
        dead_letter_exchange=dead_exchange,
    )
    service = BlacklistIngestionService()
    service.ingest = lambda session, delivery: (_ for _ in ()).throw(
        HistoryUnavailableError()
    )
    handler = BlacklistMessageHandler(
        session_factory=factory,
        ingestion_service=service,
        failure_strategy=strategy,
    )
    try:
        await handler.handle(incoming)
        retry_queue = await channel.declare_queue(
            f"{config.rabbitmq_queue_name}.retry.300", passive=True
        )
        assert retry_queue.declaration_result.message_count == 1
        assert incoming.processed is True
    finally:
        await connection.close()
        engine.dispose()
        await cleanup(config)


async def test_duplicate_redelivery_persists_one_snapshot() -> None:
    config = settings()
    await declare_topology(config)
    factory, engine = database_factory()
    payload = body(
        items=[
            {
                "ip_address": "8.8.8.8",
                "ip_version": 4,
                "abuse_confidence_score": 99,
                "country_code": "US",
                "last_reported_at": None,
            }
        ]
    )
    delivery_id = UUID(json.loads(payload)["delivery_id"])
    handler = BlacklistMessageHandler(
        session_factory=factory,
        ingestion_service=BlacklistIngestionService(),
    )
    first_connection, _, first = await publish_and_get(config, payload)
    await handler.handle(first)
    await first_connection.close()
    second_connection, _, duplicate = await publish_and_get(config, payload)
    try:
        await handler.handle(duplicate)
        with factory() as session:
            assert (
                session.scalar(
                    select(func.count())
                    .select_from(BlacklistSnapshot)
                    .where(BlacklistSnapshot.delivery_id == str(delivery_id))
                )
                == 1
            )
            snapshot_id = session.scalar(
                select(BlacklistSnapshot.snapshot_id).where(
                    BlacklistSnapshot.delivery_id == str(delivery_id)
                )
            )
            assert (
                session.scalar(
                    select(func.count())
                    .select_from(BlacklistSnapshotEntry)
                    .where(BlacklistSnapshotEntry.snapshot_id == snapshot_id)
                )
                == 1
            )
    finally:
        with factory() as session:
            session.execute(
                delete(BlacklistSnapshot).where(
                    BlacklistSnapshot.delivery_id == str(delivery_id)
                )
            )
            session.commit()
        await second_connection.close()
        engine.dispose()
        await cleanup(config)
