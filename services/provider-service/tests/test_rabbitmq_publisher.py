import asyncio
import json
import logging
from datetime import UTC, datetime
from typing import Any, cast

import pytest
from aio_pika import DeliveryMode, ExchangeType
from aio_pika.abc import AbstractRobustConnection
from aio_pika.exceptions import AMQPConnectionError, DeliveryError
from pamqp.commands import Basic
from provider_service.config import Settings
from provider_service.rabbitmq_publisher import (
    AioPikaBlacklistPublisher,
    BlacklistPublishingConnectionError,
    BlacklistPublishingRejectedError,
    BlacklistPublishingSerializationError,
    BlacklistPublishingTimeoutError,
    BlacklistPublishingUnroutableError,
)
from provider_service.schemas import BlacklistSnapshotMessage

DELIVERY_ID = "662ecba0-8918-433d-bc75-b14de17851f1"
CORRELATION_ID = "6f5aa064-43e8-4dbb-a544-d60b68af5cbd"
NOW = datetime(2026, 7, 23, 9, 0, tzinfo=UTC)
PASSWORD = "RABBITMQ_PASSWORD_MUST_NOT_LEAK"
DEFAULT_OUTCOME = object()


def message() -> BlacklistSnapshotMessage:
    return BlacklistSnapshotMessage.model_validate(
        {
            "schema_version": 1,
            "message_type": "blacklist.snapshot.complete",
            "delivery_id": DELIVERY_ID,
            "correlation_id": CORRELATION_ID,
            "producer": "aegis-provider-service",
            "provider": "AbuseIPDB",
            "created_at": NOW.isoformat(),
            "snapshot": {
                "provider": "AbuseIPDB",
                "generated_at": NOW.isoformat(),
                "fetched_at": NOW.isoformat(),
                "request": {"confidence_minimum": 90, "limit": 1000},
                "rate_limit": {"limit": 5, "remaining": 4},
                "items": [],
            },
        }
    )


def settings() -> Settings:
    return Settings(
        _env_file=None,
        abuseipdb_api_key="test-key",
        rabbitmq_host="rabbitmq.test",
        rabbitmq_port=5673,
        rabbitmq_virtual_host="aegis",
        rabbitmq_username="provider",
        rabbitmq_password=PASSWORD,
        rabbitmq_exchange_name="blacklist-exchange",
        rabbitmq_routing_key="blacklist.complete",
        rabbitmq_connection_timeout_seconds=1,
        rabbitmq_publish_timeout_seconds=1,
    )


class FakeExchange:
    def __init__(self, outcome: object = DEFAULT_OUTCOME) -> None:
        self.outcome = (
            Basic.Ack(delivery_tag=1) if outcome is DEFAULT_OUTCOME else outcome
        )
        self.calls: list[tuple[Any, dict[str, Any]]] = []

    async def publish(self, outgoing, **kwargs):
        self.calls.append((outgoing, kwargs))
        if isinstance(self.outcome, Exception):
            raise self.outcome
        return self.outcome


class FakeChannel:
    def __init__(self, exchange: FakeExchange) -> None:
        self.exchange = exchange
        self.is_closed = False
        self.declarations: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
        self.close_calls = 0

    async def declare_exchange(self, *args, **kwargs):
        self.declarations.append((args, kwargs))
        return self.exchange

    async def close(self) -> None:
        self.close_calls += 1
        self.is_closed = True


class FakeConnection:
    def __init__(self, channel: FakeChannel) -> None:
        self.channel_instance = channel
        self.is_closed = False
        self.channel_calls: list[dict[str, Any]] = []
        self.close_calls = 0

    async def channel(self, **kwargs):
        self.channel_calls.append(kwargs)
        return self.channel_instance

    async def close(self) -> None:
        self.close_calls += 1
        self.is_closed = True


class FakeConnector:
    def __init__(
        self,
        connection: FakeConnection | None = None,
        error: Exception | None = None,
    ) -> None:
        self.connection = connection
        self.error = error
        self.calls: list[dict[str, Any]] = []

    async def __call__(self, **kwargs):
        self.calls.append(kwargs)
        if self.error is not None:
            raise self.error
        assert self.connection is not None
        return cast(AbstractRobustConnection, self.connection)


def publisher(
    *,
    outcome: object = DEFAULT_OUTCOME,
) -> tuple[
    AioPikaBlacklistPublisher,
    FakeConnector,
    FakeConnection,
    FakeChannel,
    FakeExchange,
]:
    exchange = FakeExchange(outcome)
    channel = FakeChannel(exchange)
    connection = FakeConnection(channel)
    connector = FakeConnector(connection)
    return (
        AioPikaBlacklistPublisher(settings(), connector=connector),
        connector,
        connection,
        channel,
        exchange,
    )


