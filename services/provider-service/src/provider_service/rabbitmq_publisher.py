"""RabbitMQ publisher adapter for complete blacklist snapshots."""

import asyncio
from collections.abc import Awaitable, Callable
from contextlib import suppress
from typing import Protocol

import aio_pika
from aio_pika import DeliveryMode, ExchangeType, Message
from aio_pika.abc import (
    AbstractChannel,
    AbstractExchange,
    AbstractRobustConnection,
)
from aio_pika.exceptions import AMQPError, DeliveryError
from pamqp.commands import Basic
from pydantic import ValidationError
from pydantic_core import PydanticSerializationError

from provider_service.config import Settings
from provider_service.schemas import BlacklistSnapshotMessage

RobustConnector = Callable[..., Awaitable[AbstractRobustConnection]]


class BlacklistPublisher(Protocol):
    """Lifecycle and publishing boundary used by the Provider worker."""

    async def connect(self) -> None: ...

    async def publish(self, message: BlacklistSnapshotMessage) -> None: ...

    async def close(self) -> None: ...


class BlacklistPublishingError(Exception):
    """Safe base failure for RabbitMQ publishing operations."""


class BlacklistPublishingConnectionError(BlacklistPublishingError):
    """RabbitMQ connection or channel setup failed."""


class BlacklistPublishingSerializationError(BlacklistPublishingError):
    """The message could not be validated or serialized."""


class BlacklistPublishingTimeoutError(BlacklistPublishingError):
    """RabbitMQ did not complete the operation before its deadline."""


class BlacklistPublishingRejectedError(BlacklistPublishingError):
    """RabbitMQ rejected or negatively acknowledged the message."""


class BlacklistPublishingUnroutableError(BlacklistPublishingError):
    """RabbitMQ could not route the mandatory message."""


class AioPikaBlacklistPublisher:
    """Publish validated snapshots through one owned robust connection."""

    def __init__(
        self,
        settings: Settings,
        *,
        connector: RobustConnector = aio_pika.connect_robust,
    ) -> None:
        self._settings = settings
        self._connector = connector
        self._connection: AbstractRobustConnection | None = None
        self._channel: AbstractChannel | None = None
        self._exchange: AbstractExchange | None = None

    async def connect(self) -> None:
        """Connect and declare the durable direct exchange."""
        if self._connection is not None:
            return
        connection: AbstractRobustConnection | None = None
        channel: AbstractChannel | None = None
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
                channel = await connection.channel(
                    publisher_confirms=True,
                    on_return_raises=True,
                )
                assert channel is not None
                exchange = await channel.declare_exchange(
                    self._settings.rabbitmq_exchange_name,
                    ExchangeType.DIRECT,
                    durable=True,
                    auto_delete=False,
                )
        except TimeoutError:
            await self._discard_resources(channel, connection)
            raise BlacklistPublishingTimeoutError(
                "RabbitMQ connection timed out."
            ) from None
        except Exception:
            await self._discard_resources(channel, connection)
            raise BlacklistPublishingConnectionError(
                "RabbitMQ publisher connection failed."
            ) from None

        assert connection is not None
        assert channel is not None
        self._connection = connection
        self._channel = channel
        self._exchange = exchange

    async def publish(self, message: BlacklistSnapshotMessage) -> None:
        """Validate, serialize, and publisher-confirm one persistent message."""
        exchange = self._exchange
        if exchange is None:
            raise BlacklistPublishingConnectionError(
                "RabbitMQ publisher is not connected."
            )
        try:
            validated = BlacklistSnapshotMessage.model_validate(message)
            body = validated.model_dump_json().encode("utf-8")
        except (
            TypeError,
            ValueError,
            ValidationError,
            PydanticSerializationError,
        ):
            raise BlacklistPublishingSerializationError(
                "Blacklist message serialization failed."
            ) from None

        outgoing = Message(
            body,
            content_type="application/json",
            content_encoding="utf-8",
            delivery_mode=DeliveryMode.PERSISTENT,
            correlation_id=str(validated.correlation_id),
            message_id=str(validated.delivery_id),
            timestamp=validated.created_at,
            type=validated.message_type,
            app_id=validated.producer,
        )
        try:
            async with asyncio.timeout(self._settings.rabbitmq_publish_timeout_seconds):
                confirmation = await exchange.publish(
                    outgoing,
                    routing_key=self._settings.rabbitmq_routing_key,
                    mandatory=True,
                    timeout=self._settings.rabbitmq_publish_timeout_seconds,
                )
        except TimeoutError:
            raise BlacklistPublishingTimeoutError(
                "RabbitMQ publish timed out."
            ) from None
        except DeliveryError as error:
            if isinstance(error.frame, Basic.Return):
                raise BlacklistPublishingUnroutableError(
                    "RabbitMQ could not route the blacklist message."
                ) from None
            raise BlacklistPublishingRejectedError(
                "RabbitMQ rejected the blacklist message."
            ) from None
        except AMQPError, OSError:
            raise BlacklistPublishingConnectionError(
                "RabbitMQ publish failed."
            ) from None

        if not isinstance(confirmation, Basic.Ack):
            raise BlacklistPublishingRejectedError(
                "RabbitMQ rejected the blacklist message."
            )

    async def close(self) -> None:
        """Close owned channel and connection, then clear lifecycle state."""
        channel = self._channel
        connection = self._connection
        self._exchange = None
        self._channel = None
        self._connection = None
        try:
            await self._close_resources(channel, connection)
        except Exception:
            raise BlacklistPublishingConnectionError(
                "RabbitMQ publisher close failed."
            ) from None

    @staticmethod
    async def _close_resources(
        channel: AbstractChannel | None,
        connection: AbstractRobustConnection | None,
    ) -> None:
        if channel is not None and not channel.is_closed:
            await channel.close()
        if connection is not None and not connection.is_closed:
            await connection.close()

    @classmethod
    async def _discard_resources(
        cls,
        channel: AbstractChannel | None,
        connection: AbstractRobustConnection | None,
    ) -> None:
        with suppress(Exception):
            await cls._close_resources(channel, connection)
