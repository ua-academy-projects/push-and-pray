from __future__ import annotations

import asyncio
import logging
from typing import Any

import aio_pika
from aio_pika import ExchangeType
from aio_pika.abc import AbstractIncomingMessage, AbstractRobustConnection
from pydantic import ValidationError
from sqlalchemy import text

from .config import Settings
from .database import SessionLocal
from .repository import insert_batch
from .schemas import ObservationEvent

logger = logging.getLogger(__name__)


def _persist_event(event: ObservationEvent) -> tuple[int, int]:
    with SessionLocal() as session:
        return insert_batch(session, event.observations)


class PGMQConsumer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.task: asyncio.Task[None] | None = None
        self.ready = False

    @property
    def is_ready(self) -> bool:
        return bool(self.ready and self.task is not None and not self.task.done())

    async def start(self) -> None:
        self.ready = True

        self.task = asyncio.create_task(
            self._run(),
            name="pgmq-history-consumer",
        )

    async def stop(self) -> None:
        self.ready = False

        if self.task is not None:
            self.task.cancel()

            try:
                await self.task
            except asyncio.CancelledError:
                pass

    async def _run(self) -> None:
        logger.info(
            "PostgreSQL queue consumer started",
            extra={
                "queue": self.settings.pgmq_queue,
            },
        )

        while True:
            try:
                processed = await asyncio.to_thread(self._process_next_message)

                if not processed:
                    await asyncio.sleep(self.settings.pgmq_poll_interval_seconds)

            except asyncio.CancelledError:
                raise

            except Exception:
                logger.exception("PostgreSQL queue consumer failed; retrying")

                await asyncio.sleep(self.settings.pgmq_poll_interval_seconds)

    def _process_next_message(self) -> bool:
        with SessionLocal() as session:
            result = session.execute(
                text(
                    """
                    WITH candidate AS (
                        SELECT msg_id
                        FROM observation_queue
                        WHERE visible_at <= CURRENT_TIMESTAMP
                        ORDER BY msg_id
                        FOR UPDATE SKIP LOCKED
                        LIMIT 1
                    )
                    UPDATE observation_queue AS queue
                    SET
                        read_count = queue.read_count + 1,
                        visible_at = CURRENT_TIMESTAMP
                            + make_interval(secs => :visibility_timeout)
                    FROM candidate
                    WHERE queue.msg_id = candidate.msg_id
                    RETURNING
                        queue.msg_id,
                        queue.read_count AS read_ct,
                        queue.message
                    """
                ),
                {
                    "queue_name": self.settings.pgmq_queue,
                    "visibility_timeout": self.settings.pgmq_visibility_timeout_seconds,
                },
            )

            row = result.mappings().first()

            if row is None:
                session.commit()
                return False

            message = dict(row)

            session.commit()

        self._handle_message(
            msg_id=message["msg_id"],
            read_count=message["read_ct"],
            message=message["message"],
        )

        return True

    def _handle_message(
        self,
        msg_id: int,
        read_count: int,
        message: dict[str, Any],
    ) -> None:
        try:
            event = ObservationEvent.model_validate(message)

        except ValidationError as exc:
            logger.error(
                "permanently invalid queue message",
                extra={
                    "msg_id": msg_id,
                    "error": str(exc),
                },
            )

            self._archive_message(msg_id)

            return

        try:
            with SessionLocal() as session:
                inserted, duplicates = insert_batch(
                    session,
                    event.observations,
                )

        except Exception:
            logger.exception(
                "failed to persist queue message",
                extra={
                    "msg_id": msg_id,
                    "read_count": read_count,
                },
            )

            if read_count >= self.settings.pgmq_max_attempts:
                logger.error(
                    "queue message exceeded retry limit",
                    extra={
                        "msg_id": msg_id,
                        "read_count": read_count,
                    },
                )

                self._archive_message(msg_id)

            return

        self._archive_message(msg_id)

        logger.info(
            "queue message persisted",
            extra={
                "msg_id": msg_id,
                "read_count": read_count,
                "event_key": event.event_key,
                "inserted": inserted,
                "duplicates": duplicates,
            },
        )

    def _archive_message(
        self,
        msg_id: int,
    ) -> None:
        with SessionLocal() as session:
            archived = session.execute(
                text(
                    """
                    WITH archived AS (
                        DELETE FROM observation_queue
                        WHERE msg_id = :msg_id
                        RETURNING msg_id, message, read_count, enqueued_at
                    )
                    INSERT INTO observation_queue_archive (
                        msg_id,
                        message,
                        read_count,
                        enqueued_at
                    )
                    SELECT msg_id, message, read_count, enqueued_at
                    FROM archived
                    ON CONFLICT (msg_id) DO NOTHING
                    RETURNING msg_id
                    """
                ),
                {
                    "msg_id": msg_id,
                },
            ).scalar_one_or_none()

            session.commit()

            if archived is None:
                raise RuntimeError(f"failed to archive queue message {msg_id}")


