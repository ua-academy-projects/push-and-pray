import asyncio
import json
import logging
from datetime import datetime, timezone
from uuid import uuid4

import pika
from pika.adapters.blocking_connection import BlockingChannel
from pika.exceptions import (
    AMQPError,
    NackError,
    UnroutableError,
)

from app.config import Settings
from app.schemas import AirQualityMeasurementCreate


logger = logging.getLogger(__name__)


class RabbitMQPublishError(Exception):
    """Raised when a measurement event cannot be published."""


class RabbitMQPublisher:
    """Publishes durable air-quality measurement events."""

    def __init__(self, settings: Settings) -> None:
        self._url = settings.rabbitmq_url
        self._exchange = settings.rabbitmq_exchange
        self._queue = settings.rabbitmq_queue
        self._routing_key = settings.rabbitmq_routing_key
        self._dead_letter_exchange = (
            settings.rabbitmq_dead_letter_exchange
        )
        self._dead_letter_queue = (
            settings.rabbitmq_dead_letter_queue
        )

    async def publish_measurement(
        self,
        measurement: AirQualityMeasurementCreate,
    ) -> str:
        """Publish one measurement event without blocking the event loop."""

        message_id = str(uuid4())

        event: dict[str, object] = {
            "schema_version": 1,
            "message_id": message_id,
            "event_type": (
                "air_quality.measurement.collected"
            ),
            "published_at": datetime.now(
                timezone.utc
            ).isoformat(),
            "payload": measurement.model_dump(
                mode="json"
            ),
        }

        await asyncio.to_thread(
            self._publish_sync,
            message_id,
            event,
            measurement.city_code,
        )

        return message_id

    async def is_ready(self) -> bool:
        """Return whether RabbitMQ is reachable and topology is valid."""

        try:
            return await asyncio.to_thread(
                self._check_sync
            )
        except RabbitMQPublishError:
            return False

    def _check_sync(self) -> bool:
        """Synchronously verify RabbitMQ connectivity."""

        connection: pika.BlockingConnection | None = None

        try:
            parameters = pika.URLParameters(self._url)

            connection = pika.BlockingConnection(
                parameters
            )

            channel = connection.channel()

            self._declare_topology(channel)

            return True

        except AMQPError as exc:
            logger.warning(
                "RabbitMQ readiness check failed: %s",
                exc,
            )

            raise RabbitMQPublishError(
                "Could not connect to RabbitMQ"
            ) from exc

        finally:
            if (
                connection is not None
                and connection.is_open
            ):
                connection.close()

    def _publish_sync(
        self,
        message_id: str,
        event: dict[str, object],
        city_code: str,
    ) -> None:
        """Synchronously publish and wait for broker confirmation."""

        connection: pika.BlockingConnection | None = None

        try:
            parameters = pika.URLParameters(self._url)

            connection = pika.BlockingConnection(
                parameters
            )

            channel = connection.channel()

            self._declare_topology(channel)

            # Enable RabbitMQ publisher acknowledgements.
            #
            # After this call, basic_publish() raises an exception
            # when RabbitMQ rejects or cannot route the message.
            channel.confirm_delivery()

            message_body = json.dumps(
                event,
                ensure_ascii=False,
                separators=(",", ":"),
            ).encode("utf-8")

            properties = pika.BasicProperties(
                content_type="application/json",
                content_encoding="utf-8",
                delivery_mode=(
                    pika.DeliveryMode.Persistent
                ),
                message_id=message_id,
                type=(
                    "air_quality.measurement.collected"
                ),
                app_id="airaware-fetcher",
                timestamp=int(
                    datetime.now(
                        timezone.utc
                    ).timestamp()
                ),
            )

            # Do not check a boolean return value here.
            #
            # In confirmation mode:
            # - success means this method returns normally;
            # - unroutable messages raise UnroutableError;
            # - broker NACKs raise NackError.
            channel.basic_publish(
                exchange=self._exchange,
                routing_key=self._routing_key,
                body=message_body,
                properties=properties,
                mandatory=True,
            )

            logger.info(
                (
                    "Published measurement event %s "
                    "for city %s"
                ),
                message_id,
                city_code,
            )

        except UnroutableError as exc:
            logger.error(
                (
                    "RabbitMQ could not route event %s "
                    "for city %s"
                ),
                message_id,
                city_code,
            )

            raise RabbitMQPublishError(
                (
                    "RabbitMQ could not route "
                    "the measurement event"
                )
            ) from exc

        except NackError as exc:
            logger.error(
                (
                    "RabbitMQ rejected event %s "
                    "for city %s"
                ),
                message_id,
                city_code,
            )

            raise RabbitMQPublishError(
                (
                    "RabbitMQ rejected "
                    "the measurement event"
                )
            ) from exc

        except AMQPError as exc:
            logger.exception(
                (
                    "RabbitMQ publishing failed for "
                    "event %s and city %s"
                ),
                message_id,
                city_code,
            )

            raise RabbitMQPublishError(
                (
                    "Could not publish "
                    "the measurement event"
                )
            ) from exc

        except (TypeError, ValueError) as exc:
            logger.exception(
                (
                    "Could not serialize event %s "
                    "for city %s"
                ),
                message_id,
                city_code,
            )

            raise RabbitMQPublishError(
                (
                    "Could not serialize "
                    "the measurement event"
                )
            ) from exc

        finally:
            if (
                connection is not None
                and connection.is_open
            ):
                connection.close()

    def _declare_topology(
        self,
        channel: BlockingChannel,
    ) -> None:
        """Declare durable exchanges, queues and bindings."""

        channel.exchange_declare(
            exchange=self._dead_letter_exchange,
            exchange_type="direct",
            durable=True,
        )

        channel.queue_declare(
            queue=self._dead_letter_queue,
            durable=True,
        )

        channel.queue_bind(
            exchange=self._dead_letter_exchange,
            queue=self._dead_letter_queue,
            routing_key=self._routing_key,
        )

        channel.exchange_declare(
            exchange=self._exchange,
            exchange_type="direct",
            durable=True,
        )

        channel.queue_declare(
            queue=self._queue,
            durable=True,
            arguments={
                "x-dead-letter-exchange": (
                    self._dead_letter_exchange
                ),
                "x-dead-letter-routing-key": (
                    self._routing_key
                ),
            },
        )

        channel.queue_bind(
            exchange=self._exchange,
            queue=self._queue,
            routing_key=self._routing_key,
        )
