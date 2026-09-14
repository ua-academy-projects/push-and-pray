from __future__ import annotations

import asyncio
import logging
from typing import Any

import aio_pika
from pydantic import ValidationError
from sqlalchemy import text

from .config import Settings
from .database import SessionLocal
from .repository import insert_batch
from .schemas import ObservationEvent

logger = logging.getLogger(__name__)


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
            event = ObservationEvent.model_validate(message)

        except ValidationError as exc:
            logger.error(
                "permanently invalid PGMQ message",
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


class RabbitMQConsumer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.connection: aio_pika.abc.AbstractRobustConnection | None = None
        self.task: asyncio.Task[None] | None = None
        self.ready = False

    @property
    def is_ready(self) -> bool:
        return bool(self.ready and self.task is not None and not self.task.done())

    async def start(self) -> None:
        self.connection = await aio_pika.connect_robust(
            host=self.settings.rabbitmq_host,
            port=self.settings.rabbitmq_port,
            login=self.settings.rabbitmq_user,
            password=self.settings.rabbitmq_password,
            virtualhost=self.settings.rabbitmq_vhost,
        )
        channel = await self.connection.channel()
        await channel.set_qos(prefetch_count=1)
        queue = await channel.declare_queue(
            self.settings.rabbitmq_queue,
            durable=True,
        )
        self.ready = True
        self.task = asyncio.create_task(self._run(queue), name="rabbitmq-history-consumer")

    async def stop(self) -> None:
        self.ready = False
        if self.task is not None:
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass
        if self.connection is not None:
            await self.connection.close()

    async def _run(self, queue: aio_pika.abc.AbstractQueue) -> None:
        async with queue.iterator() as iterator:
            async for message in iterator:
                await self._handle_message(message)

    async def _handle_message(
        self,
        message: aio_pika.abc.AbstractIncomingMessage,
    ) -> None:
        try:
            event = ObservationEvent.model_validate_json(message.body)
        except ValidationError:
            logger.exception("rejecting invalid RabbitMQ message")
            await message.reject(requeue=False)
            return

        try:
            await asyncio.to_thread(self._persist, event)
        except Exception:
            logger.exception("RabbitMQ persistence failed; requeueing message")
            await message.nack(requeue=True)
            return

        await message.ack()

    @staticmethod
    def _persist(event: ObservationEvent) -> None:
        with SessionLocal() as session:
            insert_batch(session, event.observations)
