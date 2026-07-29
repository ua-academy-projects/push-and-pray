import asyncio
import inspect
import json
from datetime import UTC, datetime
from typing import Any, cast
from unittest.mock import Mock

import history_service.blacklist_consumer as consumer_module
import pytest
from aio_pika import DeliveryMode, ExchangeType
from aio_pika.abc import (
    AbstractExchange,
    AbstractIncomingMessage,
    AbstractRobustConnection,
)
from history_service.blacklist_consumer import (
    DEAD_LETTER_ROUTING_KEY,
    RETRY_ATTEMPT_HEADER,
    BlacklistMessageHandler,
    HistoryBlacklistConsumer,
    RabbitMQFailureStrategy,
    RetryPolicy,
)
from history_service.blacklist_ingestion import BlacklistIngestionResult
from history_service.config import Settings
from history_service.models import BlacklistSnapshot
from history_service.service import HistoryUnavailableError
from pamqp.commands import Basic

DELIVERY_ID = "662ecba0-8918-433d-bc75-b14de17851f1"
CORRELATION_ID = "6f5aa064-43e8-4dbb-a544-d60b68af5cbd"
NOW = datetime(2026, 7, 23, 9, 0, tzinfo=UTC)


def body(**overrides: Any) -> bytes:
    payload: dict[str, Any] = {
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
            "rate_limit": {},
            "items": [],
        },
    }
    payload.update(overrides)
    return json.dumps(payload).encode()


class FakeMessage:
    def __init__(self, payload: bytes | None = None, **overrides: Any) -> None:
        self.body = payload if payload is not None else body()
        self.content_type = "application/json"
        self.content_encoding = "utf-8"
        self.delivery_mode = DeliveryMode.PERSISTENT
        self.message_id = DELIVERY_ID
        self.correlation_id = CORRELATION_ID
        self.type = "blacklist.snapshot.complete"
        self.app_id = "aegis-provider-service"
        self.timestamp = NOW
        self.redelivered = False
        self.headers: dict[str, Any] = {}
        self.ack_calls = 0
        self.reject_calls: list[bool] = []
        self.nack_calls: list[bool] = []
        for name, value in overrides.items():
            setattr(self, name, value)

    async def ack(self, multiple: bool = False) -> None:
        self.ack_calls += 1

    async def reject(self, requeue: bool = False) -> None:
        self.reject_calls.append(requeue)

    async def nack(self, multiple: bool = False, requeue: bool = True) -> None:
        self.nack_calls.append(requeue)


class FakeSession:
    def __init__(self) -> None:
        self.close_calls = 0

    def close(self) -> None:
        self.close_calls += 1


async def run_inline(function):
    return function()


def handler(
    service: Mock,
    session: FakeSession,
    *,
    run_sync=run_inline,
    failure_strategy=None,
) -> BlacklistMessageHandler:
    return BlacklistMessageHandler(
        session_factory=lambda: cast(Any, session),
        ingestion_service=service,
        run_sync=run_sync,
        failure_strategy=failure_strategy,
    )


@pytest.mark.anyio
async def test_ack_occurs_only_after_successful_ingestion_returns() -> None:
    service = Mock()
    service.ingest.return_value = BlacklistIngestionResult(
        BlacklistSnapshot(snapshot_id=42), True, NOW
    )
    session = FakeSession()
    started = asyncio.Event()
    release = asyncio.Event()

    async def controlled_run(function):
        started.set()
        await release.wait()
        return function()

    message = FakeMessage()
    task = asyncio.create_task(
        handler(service, session, run_sync=controlled_run).handle(
            cast(AbstractIncomingMessage, message)
        )
    )
    await started.wait()

    assert message.ack_calls == 0
    release.set()
    await task

    assert message.ack_calls == 1
    assert session.close_calls == 1


@pytest.mark.anyio
async def test_valid_duplicate_is_acked() -> None:
    service = Mock()
    service.ingest.return_value = BlacklistIngestionResult(
        BlacklistSnapshot(snapshot_id=42), False, NOW
    )
    session = FakeSession()
    message = FakeMessage()

    await handler(service, session).handle(cast(AbstractIncomingMessage, message))

    assert message.ack_calls == 1
    assert session.close_calls == 1


