"""Standalone singleton worker for polling and direct RabbitMQ publication."""

import asyncio
import fcntl
import logging
import random
import signal
from collections.abc import Awaitable, Callable, Iterator
from contextlib import contextmanager, suppress
from datetime import UTC, datetime
from pathlib import Path
from typing import IO, Protocol
from uuid import UUID, uuid4

from provider_service.config import Settings, get_settings
from provider_service.exceptions import ApplicationError, RateLimitExceededError
from provider_service.main import create_abuseipdb_http_client
from provider_service.polling_policy import PollingPolicy
from provider_service.provider import AbuseIPDBProvider
from provider_service.rabbitmq_publisher import (
    AioPikaBlacklistPublisher,
    BlacklistPublishingConnectionError,
    BlacklistPublishingError,
    BlacklistPublishingRejectedError,
    BlacklistPublishingSerializationError,
    BlacklistPublishingTimeoutError,
    BlacklistPublishingUnroutableError,
)
from provider_service.schemas import (
    BlacklistSnapshotMessage,
    InternalBlacklistRequest,
    InternalBlacklistResponse,
)
from provider_service.service import ReputationProvider, ReputationProxyService

logger = logging.getLogger(__name__)
WORKER_LOCK_PATH = Path("/tmp/aegis-provider-blacklist-worker.lock")


class PublisherGateway(Protocol):
    async def connect(self) -> None: ...

    async def publish(self, message: BlacklistSnapshotMessage) -> None: ...

    async def close(self) -> None: ...


class BlacklistPublicationExhaustedError(RuntimeError):
    """A fetched snapshot could not be confirmed within the retry bound."""


class WorkerShutdownRequested(Exception):
    """Interrupt an in-process retry delay during graceful shutdown."""


@contextmanager
def singleton_worker_lock(lock_path: Path = WORKER_LOCK_PATH) -> Iterator[None]:
    """Reject a second worker process without storing application data."""
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    handle: IO[str] = lock_path.open("a+")
    try:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError(
                "Provider blacklist worker is already running."
            ) from error
        yield
    finally:
        fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        handle.close()


