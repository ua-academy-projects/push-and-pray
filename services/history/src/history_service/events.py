from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.orm import Session

from .models import PriceEvent

_MAX_ERROR_LENGTH = 4000


def claim_next_event(session: Session, *, now: datetime) -> PriceEvent | None:
    """Atomically claim the oldest available pending event, if any.

    Uses FOR UPDATE SKIP LOCKED so concurrent workers never block on, or
    double-claim, the same row. The claim is committed immediately, before
    processing starts, so an event left in 'processing' after a worker crash
    is detectable and recoverable by `recover_stuck_events`.
    """
    statement = (
        select(PriceEvent)
        .where(PriceEvent.status == "pending", PriceEvent.available_at <= now)
        .order_by(PriceEvent.created_at)
        .limit(1)
        .with_for_update(skip_locked=True)
    )
    event = session.execute(statement).scalar_one_or_none()
    if event is None:
        return None

    event.status = "processing"
    event.attempts += 1
    event.processing_started_at = now
    event.updated_at = now
    session.commit()
    return event


def mark_processed(session: Session, event: PriceEvent, *, now: datetime) -> None:
    event.status = "processed"
    event.processed_at = now
    event.updated_at = now
    event.last_error = None
    session.commit()


def mark_failed(session: Session, event: PriceEvent, *, error: str, now: datetime) -> None:
    event.status = "failed"
    event.last_error = error[:_MAX_ERROR_LENGTH]
    event.updated_at = now
    session.commit()


def mark_retry_or_failed(
    session: Session,
    event: PriceEvent,
    *,
    error: str,
    now: datetime,
    max_attempts: int,
    retry_backoff_seconds: float,
) -> None:
    event.last_error = error[:_MAX_ERROR_LENGTH]
    event.updated_at = now
    if event.attempts >= max_attempts:
        event.status = "failed"
    else:
        event.status = "pending"
        event.available_at = now + timedelta(seconds=retry_backoff_seconds)
    session.commit()


def recover_stuck_events(session: Session, *, now: datetime, stuck_after: timedelta) -> int:
    """Return interrupted events to 'pending' so they can be reclaimed.

    An event stays 'processing' if the worker that claimed it dies before
    finishing. This has no way to tell an in-progress attempt from an
    abandoned one except elapsed time, so any event still 'processing' past
    the threshold is treated as abandoned and made claimable again.
    """
    threshold = now - stuck_after
    statement = (
        update(PriceEvent)
        .where(PriceEvent.status == "processing", PriceEvent.processing_started_at < threshold)
        .values(status="pending", updated_at=now)
        .execution_options(synchronize_session=False)
    )
    result = session.execute(statement)
    session.commit()
    return result.rowcount
