"""Transactional ingestion of normalized Provider blacklist snapshots."""

from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import ROUND_HALF_UP, Decimal
from typing import cast

from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session

from history_service.blacklist_repository import BlacklistRepository
from history_service.exceptions import BlacklistSnapshotConflictError
from history_service.models import BlacklistSnapshot, BlacklistSnapshotEntry
from history_service.schemas import BlacklistSnapshotDelivery
from history_service.service import HistoryUnavailableError


@dataclass(frozen=True)
class BlacklistIngestionResult:
    snapshot: BlacklistSnapshot
    created: bool
    received_at: datetime


class BlacklistIngestionService:
    """Persist one delivered snapshot, idempotently by delivery ID."""

    def __init__(
        self,
        *,
        repository: BlacklistRepository | None = None,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self.repository = repository or BlacklistRepository()
        self.clock = clock or (lambda: datetime.now(UTC))

    def ingest(
        self, session: Session, delivery: BlacklistSnapshotDelivery
    ) -> BlacklistIngestionResult:
        delivery_id = str(delivery.delivery_id)
        payload = delivery.snapshot
        try:
            existing = self.repository.get_by_delivery_id(session, delivery_id)
            if existing is not None:
                # Delivery identity is immutable and first-commit-wins. A repeated
                # delivery ID returns its original snapshot even if a later sender
                # supplies materially different content.
                return self._duplicate_result(existing)

            existing_generation = self.repository.get_by_provider_generation(
                session,
                provider=payload.provider,
                provider_generated_at=payload.generated_at,
            )
            if existing_generation is not None:
                raise BlacklistSnapshotConflictError

            received_at = self.clock()
            snapshot, entries = self._build_snapshot(session, delivery, received_at)
            try:
                self.repository.add_snapshot(session, snapshot, entries)
                session.commit()
            except IntegrityError as error:
                # The failed transaction must be cleared before any race reload.
                session.rollback()
                existing = self.repository.get_by_delivery_id(session, delivery_id)
                if existing is not None:
                    return self._duplicate_result(existing)
                existing_generation = self.repository.get_by_provider_generation(
                    session,
                    provider=payload.provider,
                    provider_generated_at=payload.generated_at,
                )
                if existing_generation is not None:
                    raise BlacklistSnapshotConflictError from None
                raise HistoryUnavailableError from error
            return BlacklistIngestionResult(
                snapshot=snapshot, created=True, received_at=received_at
            )
        except SQLAlchemyError as error:
            session.rollback()
            raise HistoryUnavailableError from error

    def _build_snapshot(
        self,
        session: Session,
        delivery: BlacklistSnapshotDelivery,
        received_at: datetime,
    ) -> tuple[BlacklistSnapshot, list[BlacklistSnapshotEntry]]:
        payload = delivery.snapshot
        unique_items = {item.ip_address: item for item in payload.items}
        current_addresses = set(unique_items)
        previous_addresses = self.repository.get_previous_snapshot_ip_addresses(
            session,
            provider=payload.provider,
            confidence_minimum=payload.request.confidence_minimum,
            requested_limit=payload.request.limit,
        )
        added_count: int | None = None
        removed_count: int | None = None
        turnover_percent: Decimal | None = None
        if previous_addresses is not None:
            added_count = len(current_addresses - previous_addresses)
            removed_count = len(previous_addresses - current_addresses)
            if current_addresses:
                turnover_percent = (
                    Decimal(added_count)
                    / Decimal(len(current_addresses))
                    * Decimal(100)
                ).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
        snapshot = BlacklistSnapshot(
            delivery_id=str(delivery.delivery_id),
            provider=payload.provider,
            provider_generated_at=payload.generated_at,
            fetched_at=payload.fetched_at,
            received_at=received_at,
            confidence_minimum=payload.request.confidence_minimum,
            requested_limit=payload.request.limit,
            returned_count=len(unique_items),
            added_count=added_count,
            removed_count=removed_count,
            turnover_percent=turnover_percent,
            rate_limit_limit=payload.rate_limit.limit,
            rate_limit_remaining=payload.rate_limit.remaining,
            rate_limit_reset_at=payload.rate_limit.reset_at,
            retry_after_seconds=payload.rate_limit.retry_after_seconds,
        )
        entries = [
            BlacklistSnapshotEntry(
                ip_address=item.ip_address,
                ip_version=item.ip_version,
                abuse_confidence_score=item.abuse_confidence_score,
                country_code=item.country_code,
                last_reported_at=item.last_reported_at,
            )
            for item in unique_items.values()
        ]
        return snapshot, entries

    def _duplicate_result(
        self, existing: BlacklistSnapshot
    ) -> BlacklistIngestionResult:
        received_at = self.repository._as_aware_utc(existing.received_at)
        if received_at is None:
            received_at = self.repository._as_aware_utc(existing.fetched_at)
        return BlacklistIngestionResult(
            snapshot=existing,
            created=False,
            received_at=cast(datetime, received_at),
        )


blacklist_ingestion_service = BlacklistIngestionService()


def get_blacklist_ingestion_service() -> BlacklistIngestionService:
    return blacklist_ingestion_service
