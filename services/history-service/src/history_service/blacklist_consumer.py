"""Standalone RabbitMQ consumer for complete blacklist snapshots."""

import asyncio
import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Protocol, cast
from uuid import UUID

import aio_pika
from aio_pika import DeliveryMode, ExchangeType, Message
from aio_pika.abc import (
    AbstractExchange,
    AbstractIncomingMessage,
    AbstractRobustConnection,
)
from pamqp.commands import Basic
from pydantic import ValidationError
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session, sessionmaker

from history_service.blacklist_ingestion import (
    BlacklistIngestionService,
    get_blacklist_ingestion_service,
)
from history_service.config import Settings
from history_service.database import get_session_factory
from history_service.exceptions import ApplicationError
from history_service.schemas import (
    BlacklistSnapshotDelivery,
    BlacklistSnapshotMessage,
)
from history_service.service import HistoryUnavailableError

RobustConnector = Callable[..., Awaitable[AbstractRobustConnection]]
SessionFactory = Callable[[], Session]
RETRY_ATTEMPT_HEADER = "x-aegis-retry-attempt"
DEAD_LETTER_ROUTING_KEY = "blacklist.snapshot.dead"
logger = logging.getLogger(__name__)


def message_context(message: AbstractIncomingMessage | Message) -> dict[str, object]:
    """Return bounded message metadata safe for structured logs."""
    headers = getattr(message, "headers", None) or {}
    return {
        "delivery_id": getattr(message, "message_id", None),
        "correlation_id": getattr(message, "correlation_id", None),
        "message_type": getattr(message, "type", None),
        "retry_attempt": headers.get(RETRY_ATTEMPT_HEADER, 0),
        "redelivered": getattr(message, "redelivered", False),
    }


class RetryableBlacklistProcessingError(Exception):
    """Explicitly retryable internal processing failure."""


@dataclass(frozen=True)
class RetryPolicy:
    """Bounded delayed retry tiers in seconds."""

    delays: tuple[int, ...] = (300, 900, 1800, 3600)

    def delay_for_attempt(self, attempt: int) -> int | None:
        return self.delays[attempt] if 0 <= attempt < len(self.delays) else None


class MessageFailureStrategy(Protocol):
    """Disposition decisions kept separate from validation and persistence."""

    async def permanent(self, message: AbstractIncomingMessage) -> None: ...

    async def temporary(self, message: AbstractIncomingMessage) -> None: ...


class RejectWithoutRequeue:
    """Avoid hot loops until bounded retry queues are introduced."""

    async def permanent(self, message: AbstractIncomingMessage) -> None:
        await message.reject(requeue=False)

    async def temporary(self, message: AbstractIncomingMessage) -> None:
        await message.nack(requeue=False)


