import asyncio
import json
import logging
from typing import Any

import aio_pika
from aio_pika import ExchangeType, IncomingMessage
from aio_pika.abc import (
    AbstractRobustChannel,
    AbstractRobustConnection,
    AbstractRobustQueue,
)
from pydantic import ValidationError
from sqlalchemy.exc import SQLAlchemyError

from app.config import Settings
from app.database import SessionLocal
from app.repository import create_measurement
from app.schemas import MeasurementEvent


logger = logging.getLogger(__name__)


class RabbitMQConsumer:
    """RabbitMQ consumer managed by the FastAPI application lifecycle."""

    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._task: asyncio.Task[None] | None = None
        self._stop_event = asyncio.Event()
        self._connected_event = asyncio.Event()
        self._connection: AbstractRobustConnection | None = None
        self._channel: AbstractRobustChannel | None = None
        self._queue: AbstractRobustQueue | None = None
        self._consumer_tag: str | None = None

    @property
    def enabled(self) -> bool:
        return self._settings.rabbitmq_consumer_enabled

    @property
    def is_connected(self) -> bool:
        connection = self._connection
        transport_connected = (
            connection is not None
            and not connection.is_closed
            and connection.connected.is_set()
        )
        return (
            self.enabled
            and self._connected_event.is_set()
            and transport_connected
        )

    async def start(self) -> None:
        """Start the consumer task without blocking FastAPI startup."""

        if not self.enabled:
            logger.warning("RabbitMQ consumer is disabled by configuration")
            return

        if self._task is not None and not self._task.done():
            return

        self._stop_event.clear()
        self._task = asyncio.create_task(
            self._run_forever(),
            name="rabbitmq-consumer",
        )
        logger.info("RabbitMQ consumer background task started")

    async def stop(self) -> None:
        """Stop consuming and close RabbitMQ resources cleanly."""

        self._stop_event.set()
        self._connected_event.clear()

        if self._queue is not None and self._consumer_tag is not None:
            try:
                await self._queue.cancel(self._consumer_tag)
            except Exception:
                logger.exception("Could not cancel RabbitMQ consumer cleanly")

        if self._channel is not None and not self._channel.is_closed:
            try:
                await self._channel.close()
            except Exception:
                logger.exception("Could not close RabbitMQ channel cleanly")

        if self._connection is not None and not self._connection.is_closed:
            try:
                await self._connection.close()
            except Exception:
                logger.exception("Could not close RabbitMQ connection cleanly")

        if self._task is not None:
            try:
                await asyncio.wait_for(self._task, timeout=10)
            except TimeoutError:
                logger.warning("RabbitMQ consumer did not stop in time; cancelling")
                self._task.cancel()
                await asyncio.gather(self._task, return_exceptions=True)
            except asyncio.CancelledError:
                pass

        self._task = None
        self._consumer_tag = None
        self._queue = None
        self._channel = None
        self._connection = None
        logger.info("RabbitMQ consumer stopped")

    async def _run_forever(self) -> None:
        """Connect, consume, and retry initial or unexpected failures."""

        while not self._stop_event.is_set():
            try:
                logger.info("Connecting Backend consumer to RabbitMQ")
                self._connection = await aio_pika.connect_robust(
                    self._settings.rabbitmq_url,
                    timeout=(
                        self._settings.rabbitmq_connection_timeout_seconds
                    ),
                    client_properties={
                        "connection_name": "airaware-backend-consumer",
                    },
                )
                self._channel = await self._connection.channel()
                await self._channel.set_qos(prefetch_count=1)
                self._queue = await self._declare_topology(self._channel)
                self._consumer_tag = await self._queue.consume(
                    self._process_message,
                    no_ack=False,
                )
                self._connected_event.set()

                logger.info(
                    "Consuming queue %s",
                    self._settings.rabbitmq_queue,
                )

                await self._stop_event.wait()

            except asyncio.CancelledError:
                raise
            except Exception:
                self._connected_event.clear()

                if not self._stop_event.is_set():
                    logger.exception(
                        "RabbitMQ consumer failed; retrying in %s seconds",
                        self._settings.rabbitmq_retry_delay_seconds,
                    )
                    await self._wait_before_retry()
            finally:
                self._connected_event.clear()

                if self._connection is not None and not self._connection.is_closed:
                    try:
                        await self._connection.close()
                    except Exception:
                        logger.exception(
                            "Could not close failed RabbitMQ connection"
                        )

                self._consumer_tag = None
                self._queue = None
                self._channel = None
                self._connection = None

    async def _wait_before_retry(self) -> None:
        try:
            await asyncio.wait_for(
                self._stop_event.wait(),
                timeout=self._settings.rabbitmq_retry_delay_seconds,
            )
        except TimeoutError:
            pass

    async def _declare_topology(
        self,
        channel: AbstractRobustChannel,
    ) -> AbstractRobustQueue:
        dead_letter_exchange = await channel.declare_exchange(
            self._settings.rabbitmq_dead_letter_exchange,
            ExchangeType.DIRECT,
            durable=True,
            robust=True,
        )
        dead_letter_queue = await channel.declare_queue(
            self._settings.rabbitmq_dead_letter_queue,
            durable=True,
            robust=True,
        )
        await dead_letter_queue.bind(
            dead_letter_exchange,
            routing_key=self._settings.rabbitmq_routing_key,
            robust=True,
        )

        exchange = await channel.declare_exchange(
            self._settings.rabbitmq_exchange,
            ExchangeType.DIRECT,
            durable=True,
            robust=True,
        )
        queue = await channel.declare_queue(
            self._settings.rabbitmq_queue,
            durable=True,
            arguments={
                "x-dead-letter-exchange": (
                    self._settings.rabbitmq_dead_letter_exchange
                ),
                "x-dead-letter-routing-key": (
                    self._settings.rabbitmq_routing_key
                ),
            },
            robust=True,
        )
        await queue.bind(
            exchange,
            routing_key=self._settings.rabbitmq_routing_key,
            robust=True,
        )
        return queue

    async def _process_message(self, message: IncomingMessage) -> None:
        message_id = message.message_id or "unknown"

        try:
            raw_event: Any = json.loads(message.body.decode("utf-8"))
            event = MeasurementEvent.model_validate(raw_event)
        except (UnicodeDecodeError, json.JSONDecodeError, ValidationError):
            logger.exception(
                "Rejecting malformed measurement event %s",
                message_id,
            )
            await message.reject(requeue=False)
            return

        try:
            measurement_id, created = await asyncio.to_thread(
                self._persist_event,
                event,
            )
        except ValueError:
            logger.exception(
                "Rejecting measurement event %s with permanent data error",
                event.message_id,
            )
            await message.reject(requeue=False)
            return
        except SQLAlchemyError:
            logger.exception(
                "Database failure while processing event %s; requeueing",
                event.message_id,
            )
            await message.nack(requeue=True)
            return
        except Exception:
            logger.exception(
                "Unexpected failure while processing event %s; requeueing",
                event.message_id,
            )
            await message.nack(requeue=True)
            return

        await message.ack()
        logger.info(
            "Processed measurement event %s: city=%s, "
            "measurement_id=%s, created=%s",
            event.message_id,
            event.payload.city_code,
            measurement_id,
            created,
        )

    @staticmethod
    def _persist_event(event: MeasurementEvent) -> tuple[int, bool]:
        with SessionLocal() as db:
            measurement, created = create_measurement(
                db,
                event.payload,
            )
            return measurement.id, created
