from __future__ import annotations

import asyncio
import logging

import aio_pika
from aio_pika import ExchangeType
from aio_pika.abc import AbstractIncomingMessage, AbstractRobustConnection
from pydantic import ValidationError

from .config import Settings
from .database import SessionLocal
from .repository import insert_batch
from .schemas import ObservationEvent

logger = logging.getLogger(__name__)


def _persist_event(event: ObservationEvent) -> tuple[int, int]:
    with SessionLocal() as session:
        return insert_batch(session, event.observations)


class RabbitConsumer:
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
                await queue.bind(exchange, routing_key=self.settings.rabbitmq_routing_key)
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
            logger.exception("rejecting invalid price observation event")
            await message.reject(requeue=False)
            return

        try:
            inserted, duplicates = await asyncio.to_thread(_persist_event, event)
        except Exception:
            logger.exception("failed to persist event; returning it to RabbitMQ")
            await message.nack(requeue=True)
            return

        await message.ack()
        logger.info(
            "price observation event persisted",
            extra={
                "message_id": message.message_id,
                "inserted": inserted,
                "duplicates": duplicates,
            },
        )