@pytest.mark.anyio
async def test_amqp_timestamp_accepts_json_subsecond_precision() -> None:
    service = Mock()
    service.ingest.return_value = BlacklistIngestionResult(
        BlacklistSnapshot(snapshot_id=42), True, NOW
    )
    session = FakeSession()
    created_at = NOW.replace(microsecond=508777)
    message = FakeMessage(
        body(created_at=created_at.isoformat()),
        timestamp=created_at.replace(microsecond=0),
    )

    await handler(service, session).handle(cast(AbstractIncomingMessage, message))

    assert message.ack_calls == 1
    assert message.reject_calls == []
    service.ingest.assert_called_once()


@pytest.mark.anyio
@pytest.mark.parametrize(
    "payload",
    [
        b"{not-json",
        body(schema_version=2),
        body(message_type="blacklist.snapshot.partial"),
    ],
)
async def test_invalid_json_or_contract_is_rejected(payload: bytes) -> None:
    service = Mock()
    session = FakeSession()
    message = FakeMessage(payload)

    await handler(service, session).handle(cast(AbstractIncomingMessage, message))

    assert message.reject_calls == [False]
    assert message.ack_calls == 0
    assert session.close_calls == 0
    service.ingest.assert_not_called()


@pytest.mark.anyio
@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("message_id", CORRELATION_ID),
        ("correlation_id", DELIVERY_ID),
        ("type", "blacklist.snapshot.partial"),
        ("app_id", "another-producer"),
        ("timestamp", datetime(2026, 7, 23, 9, 1, tzinfo=UTC)),
        ("delivery_mode", DeliveryMode.NOT_PERSISTENT),
        ("content_type", "text/plain"),
        ("content_type", None),
        ("content_encoding", "utf-16"),
        ("content_encoding", None),
        ("message_id", None),
        ("correlation_id", None),
        ("type", None),
        ("app_id", None),
        ("timestamp", None),
    ],
)
async def test_amqp_body_metadata_mismatch_is_rejected(
    field: str, value: object
) -> None:
    service = Mock()
    session = FakeSession()
    message = FakeMessage(**{field: value})

    await handler(service, session).handle(cast(AbstractIncomingMessage, message))

    assert message.reject_calls == [False]
    assert message.ack_calls == 0
    service.ingest.assert_not_called()


@pytest.mark.anyio
async def test_database_failure_is_nacked_and_session_closes() -> None:
    service = Mock()
    service.ingest.side_effect = HistoryUnavailableError("database unavailable")
    session = FakeSession()
    message = FakeMessage()

    await handler(service, session).handle(cast(AbstractIncomingMessage, message))

    assert message.nack_calls == [False]
    assert message.ack_calls == 0
    assert session.close_calls == 1


class FakeExchange:
    def __init__(self, outcome: object | None = None) -> None:
        self.outcome = outcome if outcome is not None else Basic.Ack(delivery_tag=1)
        self.publish_calls: list[tuple[Any, dict[str, Any]]] = []

    async def publish(self, outgoing, **kwargs):
        self.publish_calls.append((outgoing, kwargs))
        if isinstance(self.outcome, Exception):
            raise self.outcome
        return self.outcome


def retry_strategy(
    *,
    retry_outcome: object | None = None,
    dead_outcome: object | None = None,
) -> tuple[RabbitMQFailureStrategy, FakeExchange, FakeExchange]:
    retry = FakeExchange(retry_outcome)
    dead = FakeExchange(dead_outcome)
    strategy = RabbitMQFailureStrategy(settings())
    strategy.configure(
        retry_exchange=cast(AbstractExchange, retry),
        dead_letter_exchange=cast(AbstractExchange, dead),
    )
    return strategy, retry, dead


@pytest.mark.anyio
async def test_retryable_failure_selects_first_delay_and_increments_attempt() -> None:
    strategy, retry, dead = retry_strategy()
    message = FakeMessage()

    await strategy.temporary(cast(AbstractIncomingMessage, message))

    outgoing, options = retry.publish_calls[0]
    assert outgoing.headers[RETRY_ATTEMPT_HEADER] == 1
    assert outgoing.body == message.body
    assert outgoing.delivery_mode == DeliveryMode.PERSISTENT
    assert outgoing.message_id == DELIVERY_ID
    assert outgoing.correlation_id == CORRELATION_ID
    assert options["routing_key"] == "blacklist.snapshot.retry.300"
    assert options["mandatory"] is True
    assert message.ack_calls == 1
    assert dead.publish_calls == []


