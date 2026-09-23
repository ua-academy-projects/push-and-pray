from __future__ import annotations

import asyncio
import json
import logging

import aio_pika
from aio_pika.abc import AbstractIncomingMessage, AbstractRobustChannel, AbstractRobustConnection
from pydantic import ValidationError

from .config import Settings
from .database import SessionLocal
from .repository import insert_batch
from .schemas import ObservationEvent

logger = logging.getLogger(__name__)


class RabbitMQConsumer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.connection: AbstractRobustConnection | None = None
        self.channel: AbstractRobustChannel | None = None
        self.consumer_tag: str | None = None

    @property
    def is_ready(self) -> bool:
        return bool(self.connection and not self.connection.is_closed and self.consumer_tag)

    async def start(self) -> None:
        self.connection = await aio_pika.connect_robust(self.settings.rabbitmq_url)
        self.channel = await self.connection.channel()
        await self.channel.set_qos(prefetch_count=1)

        dead_letter_exchange = await self.channel.declare_exchange(
            f"{self.settings.rabbitmq_queue}.dead-letter", durable=True
        )
        dead_letter_queue = await self.channel.declare_queue(
            f"{self.settings.rabbitmq_queue}.dead-letter", durable=True
        )
        await dead_letter_queue.bind(
            dead_letter_exchange,
            routing_key=self.settings.rabbitmq_queue,
        )

        queue = await self.channel.declare_queue(
            self.settings.rabbitmq_queue,
            durable=True,
            arguments={"x-dead-letter-exchange": dead_letter_exchange.name},
        )
        self.consumer_tag = await queue.consume(self._handle_message)

    async def stop(self) -> None:
        self.consumer_tag = None
        self.channel = None
        if self.connection is not None:
            await self.connection.close()
            self.connection = None

    async def _handle_message(self, message: AbstractIncomingMessage) -> None:
        try:
            event = ObservationEvent.model_validate(json.loads(message.body))
        except (json.JSONDecodeError, ValidationError):
            logger.exception("permanently invalid RabbitMQ message")
            await message.reject(requeue=False)
            return

        try:
            inserted, duplicates = await asyncio.to_thread(self._persist, event)
        except Exception:
            logger.exception("failed to persist RabbitMQ message")
            if message.redelivered:
                await message.reject(requeue=False)
            else:
                await message.nack(requeue=True)
            return

        await message.ack()
        logger.info(
            "RabbitMQ message persisted",
            extra={
                "event_key": event.event_key,
                "inserted": inserted,
                "duplicates": duplicates,
            },
        )

    @staticmethod
    def _persist(event: ObservationEvent) -> tuple[int, int]:
        with SessionLocal() as session:
            return insert_batch(session, event.observations)
