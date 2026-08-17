from __future__ import annotations

import asyncio
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy.orm import Session, sessionmaker

from history_service import worker as worker_module
from history_service.config import Settings
from history_service.events import (
    claim_next_event,
    mark_failed,
    mark_processed,
    mark_retry_or_failed,
    recover_stuck_events,
)
from history_service.models import PriceEvent, PriceObservation
from history_service.worker import PostgresEventWorker, process_claimed_event


def valid_payload() -> dict:
    return {
        "schema_version": 1,
        "observations": [
            {
                "instrument_code": "WTI_USD_BBL",
                "instrument_name": "WTI Crude Oil",
                "category": "crude_oil",
                "price": "68.42",
                "currency": "USD",
                "unit": "USD per barrel",
                "source": "OilPriceAPI",
                "source_series_id": "WTI_USD",
                "source_period": "2026-07-27",
                "source_observed_at": "2026-07-27T05:59:00Z",
                "scheduled_for": "2026-07-27T06:00:00Z",
                "fetched_at": "2026-07-27T06:00:02Z",
                "source_url": "https://api.oilpriceapi.com/v1/prices/latest",
                "raw_data": {"code": "WTI_USD", "price": "68.42"},
            }
        ],
    }


def make_event(session: Session, *, payload: dict | None = None, **overrides) -> PriceEvent:
    defaults = {
        "id": uuid.uuid4(),
        "event_key": f"test:{uuid.uuid4()}",
        "schema_version": 1,
        "payload": payload if payload is not None else valid_payload(),
        "status": "pending",
        "attempts": 0,
        "available_at": datetime.now(UTC) - timedelta(seconds=1),
    }
    defaults.update(overrides)
    event = PriceEvent(**defaults)
    session.add(event)
    session.commit()
    return event


# --- claim_next_event -------------------------------------------------------


def test_claim_next_event_returns_none_when_no_pending(db_session: Session) -> None:
    assert claim_next_event(db_session, now=datetime.now(UTC)) is None


def test_claim_next_event_claims_pending_and_marks_processing(db_session: Session) -> None:
    event = make_event(db_session)
    now = datetime.now(UTC)

    claimed = claim_next_event(db_session, now=now)

    assert claimed is not None
    assert claimed.id == event.id
    assert claimed.status == "processing"
    assert claimed.attempts == 1
    assert claimed.processing_started_at == now


def test_claim_next_event_ignores_events_not_yet_available(db_session: Session) -> None:
    make_event(db_session, available_at=datetime.now(UTC) + timedelta(minutes=5))

    assert claim_next_event(db_session, now=datetime.now(UTC)) is None


def test_claim_next_event_ignores_non_pending_events(db_session: Session) -> None:
    make_event(db_session, status="processing")

    assert claim_next_event(db_session, now=datetime.now(UTC)) is None


# --- mark_processed / mark_failed / mark_retry_or_failed --------------------


def test_mark_processed_clears_error_and_sets_processed_at(db_session: Session) -> None:
    event = make_event(db_session, status="processing", last_error="boom")
    now = datetime.now(UTC)

    mark_processed(db_session, event, now=now)

    assert event.status == "processed"
    assert event.processed_at == now
    assert event.last_error is None


def test_mark_failed_records_error_and_does_not_retry(db_session: Session) -> None:
    event = make_event(db_session, status="processing", attempts=1)

    mark_failed(db_session, event, error="invalid schema", now=datetime.now(UTC))

    assert event.status == "failed"
    assert event.last_error == "invalid schema"


def test_mark_retry_or_failed_retries_below_max_attempts(db_session: Session) -> None:
    event = make_event(db_session, status="processing", attempts=1)
    now = datetime.now(UTC)

    mark_retry_or_failed(
        db_session,
        event,
        error="db unavailable",
        now=now,
        max_attempts=5,
        retry_backoff_seconds=30,
    )

    assert event.status == "pending"
    assert event.last_error == "db unavailable"
    assert event.available_at == now + timedelta(seconds=30)


def test_mark_retry_or_failed_fails_permanently_at_max_attempts(db_session: Session) -> None:
    event = make_event(db_session, status="processing", attempts=5)

    mark_retry_or_failed(
        db_session,
        event,
        error="db unavailable",
        now=datetime.now(UTC),
        max_attempts=5,
        retry_backoff_seconds=30,
    )

    assert event.status == "failed"


# --- recover_stuck_events ----------------------------------------------------


def test_recover_stuck_events_reclaims_interrupted_events(db_session: Session) -> None:
    now = datetime.now(UTC)
    event = make_event(
        db_session,
        status="processing",
        processing_started_at=now - timedelta(minutes=10),
    )

    recovered = recover_stuck_events(db_session, now=now, stuck_after=timedelta(minutes=5))

    assert recovered == 1
    db_session.refresh(event)
    assert event.status == "pending"