class RabbitMQConsumer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.connection: AbstractRobustConnection | None = None
        self.task: asyncio.Task[None] | None = None
        self.ready = False

    @property
    def is_ready(self) -> bool:
        return bool(
            self.ready
            and self.connection is not None
            and not self.connection.is_closed
            and self.connection.connected.is_set()
        )

    async def start(self) -> None:
        self.task = asyncio.create_task(self._run(), name="rabbitmq-history-consumer")

    async def stop(self) -> None:
        if self.task is not None:
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass
        if self.connection is not None and not self.connection.is_closed:
            await self.connection.close()
        self.ready = False

    async def _run(self) -> None:
        while True:
            try:
                self.connection = await aio_pika.connect_robust(
                    self.settings.rabbitmq_url,
                    timeout=10,
                    reconnect_interval=5,
                    fail_fast=False,
                    client_properties={"connection_name": "oil-history-consumer"},
                )
                channel = await self.connection.channel()
                await channel.set_qos(prefetch_count=1)
                exchange = await channel.declare_exchange(
                    self.settings.rabbitmq_exchange,
                    ExchangeType.DIRECT,
                    durable=True,
                )
                queue = await channel.declare_queue(
                    self.settings.rabbitmq_queue,
                    durable=True,
                )
                await queue.bind(
                    exchange,
                    routing_key=self.settings.rabbitmq_routing_key,
                )
                await queue.consume(self._handle)
                self.ready = True
                logger.info(
                    "RabbitMQ consumer is ready",
                    extra={"queue": self.settings.rabbitmq_queue},
                )
                await asyncio.Future()
            except asyncio.CancelledError:
                raise
            except Exception:
                self.ready = False
                logger.exception("RabbitMQ consumer failed; reconnecting")
                await asyncio.sleep(5)

    async def _handle(self, message: AbstractIncomingMessage) -> None:
        try:
            event = ObservationEvent.model_validate_json(message.body)
        except ValidationError:
            logger.exception("rejecting invalid RabbitMQ event")
            await message.reject(requeue=False)
            return

        try:
            inserted, duplicates = await asyncio.to_thread(_persist_event, event)
        except Exception:
            logger.exception("failed to persist RabbitMQ event; requeueing")
            await message.nack(requeue=True)
            return

        await message.ack()
        logger.info(
            "RabbitMQ event persisted",
            extra={
                "message_id": message.message_id,
                "event_key": event.event_key,
                "inserted": inserted,
                "duplicates": duplicates,
            },
        )


def build_consumer(settings: Settings) -> PGMQConsumer | RabbitMQConsumer:
    if settings.queue_backend == "rabbitmq":
        return RabbitMQConsumer(settings)
    if settings.queue_backend == "postgres":
        return PGMQConsumer(settings)
    raise ValueError("QUEUE_BACKEND must be postgres or rabbitmq")
