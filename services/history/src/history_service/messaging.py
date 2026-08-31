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


class PGMQConsumer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.task: asyncio.Task[None] | None = None
        self.ready = False

    @property
    def is_ready(self) -> bool:
        return bool(self.ready and self.task is not None and not self.task.done())

    async def start(self) -> None:
        self.ready = False

        self.task = asyncio.create_task(
            self._run(),
            name="pgmq-history-consumer",
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
            "PGMQ consumer started",
            extra={
                "queue": self.settings.pgmq_queue,
            },
        )

        while True:
            try:
                processed = await asyncio.to_thread(self._process_next_message)
                self.ready = True

                if not processed:
                    await asyncio.sleep(self.settings.pgmq_poll_interval_seconds)

            except asyncio.CancelledError:
                raise

            except Exception:
                self.ready = False
                logger.exception("PGMQ consumer failed; retrying")

                await asyncio.sleep(self.settings.pgmq_poll_interval_seconds)

    def _process_next_message(self) -> bool:
        with SessionLocal() as session:
            result = session.execute(
                text(
                    """
                    SELECT *
                    FROM pgmq.read(
                        queue_name => :queue_name,
                        vt => :visibility_timeout,
                        qty => 1
                    )
                    """
                ),
                {
                    "queue_name": self.settings.pgmq_queue,
                    "visibility_timeout": self.settings.pgmq_visibility_timeout_seconds,
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
                "permanently invalid PGMQ message",
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
                "failed to persist PGMQ message",
                extra={
                    "msg_id": msg_id,
                    "read_count": read_count,
                },
            )

            if read_count >= self.settings.pgmq_max_attempts:
                logger.error(
                    "PGMQ message exceeded retry limit",
                    extra={
                        "msg_id": msg_id,
                        "read_count": read_count,
                    },
                )

                self._archive_message(msg_id)

            return

        self._archive_message(msg_id)

        logger.info(
            "PGMQ message persisted",
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
                    SELECT pgmq.archive(
                        queue_name => :queue_name,
                        msg_id => :msg_id
                    )
                    """
                ),
                {
                    "queue_name": self.settings.pgmq_queue,
                    "msg_id": msg_id,
                },
            ).scalar_one()

            session.commit()

            if not archived:
                raise RuntimeError(f"failed to archive PGMQ message {msg_id}")
