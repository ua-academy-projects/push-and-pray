"""Standalone singleton worker for blacklist polling and durable delivery."""

import asyncio
import fcntl
import logging
import signal
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from datetime import UTC, datetime
from pathlib import Path
from typing import IO, Protocol
from uuid import UUID, uuid4

from provider_service.config import Settings, get_settings
from provider_service.exceptions import ApplicationError, RateLimitExceededError
from provider_service.main import create_abuseipdb_http_client
from provider_service.outbox import BlacklistOutbox
from provider_service.polling_policy import PollingPolicy
from provider_service.provider import AbuseIPDBProvider
from provider_service.rabbitmq_publisher import (
    AioPikaBlacklistPublisher,
    BlacklistPublishingError,
)
from provider_service.schemas import (
    BlacklistSnapshotMessage,
    InternalBlacklistRequest,
)
from provider_service.service import ReputationProvider, ReputationProxyService

logger = logging.getLogger(__name__)


class PublisherGateway(Protocol):
    async def connect(self) -> None: ...

    async def publish(self, message: BlacklistSnapshotMessage) -> None: ...


@contextmanager
def singleton_worker_lock(outbox_path: Path) -> Iterator[None]:
    """Reject a second worker process regardless of API worker count."""
    lock_path = outbox_path.with_suffix(f"{outbox_path.suffix}.lock")
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
    """Run independent polling and durable RabbitMQ publishing schedules."""

    def __init__(
        self,
        *,
        provider: ReputationProvider,
        publisher: PublisherGateway,
        outbox: BlacklistOutbox,
        policy: PollingPolicy,
        confidence_minimum: int = 90,
        clock: Callable[[], datetime] | None = None,
        delivery_id_factory: Callable[[], UUID] | None = None,
        service: ReputationProxyService | None = None,
    ) -> None:
        self.provider = provider
        self.publisher = publisher
        self.outbox = outbox
        self.policy = policy
        self.confidence_minimum = confidence_minimum
        self.clock = clock or (lambda: datetime.now(UTC))
        self.delivery_id_factory = delivery_id_factory or uuid4
        self.service = service or ReputationProxyService(clock=self.clock)

    async def tick(self) -> None:
        """Perform each independently due action at most once."""
        now = self.clock()
        next_poll_at = self.outbox.get_next_poll_at()
        logger.info(
            "provider_blacklist_worker_tick next_poll_at=%s",
            next_poll_at.isoformat() if next_poll_at else None,
        )
        if next_poll_at is None or next_poll_at <= now:
            await self._poll(now)
        await self._publish_one(self.clock())

    async def run(self, stop_event: asyncio.Event) -> None:
        while not stop_event.is_set():
            await self.tick()
            now = self.clock()
            due_times = [
                value
                for value in (
                    self.outbox.get_next_poll_at(),
                    self.outbox.next_due_at(),
                )
                if value is not None
            ]
            delay = (
                max(0.0, min((due - now).total_seconds() for due in due_times))
                if due_times
                else 60.0
            )
            try:
                await asyncio.wait_for(stop_event.wait(), timeout=min(delay, 60.0))
            except TimeoutError:
                continue

    async def _poll(self, now: datetime) -> None:
        logger.info(
            "provider_blacklist_poll_started confidence_minimum=%s limit=1000",
            self.confidence_minimum,
        )
        try:
            snapshot = await self.service.blacklist(
                InternalBlacklistRequest(
                    confidence_minimum=self.confidence_minimum, limit=1000
                ),
                self.provider,
            )
        except RateLimitExceededError as error:
            next_poll_at = self.policy.after_rate_limit(
                now,
                retry_after_seconds=error.retry_after_seconds,
                reset_at=error.reset_at,
            )
            attempts = self.outbox.get_poll_failure_attempts() + 1
            self.outbox.set_poll_state(
                next_poll_at=next_poll_at, failure_attempts=attempts
            )
            logger.warning(
                "provider_blacklist_poll_rate_limited "
                "failure_attempts=%s next_poll_at=%s",
                attempts,
                next_poll_at.isoformat(),
            )
            return
        except ApplicationError as error:
            attempts = self.outbox.get_poll_failure_attempts() + 1
            next_poll_at = self.policy.after_poll_failure(now, attempt=attempts)
            self.outbox.set_poll_state(
                next_poll_at=next_poll_at,
                failure_attempts=attempts,
            )
            logger.warning(
                "provider_blacklist_poll_failed error_code=%s "
                "failure_attempts=%s next_poll_at=%s",
                error.code,
                attempts,
                next_poll_at.isoformat(),
            )
            return

        delivery_id = self.delivery_id_factory()
        self.outbox.enqueue(delivery_id=delivery_id, snapshot=snapshot, now=now)
        next_poll_at = self.policy.after_success(
            now,
            remaining=snapshot.rate_limit.remaining,
            reset_at=snapshot.rate_limit.reset_at,
        )
        self.outbox.set_poll_state(
            next_poll_at=next_poll_at,
            failure_attempts=0,
        )
        logger.info(
            "provider_blacklist_poll_succeeded delivery_id=%s entry_count=%s "
            "provider_generated_at=%s next_poll_at=%s",
            delivery_id,
            len(snapshot.items),
            snapshot.generated_at.isoformat(),
            next_poll_at.isoformat(),
        )
        logger.info(
            "provider_blacklist_outbox_enqueued delivery_id=%s",
            delivery_id,
        )

    async def _publish_one(self, now: datetime) -> None:
        pending = self.outbox.next_pending(now)
        if pending is None:
            return
        logger.info(
            "provider_blacklist_publish_attempt delivery_id=%s attempt=%s",
            pending.message.delivery_id,
            pending.attempts + 1,
        )
        try:
            await self.publisher.connect()
            await self.publisher.publish(pending.message)
        except BlacklistPublishingError as error:
            attempts = pending.attempts + 1
            next_attempt_at = self.policy.after_publish_failure(now, attempt=attempts)
            self.outbox.reschedule(
                pending.message.delivery_id,
                attempts=attempts,
                next_attempt_at=next_attempt_at,
            )
            logger.warning(
                "provider_blacklist_publish_failed delivery_id=%s "
                "error_type=%s attempt=%s next_attempt_at=%s",
                pending.message.delivery_id,
                type(error).__name__,
                attempts,
                next_attempt_at.isoformat(),
            )
            return
        logger.info(
            "provider_blacklist_publish_confirmed delivery_id=%s",
            pending.message.delivery_id,
        )
        self.outbox.mark_published(
            pending.message.delivery_id, published_at=self.clock()
        )
        logger.info(
            "provider_blacklist_outbox_published delivery_id=%s",
            pending.message.delivery_id,
        )


