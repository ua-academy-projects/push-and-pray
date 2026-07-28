import asyncio
import logging

import aio_pika
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.database.session import SessionLocal
from app.schemas.persistence import WeatherUpsertRequest
from app.schemas.sync import SyncFailureRequest
from app.services import persistence_service

logger = logging.getLogger(__name__)


def handle_weather_sync_message(body: bytes, db: Session) -> None:
    """Pure decode-and-persist step, kept separate from the aio-pika plumbing below so it can
    be unit-tested directly against a real test-database session, the same way the old
    PUT /internal/weather/sync handler was."""
    payload = WeatherUpsertRequest.model_validate_json(body)
    persistence_service.upsert_weather(db, payload)


def handle_sync_failure_message(body: bytes, db: Session) -> None:
    payload = SyncFailureRequest.model_validate_json(body)
    persistence_service.record_sync_failure(db, payload)


def _process_sync(body: bytes) -> None:
    db = SessionLocal()
    try:
        handle_weather_sync_message(body, db)
    finally:
        db.close()


def _process_sync_failure(body: bytes) -> None:
    db = SessionLocal()
    try:
        handle_sync_failure_message(body, db)
    finally:
        db.close()


async def _consume_queue(channel: aio_pika.abc.AbstractChannel, settings: Settings, queue_name: str, processor) -> None:
    """Declares `queue_name` durable with a dead-letter route, then consumes it forever. A
    message is acked only once `processor` -- a blocking, synchronous DB call run off the
    event loop via asyncio.to_thread -- returns without raising. Any failure (invalid JSON, a
    schema mismatch, a rolled-back persistence error) nacks without requeueing, so a message
    that can never succeed lands on `<queue_name>.dead` once instead of looping forever."""
    queue = await channel.declare_queue(
        queue_name,
        durable=True,
        arguments={
            "x-dead-letter-exchange": settings.rabbitmq_dead_letter_exchange,
            "x-dead-letter-routing-key": queue_name,
        },
    )
    async with queue.iterator() as queue_iter:
        async for message in queue_iter:
            try:
                async with message.process(requeue=False):
                    await asyncio.to_thread(processor, message.body)
                logger.info("consumed message from %s", queue_name)
            except Exception:
                logger.exception("failed to process message from %s -- dead-lettered", queue_name)


async def consume_forever(settings: Settings | None = None) -> None:
    settings = settings or get_settings()
    connection = await aio_pika.connect_robust(settings.rabbitmq_url)
    async with connection:
        channel = await connection.channel()
        await channel.set_qos(prefetch_count=settings.rabbitmq_prefetch_count)

        dlx = await channel.declare_exchange(
            settings.rabbitmq_dead_letter_exchange, aio_pika.ExchangeType.DIRECT, durable=True
        )
        for queue_name in (settings.rabbitmq_sync_queue, settings.rabbitmq_sync_failure_queue):
            dead_queue = await channel.declare_queue(f"{queue_name}.dead", durable=True)
            await dead_queue.bind(dlx, routing_key=queue_name)

        logger.info(
            "consumer started: queues=%s, %s", settings.rabbitmq_sync_queue, settings.rabbitmq_sync_failure_queue
        )
        await asyncio.gather(
            _consume_queue(channel, settings, settings.rabbitmq_sync_queue, _process_sync),
            _consume_queue(channel, settings, settings.rabbitmq_sync_failure_queue, _process_sync_failure),
        )
