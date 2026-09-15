from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

import aio_pika
from aio_pika.abc import AbstractChannel, AbstractIncomingMessage, AbstractQueue
from pydantic import ValidationError
from sqlalchemy import text

from .config import Settings
from .database import SessionLocal
from .repository import insert_batch
from .schemas import ObservationEvent

logger = logging.getLogger(__name__)


class InvalidEvent(ValueError):
    """A message that can never be persisted, however often it is retried."""


def persist_event(message: dict[str, Any]) -> tuple[ObservationEvent, int, int]:
    """Validate one event and store its observations.

    Raises InvalidEvent for a message the schema rejects. Any other exception
    is a transient failure the caller may retry.
    """
    try:
        event = ObservationEvent.model_validate(message)
    except ValidationError as exc:
        raise InvalidEvent(str(exc)) from exc

    with SessionLocal() as session:
        inserted, duplicates = insert_batch(session, event.observations)

    return event, inserted, duplicates


def create_consumer(settings: Settings) -> PGMQConsumer | AMQPConsumer:
    if settings.queue_backend == "amqp":
        return AMQPConsumer(settings)

    return PGMQConsumer(settings)


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
            "PGMQ consumer started",
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
                logger.exception("PGMQ consumer failed; retrying")

                await asyncio.sleep(self.settings.pgmq_poll_interval_seconds)

    def _process_next_message(self) -> bool:
        with SessionLocal() as session:
            result = session.execute(
                text(
                    """
                    SELECT *
                    FROM pgmq.read(
                        queue_name => :queue_name,
                        vt => :visibility_timeout,
                        qty => 1
                    )
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
            event, inserted, duplicates = persist_event(message)

        except InvalidEvent as exc:
            logger.error(
                "permanently invalid PGMQ message",
                extra={
                    "msg_id": msg_id,
                    "error": str(exc),
                },
            )

            self._archive_message(msg_id)

            return

        except Exception:
            logger.exception(
                "failed to persist PGMQ message",
                extra={
                    "msg_id": msg_id,
                    "read_count": read_count,
                },
            )

            if read_count >= self.settings.pgmq_max_attempts:
                logger.error(
                    "PGMQ message exceeded retry limit",
                    extra={
                        "msg_id": msg_id,
                        "read_count": read_count,
                    },
                )

                self._archive_message(msg_id)

            return

        self._archive_message(msg_id)

        logger.info(
            "PGMQ message persisted",
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
                    SELECT pgmq.archive(
                        queue_name => :queue_name,
                        msg_id => :msg_id
                    )
                    """
                ),
                {
                    "queue_name": self.settings.pgmq_queue,
                    "msg_id": msg_id,
                },
            ).scalar_one()

            session.commit()

            if not archived:
                raise RuntimeError(f"failed to archive PGMQ message {msg_id}")


async def declare_topology(channel: AbstractChannel, settings: Settings) -> AbstractQueue:
    """Declare the exchange, the queue and its dead-letter pair.

    The history service owns the consumer side of the topology; the fetcher
    only declares the exchange and publishes with the mandatory flag, so an
    event with no queue to land in fails there instead of vanishing.

    The queue is a quorum queue with a delivery limit: RabbitMQ counts how
    often a message came back, and dead-letters it once the limit is exceeded.
    That is the broker's equivalent of PGMQ's read count and archive table.
    """
    exchange = await channel.declare_exchange(
        settings.amqp_exchange,
        aio_pika.ExchangeType.TOPIC,
        durable=True,
    )

    dead_exchange = await channel.declare_exchange(
        f"{settings.amqp_exchange}.dead",
        aio_pika.ExchangeType.FANOUT,
        durable=True,
    )

    dead_queue = await channel.declare_queue(
        f"{settings.amqp_queue}.dead",
        durable=True,
        arguments={"x-queue-type": "quorum"},
    )

    await dead_queue.bind(dead_exchange)

    queue = await channel.declare_queue(
        settings.amqp_queue,
        durable=True,
        arguments={
            "x-queue-type": "quorum",
            "x-delivery-limit": settings.amqp_max_attempts,
            "x-dead-letter-exchange": dead_exchange.name,
        },
    )

    await queue.bind(exchange, settings.amqp_routing_key)

    return queue


def delivery_attempt(message: AbstractIncomingMessage) -> int:
    """How many times the broker has handed this message out, this one included."""
    headers = message.headers or {}

    try:
        return int(headers.get("x-delivery-count", 0)) + 1
    except (TypeError, ValueError):
        return 1


class AMQPConsumer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.task: asyncio.Task[None] | None = None
        self.ready = False
        self.connected = False

    @property
    def is_ready(self) -> bool:
        return bool(
            self.ready and self.connected and self.task is not None and not self.task.done()
        )

    async def start(self) -> None:
        self.ready = True

        self.task = asyncio.create_task(
            self._run(),
            name="amqp-history-consumer",
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
        while True:
            try:
                await self._consume()

            except asyncio.CancelledError:
                raise

            except Exception:
                self.connected = False

                logger.exception("AMQP consumer failed; reconnecting")

                await asyncio.sleep(self.settings.amqp_reconnect_delay_seconds)

    async def _consume(self) -> None:
        connection = await aio_pika.connect_robust(self.settings.amqp_url)

        async with connection:
            channel = await connection.channel()

            await channel.set_qos(prefetch_count=self.settings.amqp_prefetch_count)

            queue = await declare_topology(channel, self.settings)

            self.connected = True

            logger.info(
                "AMQP consumer started",
                extra={
                    "exchange": self.settings.amqp_exchange,
                    "queue": self.settings.amqp_queue,
                },
            )

            async with queue.iterator() as messages:
                async for message in messages:
                    await self._handle_message(message)

    async def _handle_message(self, message: AbstractIncomingMessage) -> None:
        attempt = delivery_attempt(message)

        try:
            body = json.loads(message.body)

            if not isinstance(body, dict):
                raise InvalidEvent("message body is not a JSON object")

            event, inserted, duplicates = await asyncio.to_thread(persist_event, body)

        except (InvalidEvent, ValueError) as exc:
            logger.error(
                "permanently invalid AMQP message",
                extra={
                    "message_id": message.message_id,
                    "error": str(exc),
                },
            )

            # Rejected without requeue, so the broker dead-letters it.
            await message.reject(requeue=False)

            return

        except Exception:
            logger.exception(
                "failed to persist AMQP message",
                extra={
                    "message_id": message.message_id,
                    "attempt": attempt,
                },
            )

            # Back on the queue; the delivery limit dead-letters it once it
            # has been returned amqp_max_attempts times. The pause keeps a
            # persistent failure from spinning at prefetch speed.
            await message.nack(requeue=True)

            await asyncio.sleep(self.settings.amqp_retry_delay_seconds)

            return

        await message.ack()

        logger.info(
            "AMQP message persisted",
            extra={
                "message_id": message.message_id,
                "attempt": attempt,
                "event_key": event.event_key,
                "inserted": inserted,
                "duplicates": duplicates,
            },
        )
