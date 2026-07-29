import json
import logging
import signal
import time
from typing import Any

import pika
from pika.adapters.blocking_connection import BlockingChannel
from pika.spec import Basic, BasicProperties
from pydantic import ValidationError
from sqlalchemy.exc import SQLAlchemyError

from app.config import get_settings
from app.database import SessionLocal
from app.repository import create_measurement
from app.schemas import MeasurementEvent


logging.basicConfig(
    level=logging.INFO,
    format=(
        "%(asctime)s | %(levelname)s | "
        "%(name)s | %(message)s"
    ),
)
logger = logging.getLogger(__name__)

settings = get_settings()
_should_stop = False
_active_connection: pika.BlockingConnection | None = None
_active_channel: BlockingChannel | None = None


def declare_topology(channel: BlockingChannel) -> None:
    channel.exchange_declare(
        exchange=settings.rabbitmq_dead_letter_exchange,
        exchange_type="direct",
        durable=True,
    )
    channel.queue_declare(
        queue=settings.rabbitmq_dead_letter_queue,
        durable=True,
    )
    channel.queue_bind(
        exchange=settings.rabbitmq_dead_letter_exchange,
        queue=settings.rabbitmq_dead_letter_queue,
        routing_key=settings.rabbitmq_routing_key,
    )

    channel.exchange_declare(
        exchange=settings.rabbitmq_exchange,
        exchange_type="direct",
        durable=True,
    )
    channel.queue_declare(
        queue=settings.rabbitmq_queue,
        durable=True,
        arguments={
            "x-dead-letter-exchange": (
                settings.rabbitmq_dead_letter_exchange
            ),
            "x-dead-letter-routing-key": (
                settings.rabbitmq_routing_key
            ),
        },
    )
    channel.queue_bind(
        exchange=settings.rabbitmq_exchange,
        queue=settings.rabbitmq_queue,
        routing_key=settings.rabbitmq_routing_key,
    )


def process_message(
    channel: BlockingChannel,
    method: Basic.Deliver,
    properties: BasicProperties,
    body: bytes,
) -> None:
    message_id = properties.message_id or "unknown"

    try:
        raw_event: Any = json.loads(body.decode("utf-8"))
        event = MeasurementEvent.model_validate(raw_event)

    except (UnicodeDecodeError, json.JSONDecodeError, ValidationError):
        logger.exception(
            "Rejecting malformed measurement event %s",
            message_id,
        )
        channel.basic_reject(
            delivery_tag=method.delivery_tag,
            requeue=False,
        )
        return

    try:
        with SessionLocal() as db:
            measurement, created = create_measurement(
                db,
                event.payload,
            )

        logger.info(
            "Processed measurement event %s: city=%s, "
            "measurement_id=%s, created=%s",
            event.message_id,
            event.payload.city_code,
            measurement.id,
            created,
        )
        channel.basic_ack(delivery_tag=method.delivery_tag)

    except ValueError:
        logger.exception(
            "Rejecting measurement event %s with permanent data error",
            event.message_id,
        )
        channel.basic_reject(
            delivery_tag=method.delivery_tag,
            requeue=False,
        )

    except SQLAlchemyError:
        logger.exception(
            "Database failure while processing event %s; requeueing",
            event.message_id,
        )
        channel.basic_nack(
            delivery_tag=method.delivery_tag,
            requeue=True,
        )

    except Exception:
        logger.exception(
            "Unexpected failure while processing event %s; requeueing",
            event.message_id,
        )
        channel.basic_nack(
            delivery_tag=method.delivery_tag,
            requeue=True,
        )


def request_shutdown(*_: object) -> None:
    global _should_stop
    _should_stop = True

    connection = _active_connection
    channel = _active_channel

    if (
        connection is not None
        and connection.is_open
        and channel is not None
        and channel.is_open
    ):
        connection.add_callback_threadsafe(channel.stop_consuming)


def consume_forever() -> None:
    global _active_connection, _active_channel

    signal.signal(signal.SIGTERM, request_shutdown)
    signal.signal(signal.SIGINT, request_shutdown)

    while not _should_stop:
        try:
            logger.info("Connecting Backend consumer to RabbitMQ")
            connection = pika.BlockingConnection(
                pika.URLParameters(settings.rabbitmq_url)
            )
            _active_connection = connection
            channel = connection.channel()
            _active_channel = channel

            declare_topology(channel)
            channel.basic_qos(prefetch_count=1)
            channel.basic_consume(
                queue=settings.rabbitmq_queue,
                on_message_callback=process_message,
                auto_ack=False,
            )

            logger.info("Consuming queue %s", settings.rabbitmq_queue)
            channel.start_consuming()

        except pika.exceptions.AMQPError:
            if not _should_stop:
                logger.exception(
                    "RabbitMQ consumer connection failed; "
                    "retrying in 5 seconds"
                )
                time.sleep(5)
        finally:
            if (
                _active_connection is not None
                and _active_connection.is_open
            ):
                _active_connection.close()
            _active_channel = None
            _active_connection = None

    logger.info("Backend RabbitMQ consumer stopped")


if __name__ == "__main__":
    consume_forever()
