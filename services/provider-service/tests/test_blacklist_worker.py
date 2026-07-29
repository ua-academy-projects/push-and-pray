import asyncio
import logging
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID

import pytest
from provider_service.blacklist_worker import (
    BlacklistPollingWorker,
    BlacklistPublicationExhaustedError,
    singleton_worker_lock,
)
from provider_service.exceptions import (
    RateLimitExceededError,
    UpstreamTimeoutError,
)
from provider_service.polling_policy import PollingPolicy
from provider_service.rabbitmq_publisher import (
    BlacklistPublishingConnectionError,
    BlacklistPublishingSerializationError,
    BlacklistPublishingUnroutableError,
)
from provider_service.schemas import BlacklistProviderResult, RateLimitMetadata

NOW = datetime(2026, 7, 23, 9, 0, tzinfo=UTC)
DELIVERY_ID = UUID("662ecba0-8918-433d-bc75-b14de17851f1")


class Clock:
    def __init__(self) -> None:
        self.now = NOW

    def __call__(self) -> datetime:
        return self.now


class FakeProvider:
    def __init__(self, outcomes: list[object]) -> None:
        self.outcomes = outcomes
        self.calls = 0

    async def blacklist(
        self, confidence_minimum: int, limit: int
    ) -> BlacklistProviderResult:
        self.calls += 1
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        assert isinstance(outcome, BlacklistProviderResult)
        return outcome


class FakePublisher:
    def __init__(self, outcomes: list[object] | None = None) -> None:
        self.outcomes = outcomes or [object()]
        self.messages = []
        self.connect_calls = 0
        self.close_calls = 0

    async def connect(self) -> None:
        self.connect_calls += 1

    async def publish(self, message):
        self.messages.append(message)
        outcome = self.outcomes.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return outcome

    async def close(self) -> None:
        self.close_calls += 1


class SleepRecorder:
    def __init__(self) -> None:
        self.delays: list[float] = []

    async def __call__(self, delay: float) -> None:
        self.delays.append(delay)


def result(
    *,
    remaining: int | None = 4,
    reset_at: datetime | None = None,
) -> BlacklistProviderResult:
    return BlacklistProviderResult(
        generated_at=NOW,
        rate_limit=RateLimitMetadata(limit=5, remaining=remaining, reset_at=reset_at),
        items=[],
    )


def policy() -> PollingPolicy:
    return PollingPolicy(
        interval_seconds=21600,
        publish_initial_seconds=30,
        publish_maximum_seconds=900,
    )


def worker(
    provider: FakeProvider,
    publisher: FakePublisher,
    clock: Clock,
    *,
    publish_max_attempts: int = 5,
    sleep: SleepRecorder | None = None,
) -> BlacklistPollingWorker:
    return BlacklistPollingWorker(
        provider=provider,
        publisher=publisher,
        policy=policy(),
        publish_max_attempts=publish_max_attempts,
        clock=clock,
        delivery_id_factory=lambda: DELIVERY_ID,
        sleep=sleep,
        jitter=lambda _delay: 0,
    )


def test_singleton_lock_rejects_second_worker(tmp_path: Path) -> None:
    lock_path = tmp_path / "worker.lock"

    with singleton_worker_lock(lock_path):
        with pytest.raises(RuntimeError, match="already running"):
            with singleton_worker_lock(lock_path):
                pass


@pytest.mark.anyio
async def test_scheduled_polling_waits_until_in_memory_due_time() -> None:
    clock = Clock()
    provider = FakeProvider([result(), result()])
    current = worker(provider, FakePublisher([object(), object()]), clock)

    await current.tick()
    await current.tick()
    assert provider.calls == 1

    clock.now += timedelta(hours=6)
    await current.tick()
    assert provider.calls == 2


@pytest.mark.anyio
async def test_429_honors_retry_after_and_reset() -> None:
    clock = Clock()
    reset_at = NOW + timedelta(hours=2)
    current = worker(
        FakeProvider(
            [
                RateLimitExceededError(
                    retry_after_seconds=3600,
                    reset_at=reset_at,
                )
            ]
        ),
        FakePublisher(),
        clock,
    )

    await current.tick()

    assert current.next_poll_at == reset_at
    assert current.poll_failure_attempts == 1