@pytest.mark.anyio
async def test_connect_declares_durable_direct_exchange_with_confirms() -> None:
    current, connector, connection, channel, _ = publisher()

    await current.connect()

    assert connector.calls[0]["host"] == "rabbitmq.test"
    assert connector.calls[0]["password"] == PASSWORD
    assert connection.channel_calls == [
        {"publisher_confirms": True, "on_return_raises": True}
    ]
    args, kwargs = channel.declarations[0]
    assert args == ("blacklist-exchange", ExchangeType.DIRECT)
    assert kwargs == {"durable": True, "auto_delete": False}


@pytest.mark.anyio
async def test_publish_uses_persistent_json_metadata_and_mandatory_routing() -> None:
    current, _, _, _, exchange = publisher()
    await current.connect()

    await current.publish(message())

    outgoing, options = exchange.calls[0]
    assert json.loads(outgoing.body)["delivery_id"] == DELIVERY_ID
    assert outgoing.delivery_mode == DeliveryMode.PERSISTENT
    assert outgoing.message_id == DELIVERY_ID
    assert outgoing.correlation_id == CORRELATION_ID
    assert outgoing.content_type == "application/json"
    assert outgoing.content_encoding == "utf-8"
    assert outgoing.type == "blacklist.snapshot.complete"
    assert outgoing.app_id == "aegis-provider-service"
    assert outgoing.timestamp == NOW
    assert options == {
        "routing_key": "blacklist.complete",
        "mandatory": True,
        "timeout": 1.0,
    }


@pytest.mark.anyio
async def test_positive_publisher_confirmation_succeeds() -> None:
    current, _, _, _, _ = publisher(outcome=Basic.Ack(delivery_tag=1))
    await current.connect()

    await current.publish(message())


@pytest.mark.anyio
@pytest.mark.parametrize(
    "confirmation",
    [
        Basic.Nack(delivery_tag=1),
        Basic.Reject(delivery_tag=1),
        DeliveryError(None, Basic.Nack(delivery_tag=1)),
        None,
    ],
)
async def test_negative_or_missing_confirmation_is_rejected(
    confirmation: object,
) -> None:
    current, _, _, _, _ = publisher(outcome=confirmation)
    await current.connect()

    with pytest.raises(BlacklistPublishingRejectedError):
        await current.publish(message())


@pytest.mark.anyio
async def test_unroutable_message_has_explicit_error() -> None:
    returned = Basic.Return(
        reply_code=312,
        reply_text="NO_ROUTE",
        exchange="blacklist-exchange",
        routing_key="blacklist.complete",
    )
    current, _, _, _, _ = publisher(outcome=DeliveryError(None, returned))
    await current.connect()

    with pytest.raises(BlacklistPublishingUnroutableError):
        await current.publish(message())


@pytest.mark.anyio
async def test_publish_timeout_has_explicit_error() -> None:
    current, _, _, _, exchange = publisher()

    async def blocked_publish(*args, **kwargs):
        await asyncio.sleep(2)

    exchange.publish = blocked_publish
    await current.connect()

    with pytest.raises(BlacklistPublishingTimeoutError):
        await current.publish(message())


@pytest.mark.anyio
async def test_connection_failure_is_safe_and_explicit(caplog) -> None:
    connector = FakeConnector(error=AMQPConnectionError(PASSWORD))
    current = AioPikaBlacklistPublisher(settings(), connector=connector)

    with caplog.at_level(logging.ERROR):
        try:
            await current.connect()
        except BlacklistPublishingConnectionError as error:
            captured = error
            logging.getLogger("provider.rabbitmq.test").exception(
                "rabbitmq_connection_failed"
            )
        else:
            pytest.fail("Expected a publishing connection error.")

    assert PASSWORD not in str(captured)
    assert PASSWORD not in caplog.text
    assert "amqp://" not in str(captured)


@pytest.mark.anyio
async def test_invalid_constructed_message_maps_to_serialization_error() -> None:
    current, _, _, _, exchange = publisher()
    await current.connect()
    invalid = message().model_copy(update={"snapshot": None})

    with pytest.raises(BlacklistPublishingSerializationError):
        await current.publish(invalid)

    assert exchange.calls == []


@pytest.mark.anyio
async def test_close_closes_owned_resources_and_is_idempotent() -> None:
    current, _, connection, channel, _ = publisher()
    await current.connect()

    await current.close()
    await current.close()

    assert channel.close_calls == 1
    assert connection.close_calls == 1


@pytest.mark.anyio
async def test_publish_requires_connected_lifecycle() -> None:
    current, _, _, _, _ = publisher()

    with pytest.raises(BlacklistPublishingConnectionError):
        await current.publish(message())