def test_retry_tiers_are_bounded() -> None:
    policy = RetryPolicy()

    assert [policy.delay_for_attempt(attempt) for attempt in range(5)] == [
        300,
        900,
        1800,
        3600,
        None,
    ]


@pytest.mark.anyio
async def test_retry_exhaustion_routes_to_dead_letter() -> None:
    strategy, retry, dead = retry_strategy()
    message = FakeMessage(headers={RETRY_ATTEMPT_HEADER: 4})

    await strategy.temporary(cast(AbstractIncomingMessage, message))

    assert retry.publish_calls == []
    outgoing, options = dead.publish_calls[0]
    assert outgoing.body == message.body
    assert outgoing.message_id == DELIVERY_ID
    assert outgoing.correlation_id == CORRELATION_ID
    assert options["routing_key"] == DEAD_LETTER_ROUTING_KEY
    assert message.ack_calls == 1


@pytest.mark.anyio
async def test_permanent_failure_routes_directly_to_confirmed_dead_letter() -> None:
    strategy, retry, dead = retry_strategy()
    service = Mock()
    message = FakeMessage(b"{not-json")

    await handler(
        service,
        FakeSession(),
        failure_strategy=strategy,
    ).handle(cast(AbstractIncomingMessage, message))

    assert retry.publish_calls == []
    assert dead.publish_calls[0][0].body == b"{not-json"
    assert message.ack_calls == 1
    assert message.reject_calls == []


@pytest.mark.anyio
async def test_original_is_acked_only_after_confirmed_retry_publication() -> None:
    started = asyncio.Event()
    release = asyncio.Event()

    class ControlledExchange(FakeExchange):
        async def publish(self, outgoing, **kwargs):
            self.publish_calls.append((outgoing, kwargs))
            started.set()
            await release.wait()
            return Basic.Ack(delivery_tag=1)

    retry = ControlledExchange()
    dead = FakeExchange()
    strategy = RabbitMQFailureStrategy(settings())
    strategy.configure(
        retry_exchange=cast(AbstractExchange, retry),
        dead_letter_exchange=cast(AbstractExchange, dead),
    )
    message = FakeMessage()
    task = asyncio.create_task(
        strategy.temporary(cast(AbstractIncomingMessage, message))
    )
    await started.wait()

    assert message.ack_calls == 0
    release.set()
    await task

    assert message.ack_calls == 1


@pytest.mark.anyio
async def test_failed_retry_or_dead_letter_publish_does_not_ack_original() -> None:
    retry_nack = Basic.Nack(delivery_tag=1)
    strategy, _, _ = retry_strategy(
        retry_outcome=retry_nack,
        dead_outcome=retry_nack,
    )
    retry_message = FakeMessage()
    dead_message = FakeMessage()

    await strategy.temporary(cast(AbstractIncomingMessage, retry_message))
    await strategy.permanent(cast(AbstractIncomingMessage, dead_message))

    assert retry_message.ack_calls == 0
    assert dead_message.ack_calls == 0


