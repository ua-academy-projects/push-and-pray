from __future__ import annotations

import asyncio
import logging
from datetime import UTC, datetime, timedelta

from pydantic import ValidationError
from sqlalchemy.orm import Session

from .config import Settings
from .database import SessionLocal
from .events import (
    claim_next_event,
    mark_failed,
    mark_processed,
    mark_retry_or_failed,
    recover_stuck_events,
)
from .models import PriceEvent
from .repository import insert_observations
from .schemas import ObservationEvent

logger = logging.getLogger(__name__)


def process_claimed_event(session: Session, event: PriceEvent, settings: Settings) -> None:
    """Validate and persist one already-claimed event.

    The observation insert and the 'processed' status update happen in the
    same transaction, so an event is only ever marked processed once its
    observations are durably committed alongside it.
    """
    try:
        parsed = ObservationEvent.model_validate(event.payload)
    except ValidationError as exc:
        logger.error(
            "rejecting permanently invalid price observation event",
            extra={"event_id": str(event.id), "event_key": event.event_key},
        )
        mark_failed(session, event, error=str(exc), now=datetime.now(UTC))
        return

    try:
        insert_observations(session, parsed.observations)
        mark_processed(session, event, now=datetime.now(UTC))
    except Exception as exc:
        session.rollback()
        logger.exception(
            "failed to persist event observations; scheduling retry",
            extra={"event_id": str(event.id), "event_key": event.event_key},
        )
        mark_retry_or_failed(
            session,
            event,
            error=str(exc),
            now=datetime.now(UTC),
            max_attempts=settings.history_worker_max_attempts,
            retry_backoff_seconds=settings.history_worker_retry_backoff_seconds,
        )
        return

    logger.info(
        "price observation event processed",
        extra={"event_id": str(event.id), "event_key": event.event_key},
    )


class PostgresEventWorker:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.task: asyncio.Task[None] | None = None
        self.running = False

    @property
    def is_ready(self) -> bool:
        return self.running and self.task is not None and not self.task.done()

    async def start(self) -> None:
        self.running = True
        self.task = asyncio.create_task(self._run(), name="postgres-history-worker")

    async def stop(self) -> None:
        self.running = False
        if self.task is not None:
            self.task.cancel()
            try:
                await self.task
            except asyncio.CancelledError:
                pass

    async def _run(self) -> None:
        logger.info("PostgreSQL event worker started")
        while True:
            try:
                processed = await asyncio.to_thread(self._tick)
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("event worker tick failed; backing off")
                processed = False
            if not processed:
                await asyncio.sleep(self.settings.history_worker_poll_interval_seconds)

    def _tick(self) -> bool:
        with SessionLocal() as session:
            now = datetime.now(UTC)
            recover_stuck_events(
                session,
                now=now,
                stuck_after=timedelta(seconds=self.settings.history_worker_stuck_after_seconds),
            )
            event = claim_next_event(session, now=now)
            if event is None:
                return False
            process_claimed_event(session, event, self.settings)
            return True