class BlacklistPollingWorker:
    """Poll AbuseIPDB and publish each completed snapshot directly."""

    def __init__(
        self,
        *,
        provider: ReputationProvider,
        publisher: PublisherGateway,
        policy: PollingPolicy,
        publish_max_attempts: int,
        confidence_minimum: int = 90,
        clock: Callable[[], datetime] | None = None,
        delivery_id_factory: Callable[[], UUID] | None = None,
        service: ReputationProxyService | None = None,
        sleep: Callable[[float], Awaitable[None]] | None = None,
        jitter: Callable[[int], float] | None = None,
    ) -> None:
        self.provider = provider
        self.publisher = publisher
        self.policy = policy
        self.publish_max_attempts = publish_max_attempts
        self.confidence_minimum = confidence_minimum
        self.clock = clock or (lambda: datetime.now(UTC))
        self.delivery_id_factory = delivery_id_factory or uuid4
        self.service = service or ReputationProxyService(clock=self.clock)
        self.sleep = sleep or asyncio.sleep
        self.jitter = jitter or (
            lambda delay: random.uniform(0, min(delay * 0.1, 30.0))
        )
        self.next_poll_at: datetime | None = None
        self.poll_failure_attempts = 0
        self._stop_event: asyncio.Event | None = None

    async def tick(self) -> None:
        """Poll and publish once when the in-memory schedule is due."""
        now = self.clock()
        logger.info(
            "provider_blacklist_worker_tick",
            extra={
                "next_poll_at": (
                    self.next_poll_at.isoformat() if self.next_poll_at else None
                )
            },
        )
        if self.next_poll_at is None or self.next_poll_at <= now:
            await self._poll_and_publish(now)

    async def run(self, stop_event: asyncio.Event) -> None:
        self._stop_event = stop_event
        try:
            while not stop_event.is_set():
                try:
                    await self.tick()
                except WorkerShutdownRequested:
                    return
                now = self.clock()
                delay = (
                    max(0.0, (self.next_poll_at - now).total_seconds())
                    if self.next_poll_at is not None
                    else 60.0
                )
                try:
                    await asyncio.wait_for(stop_event.wait(), timeout=min(delay, 60.0))
                except TimeoutError:
                    continue
        finally:
            self._stop_event = None

    async def _poll_and_publish(self, now: datetime) -> None:
        logger.info(
            "provider_blacklist_poll_started",
            extra={"confidence_minimum": self.confidence_minimum, "limit": 1000},
        )
        try:
            snapshot = await self.service.blacklist(
                InternalBlacklistRequest(
                    confidence_minimum=self.confidence_minimum, limit=1000
                ),
                self.provider,
            )
        except RateLimitExceededError as error:
            self.poll_failure_attempts += 1
            self.next_poll_at = self.policy.after_rate_limit(
                now,
                retry_after_seconds=error.retry_after_seconds,
                reset_at=error.reset_at,
            )
            logger.warning(
                "provider_blacklist_poll_rate_limited",
                extra={
                    "failure_attempts": self.poll_failure_attempts,
                    "next_poll_at": self.next_poll_at.isoformat(),
                },
            )
            return
        except ApplicationError as error:
            self.poll_failure_attempts += 1
            self.next_poll_at = self.policy.after_poll_failure(
                now, attempt=self.poll_failure_attempts
            )
            logger.warning(
                "provider_blacklist_poll_failed",
                extra={
                    "error_code": error.code,
                    "failure_attempts": self.poll_failure_attempts,
                    "next_poll_at": self.next_poll_at.isoformat(),
                },
            )
            return

        delivery_id = self.delivery_id_factory()
        message = self._message_for(
            delivery_id=delivery_id,
            snapshot=snapshot,
            created_at=now,
        )
        logger.info(
            "provider_blacklist_poll_succeeded",
            extra={
                "delivery_id": str(delivery_id),
                "correlation_id": str(delivery_id),
                "entry_count": len(snapshot.items),
                "provider_generated_at": snapshot.generated_at.isoformat(),
            },
        )

        publish_attempts = await self._publish_with_retry(message)
        self.poll_failure_attempts = 0
        self.next_poll_at = self.policy.after_success(
            self.clock(),
            remaining=snapshot.rate_limit.remaining,
            reset_at=snapshot.rate_limit.reset_at,
        )
        logger.info(
            "provider_blacklist_publish_confirmed",
            extra={
                "delivery_id": str(delivery_id),
                "correlation_id": str(delivery_id),
                "attempts": publish_attempts,
                "next_poll_at": self.next_poll_at.isoformat(),
            },
        )

    async def _publish_with_retry(self, message: BlacklistSnapshotMessage) -> int:
        for attempt in range(1, self.publish_max_attempts + 1):
            logger.info(
                "provider_blacklist_publish_attempt",
                extra={
                    "delivery_id": str(message.delivery_id),
                    "correlation_id": str(message.correlation_id),
                    "attempt": attempt,
                    "max_attempts": self.publish_max_attempts,
                },
            )
            try:
                await self.publisher.connect()
                await self.publisher.publish(message)
                return attempt
            except (
                BlacklistPublishingSerializationError,
                BlacklistPublishingUnroutableError,
            ):
                logger.exception(
                    "provider_blacklist_publish_permanent_failure",
                    extra={
                        "delivery_id": str(message.delivery_id),
                        "correlation_id": str(message.correlation_id),
                        "attempt": attempt,
                    },
                )
                raise
            except (
                BlacklistPublishingConnectionError,
                BlacklistPublishingRejectedError,
                BlacklistPublishingTimeoutError,
            ) as error:
                with suppress(BlacklistPublishingError):
                    await self.publisher.close()
                exhausted = attempt >= self.publish_max_attempts
                delay = (
                    None
                    if exhausted
                    else self.policy.publish_delay_for_attempt(attempt)
                )
                log_failure = logger.error if exhausted else logger.warning
                log_failure(
                    "provider_blacklist_publish_failed",
                    extra={
                        "delivery_id": str(message.delivery_id),
                        "correlation_id": str(message.correlation_id),
                        "error_type": type(error).__name__,
                        "attempt": attempt,
                        "max_attempts": self.publish_max_attempts,
                        "retry_delay_seconds": delay,
                        "exhausted": exhausted,
                    },
                )
                if exhausted:
                    raise BlacklistPublicationExhaustedError(
                        "RabbitMQ publication retries were exhausted."
                    ) from error
                assert delay is not None
                await self._wait_before_retry(delay + self.jitter(delay))
        raise AssertionError("Publication retry loop exited without a result.")

    async def _wait_before_retry(self, delay: float) -> None:
        stop_event = self._stop_event
        if stop_event is None:
            await self.sleep(delay)
            return
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=delay)
        except TimeoutError:
            return
        raise WorkerShutdownRequested

    @staticmethod
    def _message_for(
        *,
        delivery_id: UUID,
        snapshot: InternalBlacklistResponse,
        created_at: datetime,
    ) -> BlacklistSnapshotMessage:
        return BlacklistSnapshotMessage(
            schema_version=1,
            message_type="blacklist.snapshot.complete",
            delivery_id=delivery_id,
            correlation_id=delivery_id,
            producer="aegis-provider-service",
            provider=snapshot.provider,
            created_at=created_at,
            snapshot=snapshot,
        )