@pytest.mark.anyio
async def test_upstream_timeout_uses_bounded_poll_retry_schedule() -> None:
    clock = Clock()
    current = worker(
        FakeProvider([UpstreamTimeoutError()]),
        FakePublisher(),
        clock,
    )

    await current.tick()

    assert current.next_poll_at == NOW + timedelta(minutes=5)
    assert current.poll_failure_attempts == 1


@pytest.mark.anyio
async def test_transient_publish_failure_reconnects_with_same_message_id() -> None:
    clock = Clock()
    sleep = SleepRecorder()
    publisher = FakePublisher([BlacklistPublishingConnectionError("failed"), object()])
    current = worker(FakeProvider([result()]), publisher, clock, sleep=sleep)

    await current.tick()

    assert publisher.connect_calls == 2
    assert publisher.close_calls == 1
    assert sleep.delays == [30]
    assert len(publisher.messages) == 2
    assert publisher.messages[0] is publisher.messages[1]
    assert publisher.messages[0].delivery_id == DELIVERY_ID
    assert publisher.messages[0].correlation_id == DELIVERY_ID
    assert current.next_poll_at == NOW + timedelta(hours=6)


@pytest.mark.anyio
async def test_publish_retry_is_bounded_and_uses_exponential_backoff(
    caplog: pytest.LogCaptureFixture,
) -> None:
    clock = Clock()
    sleep = SleepRecorder()
    publisher = FakePublisher(
        [BlacklistPublishingConnectionError("failed") for _ in range(4)]
    )
    current = worker(
        FakeProvider([result()]),
        publisher,
        clock,
        publish_max_attempts=4,
        sleep=sleep,
    )

    with (
        caplog.at_level(logging.WARNING),
        pytest.raises(BlacklistPublicationExhaustedError),
    ):
        await current.tick()

    assert publisher.connect_calls == 4
    assert publisher.close_calls == 4
    assert sleep.delays == [30, 60, 120]
    assert {message.delivery_id for message in publisher.messages} == {DELIVERY_ID}
    assert "provider_blacklist_publish_failed" in caplog.text
    assert current.next_poll_at is None


@pytest.mark.anyio
@pytest.mark.parametrize(
    "failure",
    [
        BlacklistPublishingSerializationError("invalid"),
        BlacklistPublishingUnroutableError("unroutable"),
    ],
)
async def test_permanent_publish_failure_is_not_retried(failure: Exception) -> None:
    publisher = FakePublisher([failure])
    current = worker(FakeProvider([result()]), publisher, Clock())

    with pytest.raises(type(failure)):
        await current.tick()

    assert publisher.connect_calls == 1
    assert publisher.close_calls == 0
    assert len(publisher.messages) == 1


@pytest.mark.anyio
async def test_worker_stops_while_waiting_for_future_schedule() -> None:
    current = worker(FakeProvider([result()]), FakePublisher(), Clock())
    current.next_poll_at = NOW + timedelta(hours=6)
    stop_event = asyncio.Event()

    task = asyncio.create_task(current.run(stop_event))
    await asyncio.sleep(0)
    stop_event.set()
    await task


@pytest.mark.anyio
async def test_worker_stops_during_publication_retry_delay() -> None:
    publisher = FakePublisher([BlacklistPublishingConnectionError("failed")])
    current = worker(FakeProvider([result()]), publisher, Clock())
    stop_event = asyncio.Event()

    task = asyncio.create_task(current.run(stop_event))
    while publisher.close_calls == 0:
        await asyncio.sleep(0)
    stop_event.set()
    await task

    assert publisher.connect_calls == 1
    assert len(publisher.messages) == 1


def test_worker_has_no_history_http_or_local_database_dependency() -> None:
    import provider_service.blacklist_worker as worker_module

    source = Path(worker_module.__file__).read_text()

    assert "history_client" not in source
    assert "HistoryIngestionClient" not in source
    assert "create_history_http_client" not in source
    assert "httpx" not in source
