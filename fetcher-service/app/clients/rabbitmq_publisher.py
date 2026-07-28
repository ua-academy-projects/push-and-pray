import json
from typing import Any

import aio_pika

from app.config import Settings
from app.exceptions import MessageBrokerPublishError, MessageBrokerUnavailableError


class RabbitMQPublisher:
    """The only way a completed (or failed) sync reaches the Backend now -- a persistent
    message on a durable queue, published and forgotten, never a direct HTTP call. A
    short-lived connection per publish, mirroring BackendClient's per-request
    httpx.AsyncClient -- there's no long-running process here to own a persistent connection.

    Both queues carry a dead-letter route to `rabbitmq_dead_letter_exchange` so a message the
    Backend's consumer can never process (bad shape, persistent DB failure) lands on
    `<queue>.dead` once instead of being redelivered forever. The consumer side declares the
    same dead-letter arguments; whichever side connects first creates the queue, so the two
    declarations must stay identical or RabbitMQ will reject the mismatched one."""

    def __init__(self, settings: Settings):
        self._url = settings.rabbitmq_url
        self._sync_queue = settings.rabbitmq_sync_queue
        self._sync_failure_queue = settings.rabbitmq_sync_failure_queue
        self._dead_letter_exchange = settings.rabbitmq_dead_letter_exchange

    async def _publish(self, queue_name: str, payload: dict[str, Any]) -> None:
        try:
            connection = await aio_pika.connect_robust(self._url)
        except (aio_pika.exceptions.AMQPError, OSError) as exc:
            raise MessageBrokerUnavailableError(f"Could not connect to RabbitMQ for queue {queue_name}") from exc

        try:
            async with connection:
                channel = await connection.channel()
                await channel.declare_queue(
                    queue_name,
                    durable=True,
                    arguments={
                        "x-dead-letter-exchange": self._dead_letter_exchange,
                        "x-dead-letter-routing-key": queue_name,
                    },
                )
                message = aio_pika.Message(
                    body=json.dumps(payload).encode("utf-8"),
                    content_type="application/json",
                    delivery_mode=aio_pika.DeliveryMode.PERSISTENT,
                )
                await channel.default_exchange.publish(message, routing_key=queue_name)
        except aio_pika.exceptions.AMQPError as exc:
            raise MessageBrokerPublishError(f"Failed to publish to queue {queue_name}") from exc

    async def publish_weather_sync(self, payload: dict[str, Any]) -> None:
        await self._publish(self._sync_queue, payload)

    async def publish_sync_failure(self, payload: dict[str, Any]) -> None:
        await self._publish(self._sync_failure_queue, payload)