async def run_worker(settings: Settings, stop_event: asyncio.Event) -> None:
    logger.info(
        "provider_blacklist_worker_starting",
        extra={
            "poll_interval_seconds": settings.blacklist_poll_interval_seconds,
            "confidence_minimum": settings.blacklist_confidence_minimum,
            "rabbitmq_host": settings.rabbitmq_host,
            "rabbitmq_port": settings.rabbitmq_port,
            "rabbitmq_virtual_host": settings.rabbitmq_virtual_host,
            "rabbitmq_exchange": settings.rabbitmq_exchange_name,
            "rabbitmq_routing_key": settings.rabbitmq_routing_key,
            "publish_max_attempts": settings.rabbitmq_publish_max_attempts,
        },
    )
    if not settings.blacklist_polling_enabled:
        logger.info("provider_blacklist_polling_disabled")
        return
    with singleton_worker_lock():
        logger.info("provider_blacklist_singleton_lock_acquired")
        abuseipdb_client = create_abuseipdb_http_client(settings)
        publisher = AioPikaBlacklistPublisher(settings)
        try:
            worker = BlacklistPollingWorker(
                provider=AbuseIPDBProvider(
                    abuseipdb_client,
                    operation_timeout_seconds=(
                        settings.abuseipdb_operation_timeout_seconds
                    ),
                ),
                publisher=publisher,
                policy=PollingPolicy(
                    interval_seconds=settings.blacklist_poll_interval_seconds,
                    publish_initial_seconds=(
                        settings.rabbitmq_publish_retry_initial_seconds
                    ),
                    publish_maximum_seconds=(
                        settings.rabbitmq_publish_retry_maximum_seconds
                    ),
                ),
                publish_max_attempts=settings.rabbitmq_publish_max_attempts,
                confidence_minimum=settings.blacklist_confidence_minimum,
            )
            await worker.run(stop_event)
        finally:
            logger.info("provider_blacklist_worker_shutting_down")
            await abuseipdb_client.aclose()
            await publisher.close()
            logger.info("provider_blacklist_worker_stopped")


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        force=True,
    )

    settings = get_settings()
    stop_event = asyncio.Event()

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    for signal_number in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(signal_number, stop_event.set)
    try:
        loop.run_until_complete(run_worker(settings, stop_event))
    finally:
        loop.close()
