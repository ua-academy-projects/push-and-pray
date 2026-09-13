from __future__ import annotations

import json
import os
import time
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from history_service import messaging
from history_service.config import Settings

QUEUE = "price_observations"
DATABASE_URL = os.getenv("QUEUE_TEST_SQLALCHEMY_URL")


@pytest.fixture()
def database_engine():
    if not DATABASE_URL:
        pytest.skip("QUEUE_TEST_SQLALCHEMY_URL is not configured")

    engine = create_engine(
        DATABASE_URL,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=5,
    )

    with engine.begin() as connection:
        connection.execute(text("TRUNCATE TABLE price_observations"))

        connection.execute(text("DELETE FROM published_queue_events"))

        connection.execute(text("DELETE FROM observation_queue"))

        connection.execute(text("TRUNCATE TABLE observation_queue_archive"))

    yield engine

    engine.dispose()


def valid_event() -> dict:
    return {
        "schema_version": 1,
        "event_key": ("oil-prices:2026-08-18T12:00:00Z"),
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
                "source_period": "2026-08-18",
                "source_observed_at": ("2026-08-18T11:59:00Z"),
                "scheduled_for": ("2026-08-18T12:00:00Z"),
                "fetched_at": ("2026-08-18T12:00:02Z"),
                "source_url": ("https://api.oilpriceapi.com/v1/prices/latest"),
                "raw_data": {
                    "code": "WTI_USD",
                    "price": "68.42",
                },
            }
        ],
    }


def send_message(engine, payload: dict) -> int:
    with engine.begin() as connection:
        message_id = connection.execute(
            text(
                """
                INSERT INTO observation_queue (message)
                VALUES (CAST(:payload AS jsonb))
                RETURNING msg_id
                """
            ),
            {
                "payload": json.dumps(payload),
            },
        ).scalar_one()

    return int(message_id)


def read_message(
    engine,
    visibility_timeout: int,
):
    with engine.begin() as connection:
        return (
            connection.execute(
                text(
                    """
                    UPDATE observation_queue
                    SET vt = now() + make_interval(secs => :visibility_timeout),
                        read_ct = read_ct + 1
                    WHERE msg_id = (
                        SELECT msg_id
                        FROM observation_queue
                        WHERE vt <= now()
                        ORDER BY msg_id
                        FOR UPDATE SKIP LOCKED
                        LIMIT 1
                    )
                    RETURNING msg_id, read_ct, message
                    """
                ),
                {
                    "visibility_timeout": visibility_timeout,
                },
            )
            .mappings()
            .first()
        )


def archive_message(
    engine,
    message_id: int,
) -> None:
    with engine.begin() as connection:
        archived = connection.execute(
            text(
                """
                WITH moved AS (
                    DELETE FROM observation_queue
                    WHERE msg_id = :message_id
                    RETURNING msg_id, message, read_ct, enqueued_at
                )
                INSERT INTO observation_queue_archive
                    (msg_id, message, read_ct, enqueued_at)
                SELECT msg_id, message, read_ct, enqueued_at FROM moved
                RETURNING msg_id
                """
            ),
            {
                "message_id": message_id,
            },
        ).scalar_one_or_none()

    assert archived == message_id


def test_queue_table_exists(
    database_engine,
) -> None:
    with database_engine.connect() as connection:
        queue_ready = connection.execute(
            text("SELECT to_regclass('public.observation_queue') IS NOT NULL")
        ).scalar_one()

        archive_ready = connection.execute(
            text(
                "SELECT to_regclass('public.observation_queue_archive') IS NOT NULL"
            )
        ).scalar_one()

    assert queue_ready is True
    assert archive_ready is True


def test_two_consumers_cannot_read_same_message(
    database_engine,
) -> None:
    message_id = send_message(
        database_engine,
        valid_event(),
    )

    barrier = Barrier(2)

    def consume_once():
        barrier.wait(timeout=5)

        row = read_message(
            database_engine,
            visibility_timeout=10,
        )

        if row is None:
            return None

        return row["msg_id"]

    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [
            executor.submit(consume_once),
            executor.submit(consume_once),
        ]

        results = [future.result() for future in futures]

    received = [result for result in results if result is not None]

    assert received == [message_id]

    archive_message(
        database_engine,
        message_id,
    )


def test_message_returns_after_visibility_timeout(
    database_engine,
) -> None:
    message_id = send_message(
        database_engine,
        valid_event(),
    )

    first = read_message(
        database_engine,
        visibility_timeout=1,
    )

    assert first is not None
    assert first["msg_id"] == message_id
    assert first["read_ct"] == 1

    hidden = read_message(
        database_engine,
        visibility_timeout=1,
    )

    assert hidden is None

    time.sleep(1.2)

    second = read_message(
        database_engine,
        visibility_timeout=5,
    )

    assert second is not None
    assert second["msg_id"] == message_id
    assert second["read_ct"] == 2

    archive_message(
        database_engine,
        message_id,
    )


def test_history_persists_observations_exactly_once(
    database_engine,
    monkeypatch,
) -> None:
    session_factory = sessionmaker(
        bind=database_engine,
        expire_on_commit=False,
    )

    monkeypatch.setattr(
        messaging,
        "SessionLocal",
        session_factory,
    )

    settings = Settings(
        database_url=DATABASE_URL,
        queue_name=QUEUE,
        queue_visibility_timeout_seconds=5,
        queue_poll_interval_seconds=0.1,
        queue_max_attempts=5,
    )

    consumer = messaging.QueueConsumer(settings)

    payload = valid_event()

    first_message_id = send_message(
        database_engine,
        payload,
    )

    assert consumer._process_next_message() is True

    with database_engine.connect() as connection:
        observation_count = connection.execute(
            text(
                """
                SELECT COUNT(*)
                FROM price_observations
                """
            )
        ).scalar_one()

        active_count = connection.execute(
            text(
                """
                SELECT COUNT(*)
                FROM observation_queue
                WHERE msg_id = :message_id
                """
            ),
            {
                "message_id": first_message_id,
            },
        ).scalar_one()

    assert observation_count == 1
    assert active_count == 0

    send_message(
        database_engine,
        payload,
    )

    assert consumer._process_next_message() is True

    with database_engine.connect() as connection:
        final_observation_count = connection.execute(
            text(
                """
                    SELECT COUNT(*)
                    FROM price_observations
                    """
            )
        ).scalar_one()

        archived_count = connection.execute(
            text(
                """
                SELECT COUNT(*)
                FROM observation_queue_archive
                WHERE message->>'event_key'
                    = :event_key
                """
            ),
            {
                "event_key": payload["event_key"],
            },
        ).scalar_one()

    assert final_observation_count == 1
    assert archived_count == 2
