from __future__ import annotations

import asyncio
import logging
from typing import Any

from pydantic import ValidationError
from sqlalchemy import text

from .config import Settings
from .database import SessionLocal
from .repository import insert_batch
from .schemas import ObservationEvent

logger = logging.getLogger(__name__)


class QueueConsumer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.task: asyncio.Task[None] | None = None
        self.ready = False

    @property
    def is_ready(self) -> bool:
        return bool(self.ready and self.task is not None and not self.task.done())

    async def start(self) -> None:
        self.ready = True

        self.task = asyncio.create_task(
            self._run(),
            name="queue-history-consumer",
        )

    async def stop(self) -> None:
        self.ready = False

        if self.task is not None:
            self.task.cancel()

            try:
                await self.task
            except asyncio.CancelledError:
                pass

    async def _run(self) -> None:
        logger.info(
            "queue consumer started",
            extra={
                "queue": self.settings.queue_name,
            },
        )

        while True:
            try:
                processed = await asyncio.to_thread(self._process_next_message)

                if not processed:
                    await asyncio.sleep(self.settings.queue_poll_interval_seconds)

            except asyncio.CancelledError:
                raise

            except Exception:
                logger.exception("queue consumer failed; retrying")

                await asyncio.sleep(self.settings.queue_poll_interval_seconds)

    def _process_next_message(self) -> bool:
        with SessionLocal() as session:
            result = session.execute(
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
                    "visibility_timeout": self.settings.queue_visibility_timeout_seconds,
                },
            )

            row = result.mappings().first()

            if row is None:
                session.commit()
                return False

            message = dict(row)

            session.commit()

        self._handle_message(
            msg_id=message["msg_id"],
            read_count=message["read_ct"],
            message=message["message"],
        )

        return True

    def _handle_message(
        self,
        msg_id: int,
        read_count: int,
        message: dict[str, Any],
    ) -> None:
        try:
            event = ObservationEvent.model_validate(message)

        except ValidationError as exc:
            logger.error(
                "permanently invalid queue message",
                extra={
                    "msg_id": msg_id,
                    "error": str(exc),
                },
            )

            self._archive_message(msg_id)

            return

        try:
            with SessionLocal() as session:
                inserted, duplicates = insert_batch(
                    session,
                    event.observations,
                )

        except Exception:
            logger.exception(
                "failed to persist queue message",
                extra={
                    "msg_id": msg_id,
                    "read_count": read_count,
                },
            )

            if read_count >= self.settings.queue_max_attempts:
                logger.error(
                    "queue message exceeded retry limit",
                    extra={
                        "msg_id": msg_id,
                        "read_count": read_count,
                    },
                )

                self._archive_message(msg_id)

            return

        self._archive_message(msg_id)

        logger.info(
            "queue message persisted",
            extra={
                "msg_id": msg_id,
                "read_count": read_count,
                "event_key": event.event_key,
                "inserted": inserted,
                "duplicates": duplicates,
            },
        )

    def _archive_message(
        self,
        msg_id: int,
    ) -> None:
        with SessionLocal() as session:
            archived = session.execute(
                text(
                    """
                    WITH moved AS (
                        DELETE FROM observation_queue
                        WHERE msg_id = :msg_id
                        RETURNING msg_id, message, read_ct, enqueued_at
                    )
                    INSERT INTO observation_queue_archive
                        (msg_id, message, read_ct, enqueued_at)
                    SELECT msg_id, message, read_ct, enqueued_at FROM moved
                    RETURNING msg_id
                    """
                ),
                {
                    "msg_id": msg_id,
                },
            ).scalar_one_or_none()

            session.commit()

            if not archived:
                raise RuntimeError(f"failed to archive queue message {msg_id}")