async def run_worker(settings: Settings, stop_event: asyncio.Event) -> None:
    logger.info(
        "provider_blacklist_worker_starting poll_interval_seconds=%s "
        "confidence_minimum=%s outbox_path=%s rabbitmq_host=%s "
        "rabbitmq_port=%s rabbitmq_virtual_host=%s rabbitmq_exchange=%s "
        "rabbitmq_routing_key=%s",
        settings.blacklist_poll_interval_seconds,
        settings.blacklist_confidence_minimum,
        settings.blacklist_outbox_path,
        settings.rabbitmq_host,
        settings.rabbitmq_port,
        settings.rabbitmq_virtual_host,
        settings.rabbitmq_exchange_name,
        settings.rabbitmq_routing_key,
    )
    if not settings.blacklist_polling_enabled:
        logger.info("provider_blacklist_polling_disabled")
        return
    with singleton_worker_lock(settings.blacklist_outbox_path):
        logger.info(
            "provider_blacklist_singleton_lock_acquired outbox_path=%s",
            settings.blacklist_outbox_path,
        )
        outbox = BlacklistOutbox(settings.blacklist_outbox_path)
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
                outbox=outbox,
                policy=PollingPolicy(
                    interval_seconds=settings.blacklist_poll_interval_seconds,
                    publish_initial_seconds=(
                        settings.rabbitmq_publish_retry_initial_seconds
                    ),
                    publish_maximum_seconds=(
                        settings.rabbitmq_publish_retry_maximum_seconds
                    ),
                ),
                confidence_minimum=settings.blacklist_confidence_minimum,
            )
            await worker.run(stop_event)
        finally:
            logger.info("provider_blacklist_worker_shutting_down")
            await abuseipdb_client.aclose()
            await publisher.close()
            outbox.close()
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