class RabbitMQFailureStrategy:
    """Republish failures durably before acknowledging the original."""

    def __init__(
        self,
        settings: Settings,
        *,
        policy: RetryPolicy | None = None,
    ) -> None:
        self._settings = settings
        self._policy = policy or RetryPolicy()
        self._retry_exchange: AbstractExchange | None = None
        self._dead_letter_exchange: AbstractExchange | None = None

    def configure(
        self,
        *,
        retry_exchange: AbstractExchange,
        dead_letter_exchange: AbstractExchange,
    ) -> None:
        self._retry_exchange = retry_exchange
        self._dead_letter_exchange = dead_letter_exchange

    @property
    def retry_delays(self) -> tuple[int, ...]:
        return self._policy.delays

    async def permanent(self, message: AbstractIncomingMessage) -> None:
        confirmed = await self._publish_dead_letter(message)
        if confirmed:
            await message.ack()
            logger.warning(
                "history_blacklist_message_dead_lettered",
                extra=message_context(message),
            )
        else:
            logger.error(
                "history_blacklist_dead_letter_handoff_failed",
                extra=message_context(message),
            )

    async def temporary(self, message: AbstractIncomingMessage) -> None:
        attempt = BlacklistMessageHandler.retry_attempt(message)
        delay = self._policy.delay_for_attempt(attempt)
        if delay is None:
            confirmed = await self._publish_dead_letter(message)
            if confirmed:
                await message.ack()
                logger.warning(
                    "history_blacklist_message_retry_exhausted",
                    extra=message_context(message),
                )
            else:
                logger.error(
                    "history_blacklist_dead_letter_handoff_failed",
                    extra=message_context(message),
                )
            return
        confirmed = await self._publish_retry(message, attempt=attempt + 1, delay=delay)
        if confirmed:
            await message.ack()
            logger.warning(
                "history_blacklist_message_retry_scheduled",
                extra={
                    **message_context(message),
                    "next_retry_attempt": attempt + 1,
                    "retry_delay_seconds": delay,
                },
            )
        else:
            logger.error(
                "history_blacklist_retry_handoff_failed",
                extra={
                    **message_context(message),
                    "next_retry_attempt": attempt + 1,
                    "retry_delay_seconds": delay,
                },
            )

    async def _publish_retry(
        self,
        message: AbstractIncomingMessage,
        *,
        attempt: int,
        delay: int,
    ) -> bool:
        exchange = self._retry_exchange
        if exchange is None:
            return False
        outgoing = self._copy_message(
            message,
            headers={**message.headers, RETRY_ATTEMPT_HEADER: attempt},
        )
        return await self._publish_confirmed(
            exchange,
            outgoing,
            routing_key=self.retry_routing_key(delay),
        )

    async def _publish_dead_letter(self, message: AbstractIncomingMessage) -> bool:
        exchange = self._dead_letter_exchange
        if exchange is None:
            return False
        outgoing = self._copy_message(message, headers=dict(message.headers))
        return await self._publish_confirmed(
            exchange,
            outgoing,
            routing_key=DEAD_LETTER_ROUTING_KEY,
        )

    async def _publish_confirmed(
        self,
        exchange: AbstractExchange,
        message: Message,
        *,
        routing_key: str,
    ) -> bool:
        try:
            async with asyncio.timeout(self._settings.rabbitmq_publish_timeout_seconds):
                confirmation = await exchange.publish(
                    message,
                    routing_key=routing_key,
                    mandatory=True,
                    timeout=self._settings.rabbitmq_publish_timeout_seconds,
                )
        except Exception:
            logger.exception(
                "history_blacklist_failure_handoff_publish_failed",
                extra={
                    **message_context(message),
                    "routing_key": routing_key,
                },
            )
            return False
        confirmed = isinstance(confirmation, Basic.Ack)
        if not confirmed:
            logger.error(
                "history_blacklist_failure_handoff_not_confirmed",
                extra={
                    **message_context(message),
                    "routing_key": routing_key,
                    "confirmation_type": type(confirmation).__name__,
                },
            )
        return confirmed

    @staticmethod
    def _copy_message(
        message: AbstractIncomingMessage,
        *,
        headers: dict[str, Any],
    ) -> Message:
        return Message(
            message.body,
            headers=headers,
            content_type=message.content_type,
            content_encoding=message.content_encoding,
            delivery_mode=DeliveryMode.PERSISTENT,
            correlation_id=message.correlation_id,
            message_id=message.message_id,
            timestamp=message.timestamp,
            type=message.type,
            app_id=message.app_id,
        )

    @staticmethod
    def retry_routing_key(delay: int) -> str:
        return f"blacklist.snapshot.retry.{delay}"


