from __future__ import annotations

import asyncio
import logging
import ssl

import aio_pika
from pydantic import ValidationError
from sqlalchemy import text

from .config import Settings
from .database import SessionLocal
from .repository import insert_batch
from .schemas import ObservationEvent

logger = logging.getLogger(__name__)


class RabbitMQConsumer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.task: asyncio.Task | None = None
        self.ready = False

    @property
    def is_ready(self) -> bool:
        return bool(self.ready and self.task and not self.task.done())

    async def start(self) -> None:
        self.task = asyncio.create_task(self._run(), name="rabbitmq-history-consumer")

    async def stop(self) -> None:
        self.ready = False
        if self.task:
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass

    def _persist(self, event: ObservationEvent) -> None:
        with SessionLocal() as session:
            session.execute(
                text("SELECT set_config('statement_timeout', :timeout, true)"),
                {"timeout": str(int(self.settings.rabbitmq_timeout_seconds * 1000))},
            )
            insert_batch(session, event.observations)  # Commits before returning.

    async def _handle(self, message, channel) -> None:
        destination = None
        attempts = 0
        try:
            attempts = int((message.headers or {}).get("attempts", 0))
            if attempts < 0:
                raise ValueError("invalid attempts")
            event = ObservationEvent.model_validate_json(message.body)
        except (ValidationError, ValueError, TypeError):
            destination = self.settings.rabbitmq_queue + ".dead"
        else:
            try:
                await asyncio.to_thread(self._persist, event)
            except Exception:
                logger.warning("Database insert failed; retaining message for retry")
                destination = self.settings.rabbitmq_queue + (
                    ".dead" if attempts + 1 >= self.settings.rabbitmq_max_attempts else ".retry"
                )
        if destination:
            # Confirm the durable retry/DLQ copy before acknowledging the original.
            await channel.default_exchange.publish(
                aio_pika.Message(
                    body=message.body,
                    content_type="application/json",
                    delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
                    headers={"attempts": attempts + 1},
                ),
                routing_key=destination,
                mandatory=True,
                timeout=self.settings.rabbitmq_timeout_seconds,
            )
        await message.ack()

    async def _run(self) -> None:
        context = ssl.create_default_context(cafile=self.settings.rabbitmq_ca_file)
        while True:
            try:
                connection = await aio_pika.connect(
                    self.settings.rabbitmq_url,
                    ssl_context=context,
                    timeout=self.settings.rabbitmq_timeout_seconds,
                )
                async with connection:
                    channel = await connection.channel(
                        publisher_confirms=True, on_return_raises=True
                    )
                    await channel.set_qos(prefetch_count=1)
                    queue = await channel.get_queue(self.settings.rabbitmq_queue, ensure=True)
                    async with queue.iterator() as messages:
                        self.ready = True
                        async for message in messages:
                            await self._handle(message, channel)
            except asyncio.CancelledError:
                raise
            except Exception:
                # Closing the connection requeues an unacknowledged original.
                logger.warning("RabbitMQ consumer disconnected; reconnecting")
            finally:
                self.ready = False
            await asyncio.sleep(self.settings.rabbitmq_reconnect_seconds)
