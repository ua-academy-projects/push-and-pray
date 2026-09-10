from __future__ import annotations

import asyncio
import json
import logging
from typing import Any

from pydantic import ValidationError
from google.cloud import pubsub_v1

from .config import Settings
from .database import SessionLocal
from .repository import insert_batch
from .schemas import ObservationEvent

logger = logging.getLogger(__name__)


class PubSubConsumer:
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
            name="pubsub-history-consumer",
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
            "Pub/Sub consumer started",
            extra={
                "subscription": self.settings.pubsub_subscription_id,
            },
        )

        while True:
            try:
                await asyncio.to_thread(self._consume)

            except asyncio.CancelledError:
                raise

            except Exception:
                logger.exception("Pub/Sub consumer failed; retrying")
                await asyncio.sleep(1)

    def _consume(self) -> None:
        subscriber = pubsub_v1.SubscriberClient()
        subscription = subscriber.subscription_path(
            self.settings.pubsub_project_id,
            self.settings.pubsub_subscription_id,
        )
        future = subscriber.subscribe(subscription, callback=self._handle_message)
        try:
            future.result()
        finally:
            future.cancel()
            subscriber.close()

    def _handle_message(
        self,
        message: pubsub_v1.subscriber.message.Message,
    ) -> None:
        try:
            event = ObservationEvent.model_validate(json.loads(message.data))

        except ValidationError as exc:
            logger.error(
                "permanently invalid Pub/Sub message",
                extra={
                    "message_id": message.message_id,
                    "error": str(exc),
                },
            )

            message.ack()

            return

        try:
            with SessionLocal() as session:
                inserted, duplicates = insert_batch(
                    session,
                    event.observations,
                )

        except Exception:
            logger.exception(
                "failed to persist Pub/Sub message",
                extra={
                    "message_id": message.message_id,
                },
            )

            message.nack()
            return

        message.ack()

        logger.info(
            "Pub/Sub message persisted",
            extra={
                "message_id": message.message_id,
                "event_key": event.event_key,
                "inserted": inserted,
                "duplicates": duplicates,
            },
        )