class BlacklistMessageHandler:
    """Validate one message and delegate transactional persistence."""

    def __init__(
        self,
        *,
        session_factory: SessionFactory,
        ingestion_service: BlacklistIngestionService,
        failure_strategy: MessageFailureStrategy | None = None,
        run_sync: Callable[[Callable[[], object]], Awaitable[object]] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._ingestion_service = ingestion_service
        self._failure_strategy = failure_strategy or RejectWithoutRequeue()
        self._run_sync = run_sync or asyncio.to_thread

    def set_failure_strategy(self, strategy: MessageFailureStrategy) -> None:
        self._failure_strategy = strategy

    async def handle(self, message: AbstractIncomingMessage) -> None:
        try:
            envelope = self._validate_message(message)
        except ValueError, ValidationError, UnicodeDecodeError:
            logger.exception(
                "history_blacklist_message_validation_failed",
                extra=message_context(message),
            )
            await self._failure_strategy.permanent(message)
            return

        delivery = BlacklistSnapshotDelivery(
            delivery_id=envelope.delivery_id,
            snapshot=envelope.snapshot,
        )
        try:
            result = await self._run_sync(lambda: self._ingest(delivery))
        except (
            HistoryUnavailableError,
            OperationalError,
            RetryableBlacklistProcessingError,
        ):
            logger.exception(
                "history_blacklist_message_temporary_failure",
                extra=message_context(message),
            )
            await self._failure_strategy.temporary(message)
            return
        except ApplicationError:
            logger.exception(
                "history_blacklist_message_permanent_failure",
                extra=message_context(message),
            )
            await self._failure_strategy.permanent(message)
            return
        except Exception:
            logger.exception(
                "history_blacklist_message_unexpected_failure",
                extra=message_context(message),
            )
            await self._failure_strategy.permanent(message)
            return
        logger.info(
            "history_blacklist_message_committed",
            extra={
                **message_context(message),
                "duplicate": getattr(result, "created", None) is False,
                "snapshot_id": getattr(
                    getattr(result, "snapshot", None), "snapshot_id", None
                ),
            },
        )
        await message.ack()
        logger.info(
            "history_blacklist_message_acked delivery_id=%s",
            message.message_id,
            extra=message_context(message),
        )

    def _ingest(self, delivery: BlacklistSnapshotDelivery) -> object:
        session = self._session_factory()
        try:
            return self._ingestion_service.ingest(session, delivery)
        finally:
            session.close()

    @staticmethod
    def _validate_message(
        message: AbstractIncomingMessage,
    ) -> BlacklistSnapshotMessage:
        if message.content_type != "application/json":
            raise ValueError("Unexpected content type.")
        if message.content_encoding is None or (
            message.content_encoding.lower() != "utf-8"
        ):
            raise ValueError("Unexpected content encoding.")
        if message.delivery_mode != DeliveryMode.PERSISTENT:
            raise ValueError("Blacklist messages must be persistent.")
        BlacklistMessageHandler.retry_attempt(message)

        envelope = BlacklistSnapshotMessage.model_validate_json(message.body)
        BlacklistMessageHandler._require_matching_uuid(
            message.message_id, envelope.delivery_id, "message_id"
        )
        BlacklistMessageHandler._require_matching_uuid(
            message.correlation_id, envelope.correlation_id, "correlation_id"
        )
        BlacklistMessageHandler._require_matching_text(
            message.type, envelope.message_type, "type"
        )
        BlacklistMessageHandler._require_matching_text(
            message.app_id, envelope.producer, "app_id"
        )
        if not isinstance(message.timestamp, datetime):
            raise ValueError("AMQP timestamp is required.")
        timestamp = message.timestamp
        if timestamp.tzinfo is None or timestamp.utcoffset() is None:
            raise ValueError("AMQP timestamp must be timezone-aware.")
        if timestamp.replace(microsecond=0) != envelope.created_at.replace(
            microsecond=0
        ):
            raise ValueError("AMQP timestamp does not match the message.")
        return envelope

    @staticmethod
    def retry_attempt(message: AbstractIncomingMessage) -> int:
        value = (message.headers or {}).get(RETRY_ATTEMPT_HEADER, 0)
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ValueError("Invalid retry attempt metadata.")
        return value

    @staticmethod
    def _require_matching_uuid(value: str | None, expected: UUID, field: str) -> None:
        if value is None:
            raise ValueError(f"AMQP {field} is required.")
        try:
            parsed = UUID(value)
        except ValueError:
            raise ValueError(f"Invalid AMQP {field}.") from None
        if parsed != expected:
            raise ValueError(f"AMQP {field} does not match the message.")

    @staticmethod
    def _require_matching_text(value: str | None, expected: str, field: str) -> None:
        if value is None:
            raise ValueError(f"AMQP {field} is required.")
        if value != expected:
            raise ValueError(f"AMQP {field} does not match the message.")


class HistoryBlacklistConsumer:
    """Own RabbitMQ topology, consumption, and graceful process shutdown."""

    def __init__(
        self,
        settings: Settings,
        handler: BlacklistMessageHandler,
        *,
        connector: RobustConnector = aio_pika.connect_robust,
        failure_strategy: RabbitMQFailureStrategy | None = None,
    ) -> None:
        self._settings = settings
        self._handler = handler
        self._connector = connector
        self._failure_strategy = failure_strategy or RabbitMQFailureStrategy(settings)
        self._handler.set_failure_strategy(self._failure_strategy)
        self._inflight: set[asyncio.Task[object]] = set()
        self.ready = asyncio.Event()
        self._connection: AbstractRobustConnection | None = None

    @property
    def is_ready(self) -> bool:
        return (
            self.ready.is_set()
            and self._connection is not None
            and not self._connection.is_closed
        )

    async def run(self, stop_event: asyncio.Event) -> None:
        connection: AbstractRobustConnection | None = None
        logger.info(
            "history_blacklist_consumer_starting",
            extra={
                "rabbitmq_host": self._settings.rabbitmq_host,
                "rabbitmq_port": self._settings.rabbitmq_port,
                "rabbitmq_virtual_host": self._settings.rabbitmq_virtual_host,
                "rabbitmq_exchange": self._settings.rabbitmq_exchange_name,
                "rabbitmq_queue": self._settings.rabbitmq_queue_name,
                "rabbitmq_routing_key": self._settings.rabbitmq_routing_key,
                "prefetch_count": self._settings.rabbitmq_prefetch_count,
            },
        )
        try:
            async with asyncio.timeout(
                self._settings.rabbitmq_connection_timeout_seconds
            ):
                connection = await self._connector(
                    host=self._settings.rabbitmq_host,
                    port=self._settings.rabbitmq_port,
                    login=self._settings.rabbitmq_username,
                    password=self._settings.rabbitmq_password.get_secret_value(),
                    virtualhost=self._settings.rabbitmq_virtual_host,
                    timeout=self._settings.rabbitmq_connection_timeout_seconds,
                )
                self._connection = connection
                channel = await connection.channel(
                    publisher_confirms=True,
                    on_return_raises=True,
                )
                await channel.set_qos(
                    prefetch_count=self._settings.rabbitmq_prefetch_count
                )
                exchange = await channel.declare_exchange(
                    self._settings.rabbitmq_exchange_name,
                    ExchangeType.DIRECT,
                    durable=True,
                    auto_delete=False,
                )
                retry_exchange = await channel.declare_exchange(
                    self._settings.rabbitmq_retry_exchange_name,
                    ExchangeType.DIRECT,
                    durable=True,
                    auto_delete=False,
                )
                dead_letter_exchange = await channel.declare_exchange(
                    self._settings.rabbitmq_dead_letter_exchange_name,
                    ExchangeType.DIRECT,
                    durable=True,
                    auto_delete=False,
                )
                queue = await channel.declare_queue(
                    self._settings.rabbitmq_queue_name,
                    durable=True,
                    exclusive=False,
                    auto_delete=False,
                )
                await queue.bind(
                    exchange,
                    routing_key=self._settings.rabbitmq_routing_key,
                )
                for delay in self._failure_strategy.retry_delays:
                    retry_queue = await channel.declare_queue(
                        f"{self._settings.rabbitmq_queue_name}.retry.{delay}",
                        durable=True,
                        exclusive=False,
                        auto_delete=False,
                        arguments={
                            "x-message-ttl": delay * 1000,
                            "x-dead-letter-exchange": (
                                self._settings.rabbitmq_exchange_name
                            ),
                            "x-dead-letter-routing-key": (
                                self._settings.rabbitmq_routing_key
                            ),
                        },
                    )
                    await retry_queue.bind(
                        retry_exchange,
                        routing_key=self._failure_strategy.retry_routing_key(delay),
                    )
                dead_letter_queue = await channel.declare_queue(
                    self._settings.rabbitmq_dead_letter_queue_name,
                    durable=True,
                    exclusive=False,
                    auto_delete=False,
                )
                await dead_letter_queue.bind(
                    dead_letter_exchange,
                    routing_key=DEAD_LETTER_ROUTING_KEY,
                )
                self._failure_strategy.configure(
                    retry_exchange=retry_exchange,
                    dead_letter_exchange=dead_letter_exchange,
                )
                consumer_tag = await queue.consume(self._on_message, no_ack=False)
                self.ready.set()
                logger.info(
                    "history_blacklist_consumer_registered",
                    extra={
                        "rabbitmq_queue": self._settings.rabbitmq_queue_name,
                        "consumer_tag": consumer_tag,
                    },
                )

            await stop_event.wait()
            logger.info(
                "history_blacklist_consumer_shutdown_requested",
                extra={"rabbitmq_queue": self._settings.rabbitmq_queue_name},
            )
            await queue.cancel(consumer_tag)
            await self._finish_inflight()
        finally:
            self.ready.clear()
            self._connection = None
            if connection is not None and not connection.is_closed:
                await connection.close()
            logger.info(
                "history_blacklist_consumer_stopped",
                extra={"rabbitmq_queue": self._settings.rabbitmq_queue_name},
            )

    async def _on_message(self, message: AbstractIncomingMessage) -> None:
        task = cast(asyncio.Task[object] | None, asyncio.current_task())
        if task is not None:
            self._inflight.add(task)
        try:
            await self._handler.handle(message)
        finally:
            if task is not None:
                self._inflight.discard(task)

    async def _finish_inflight(self) -> None:
        if not self._inflight:
            return
        _, pending = await asyncio.wait(
            tuple(self._inflight),
            timeout=self._settings.rabbitmq_shutdown_timeout_seconds,
        )
        for task in pending:
            task.cancel()
        if pending:
            await asyncio.gather(*pending, return_exceptions=True)


async def run_consumer(settings: Settings, stop_event: asyncio.Event) -> None:
    await create_consumer(settings).run(stop_event)


def create_consumer(settings: Settings) -> HistoryBlacklistConsumer:
    """Build the consumer with History-owned persistence dependencies."""
    factory = cast(sessionmaker[Session], get_session_factory())
    handler = BlacklistMessageHandler(
        session_factory=factory,
        ingestion_service=get_blacklist_ingestion_service(),
    )
    return HistoryBlacklistConsumer(settings, handler)