@pytest.mark.anyio
async def test_failed_retry_handoff_logs_structured_context(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    strategy, _, _ = retry_strategy(retry_outcome=Basic.Nack(delivery_tag=1))
    message = FakeMessage(redelivered=True)
    failure_log = Mock()
    monkeypatch.setattr(consumer_module.logger, "error", failure_log)

    await strategy.temporary(cast(AbstractIncomingMessage, message))

    target = next(
        call
        for call in failure_log.call_args_list
        if call.args[0] == "history_blacklist_retry_handoff_failed"
    )
    (event,) = target.args
    context = target.kwargs["extra"]
    assert event == "history_blacklist_retry_handoff_failed"
    assert context["delivery_id"] == DELIVERY_ID
    assert context["correlation_id"] == CORRELATION_ID
    assert context["message_type"] == "blacklist.snapshot.complete"
    assert context["retry_attempt"] == 0
    assert context["redelivered"] is True
    assert context["next_retry_attempt"] == 1
    assert context["retry_delay_seconds"] == 300
    assert message.ack_calls == 0


@pytest.mark.anyio
async def test_duplicate_delivery_after_retry_persists_once(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    persisted: set[str] = set()
    service = Mock()

    def ingest(_session, delivery):
        created = str(delivery.delivery_id) not in persisted
        persisted.add(str(delivery.delivery_id))
        return BlacklistIngestionResult(BlacklistSnapshot(snapshot_id=42), created, NOW)

    service.ingest.side_effect = ingest
    first = FakeMessage()
    retried = FakeMessage(headers={RETRY_ATTEMPT_HEADER: 1})
    info_log = Mock()
    monkeypatch.setattr(consumer_module.logger, "info", info_log)

    await handler(service, FakeSession()).handle(cast(AbstractIncomingMessage, first))
    await handler(service, FakeSession()).handle(cast(AbstractIncomingMessage, retried))

    assert persisted == {DELIVERY_ID}
    assert service.ingest.call_count == 2
    assert first.ack_calls == 1
    assert retried.ack_calls == 1
    committed = [
        call
        for call in info_log.call_args_list
        if call.args[0] == "history_blacklist_message_committed"
    ]
    assert [call.kwargs["extra"]["duplicate"] for call in committed] == [False, True]
    assert all(call.kwargs["extra"]["delivery_id"] == DELIVERY_ID for call in committed)


def settings(**overrides: Any) -> Settings:
    values: dict[str, Any] = {
        "_env_file": None,
        "mariadb_database": "aegis_history",
        "mariadb_user": "history",
        "mariadb_password": "secret",
        "rabbitmq_prefetch_count": 3,
        "rabbitmq_shutdown_timeout_seconds": 0.01,
    }
    values.update(overrides)
    return Settings(**values)


class FakeQueue:
    def __init__(self) -> None:
        self.bind_calls: list[tuple[object, dict[str, Any]]] = []
        self.consume_calls: list[dict[str, Any]] = []
        self.cancel_calls: list[str] = []
        self.callback = None
        self.consuming = asyncio.Event()

    async def bind(self, exchange, **kwargs) -> None:
        self.bind_calls.append((exchange, kwargs))

    async def consume(self, callback, **kwargs) -> str:
        self.callback = callback
        self.consume_calls.append(kwargs)
        self.consuming.set()
        return "consumer-tag"

    async def cancel(self, consumer_tag: str) -> None:
        self.cancel_calls.append(consumer_tag)


class FakeChannel:
    def __init__(self, queue: FakeQueue) -> None:
        self.queue = queue
        self.qos_calls: list[dict[str, Any]] = []
        self.exchange_calls: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
        self.queue_calls: list[tuple[tuple[Any, ...], dict[str, Any]]] = []
        self.exchanges: dict[str, FakeExchange] = {}
        self.queues: dict[str, FakeQueue] = {"aegis.history.blacklist.snapshots": queue}

    async def set_qos(self, **kwargs) -> None:
        self.qos_calls.append(kwargs)

    async def declare_exchange(self, *args, **kwargs):
        self.exchange_calls.append((args, kwargs))
        exchange = FakeExchange()
        self.exchanges[args[0]] = exchange
        return exchange

    async def declare_queue(self, *args, **kwargs):
        self.queue_calls.append((args, kwargs))
        return self.queues.setdefault(args[0], FakeQueue())


class FakeConnection:
    def __init__(self, channel: FakeChannel) -> None:
        self.channel_instance = channel
        self.channel_calls: list[dict[str, Any]] = []
        self.is_closed = False
        self.close_calls = 0

    async def channel(self, **kwargs):
        self.channel_calls.append(kwargs)
        return self.channel_instance

    async def close(self) -> None:
        self.close_calls += 1
        self.is_closed = True


class FakeConnector:
    def __init__(self, connection: FakeConnection) -> None:
        self.connection = connection
        self.calls: list[dict[str, Any]] = []

    async def __call__(self, **kwargs):
        self.calls.append(kwargs)
        return cast(AbstractRobustConnection, self.connection)


@pytest.mark.anyio
async def test_consumer_declares_topology_prefetch_and_manual_ack() -> None:
    queue = FakeQueue()
    channel = FakeChannel(queue)
    connection = FakeConnection(channel)
    service = Mock()
    connector = FakeConnector(connection)
    consumer = HistoryBlacklistConsumer(
        settings(),
        handler(service, FakeSession()),
        connector=connector,
    )
    stop_event = asyncio.Event()
    stop_event.set()

    await consumer.run(stop_event)

    assert connector.calls == [
        {
            "host": "127.0.0.1",
            "port": 5672,
            "login": "guest",
            "password": "guest",
            "virtualhost": "/",
            "timeout": 10.0,
        }
    ]
    assert connection.channel_calls == [
        {"publisher_confirms": True, "on_return_raises": True}
    ]
    assert channel.qos_calls == [{"prefetch_count": 3}]
    assert [call[0] for call in channel.exchange_calls] == [
        ("aegis.blacklist", ExchangeType.DIRECT),
        ("aegis.blacklist.retry", ExchangeType.DIRECT),
        ("aegis.blacklist.dead", ExchangeType.DIRECT),
    ]
    assert all(
        kwargs == {"durable": True, "auto_delete": False}
        for _, kwargs in channel.exchange_calls
    )
    assert len(channel.queue_calls) == 6
    assert all(
        kwargs["durable"] is True
        and kwargs["exclusive"] is False
        and kwargs["auto_delete"] is False
        for _, kwargs in channel.queue_calls
    )
    assert queue.bind_calls == [
        (
            channel.exchanges["aegis.blacklist"],
            {"routing_key": "blacklist.snapshot.complete"},
        )
    ]
    for delay in (300, 900, 1800, 3600):
        retry_queue = channel.queues[f"aegis.history.blacklist.snapshots.retry.{delay}"]
        declaration = next(
            kwargs
            for args, kwargs in channel.queue_calls
            if args[0] == f"aegis.history.blacklist.snapshots.retry.{delay}"
        )
        assert declaration["arguments"] == {
            "x-message-ttl": delay * 1000,
            "x-dead-letter-exchange": "aegis.blacklist",
            "x-dead-letter-routing-key": "blacklist.snapshot.complete",
        }
        assert retry_queue.bind_calls == [
            (
                channel.exchanges["aegis.blacklist.retry"],
                {"routing_key": f"blacklist.snapshot.retry.{delay}"},
            )
        ]
    assert channel.queues["aegis.history.blacklist.snapshots.dead"].bind_calls == [
        (
            channel.exchanges["aegis.blacklist.dead"],
            {"routing_key": DEAD_LETTER_ROUTING_KEY},
        )
    ]
    assert queue.consume_calls == [{"no_ack": False}]
    assert queue.cancel_calls == ["consumer-tag"]
    assert connection.close_calls == 1


@pytest.mark.anyio
async def test_graceful_shutdown_leaves_unfinished_message_unacknowledged() -> None:
    queue = FakeQueue()
    channel = FakeChannel(queue)
    connection = FakeConnection(channel)
    handler_started = asyncio.Event()

    class BlockingHandler:
        def set_failure_strategy(self, strategy) -> None:
            pass

        async def handle(self, message) -> None:
            handler_started.set()
            await asyncio.Event().wait()

    consumer = HistoryBlacklistConsumer(
        settings(),
        cast(BlacklistMessageHandler, BlockingHandler()),
        connector=FakeConnector(connection),
    )
    stop_event = asyncio.Event()
    run_task = asyncio.create_task(consumer.run(stop_event))
    await queue.consuming.wait()
    message = FakeMessage()
    callback_task = asyncio.create_task(
        queue.callback(cast(AbstractIncomingMessage, message))
    )
    await handler_started.wait()

    stop_event.set()
    await run_task

    assert callback_task.cancelled()
    assert message.ack_calls == 0
    assert message.reject_calls == []
    assert message.nack_calls == []


def test_amqp_callback_contains_only_orchestration() -> None:
    source = inspect.getsource(HistoryBlacklistConsumer._on_message)

    assert "_handler.handle" in source
    assert "session" not in source
    assert ".commit(" not in source
    assert "SELECT " not in source
    assert "INSERT " not in source