def test_recover_stuck_events_leaves_recent_processing_alone(db_session: Session) -> None:
    now = datetime.now(UTC)
    event = make_event(
        db_session,
        status="processing",
        processing_started_at=now - timedelta(seconds=5),
    )

    recovered = recover_stuck_events(db_session, now=now, stuck_after=timedelta(minutes=5))

    assert recovered == 0
    db_session.refresh(event)
    assert event.status == "processing"


# --- process_claimed_event ---------------------------------------------------


def test_process_claimed_event_persists_observations_then_marks_processed(
    db_session: Session,
) -> None:
    make_event(db_session)
    event = claim_next_event(db_session, now=datetime.now(UTC))
    assert event is not None

    process_claimed_event(db_session, event, Settings())

    assert event.status == "processed"
    assert event.processed_at is not None
    observations = db_session.query(PriceObservation).all()
    assert len(observations) == 1
    assert observations[0].instrument_code == "WTI_USD_BBL"


def test_process_claimed_event_reuses_idempotent_insert_for_duplicates(
    db_session: Session,
) -> None:
    make_event(db_session)
    first = claim_next_event(db_session, now=datetime.now(UTC))
    process_claimed_event(db_session, first, Settings())

    make_event(db_session)  # same instrument_code/scheduled_for as the first event
    second = claim_next_event(db_session, now=datetime.now(UTC))
    process_claimed_event(db_session, second, Settings())

    assert second.status == "processed"
    assert db_session.query(PriceObservation).count() == 1


def test_process_claimed_event_marks_permanently_invalid_event_as_failed(
    db_session: Session,
) -> None:
    payload = valid_payload()
    payload["schema_version"] = 2
    make_event(db_session, payload=payload)
    event = claim_next_event(db_session, now=datetime.now(UTC))
    assert event is not None

    process_claimed_event(db_session, event, Settings())

    assert event.status == "failed"
    assert event.last_error
    assert db_session.query(PriceObservation).count() == 0


def test_process_claimed_event_retries_transient_persistence_failure(
    db_session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    make_event(db_session)
    event = claim_next_event(db_session, now=datetime.now(UTC))
    assert event is not None

    def _boom(*_args, **_kwargs):
        raise RuntimeError("database is temporarily unavailable")

    monkeypatch.setattr(worker_module, "insert_observations", _boom)
    settings = Settings(history_worker_max_attempts=5, history_worker_retry_backoff_seconds=30)

    process_claimed_event(db_session, event, settings)

    assert event.status == "pending"
    assert event.attempts == 1
    assert "temporarily unavailable" in event.last_error
    assert event.available_at > datetime.now(UTC)
    assert db_session.query(PriceObservation).count() == 0


def test_process_claimed_event_fails_permanently_after_max_attempts(
    db_session: Session, monkeypatch: pytest.MonkeyPatch
) -> None:
    make_event(db_session, attempts=4)
    event = claim_next_event(db_session, now=datetime.now(UTC))
    assert event is not None
    assert event.attempts == 5

    def _boom(*_args, **_kwargs):
        raise RuntimeError("still down")

    monkeypatch.setattr(worker_module, "insert_observations", _boom)

    process_claimed_event(db_session, event, Settings(history_worker_max_attempts=5))

    assert event.status == "failed"


# --- PostgresEventWorker._tick -----------------------------------------------


def test_tick_processes_one_pending_event(
    db_session: Session, session_factory: sessionmaker[Session], monkeypatch: pytest.MonkeyPatch
) -> None:
    make_event(db_session)
    monkeypatch.setattr(worker_module, "SessionLocal", session_factory)
    instance = PostgresEventWorker(Settings())

    assert instance._tick() is True

    with session_factory() as session:
        event = session.query(PriceEvent).one()
        assert event.status == "processed"


def test_tick_returns_false_when_nothing_to_do(
    session_factory: sessionmaker[Session], monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(worker_module, "SessionLocal", session_factory)
    instance = PostgresEventWorker(Settings())

    assert instance._tick() is False


def test_tick_recovers_and_processes_an_interrupted_event(
    db_session: Session, session_factory: sessionmaker[Session], monkeypatch: pytest.MonkeyPatch
) -> None:
    now = datetime.now(UTC)
    make_event(
        db_session,
        status="processing",
        processing_started_at=now - timedelta(seconds=1000),
        available_at=now - timedelta(seconds=1000),
    )
    monkeypatch.setattr(worker_module, "SessionLocal", session_factory)
    settings = Settings(history_worker_stuck_after_seconds=60)
    instance = PostgresEventWorker(settings)

    assert instance._tick() is True

    with session_factory() as session:
        event = session.query(PriceEvent).one()
        assert event.status == "processed"
        assert event.attempts == 1


# --- PostgresEventWorker lifecycle -------------------------------------------


def test_worker_reports_ready_only_while_its_loop_task_is_running() -> None:
    async def scenario() -> None:
        instance = PostgresEventWorker(Settings(history_worker_poll_interval_seconds=0.01))
        instance._tick = lambda: False  # avoid touching the database

        assert instance.is_ready is False
        await instance.start()
        await asyncio.sleep(0.05)
        assert instance.is_ready is True

        await instance.stop()
        assert instance.is_ready is False

    asyncio.run(scenario())
