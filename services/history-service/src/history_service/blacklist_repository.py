"""Persistence operations for complete blacklist snapshots and sync runs."""

from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal
from typing import cast, overload

from sqlalchemy import DateTime, case, func, select, text
from sqlalchemy import cast as sql_cast
from sqlalchemy.orm import Session

from history_service.models import (
    BlacklistSnapshot,
    BlacklistSnapshotEntry,
    BlacklistSyncRun,
)

TEMPORARY_SYNC_ERROR_CODES = {
    "PROVIDER_SERVICE_UNAVAILABLE",
    "UPSTREAM_UNAVAILABLE",
    "UPSTREAM_TIMEOUT",
    "DATABASE_UNAVAILABLE",
}


@dataclass(frozen=True)
class PersistedBlacklistSchedule:
    status: str
    next_attempt_at: datetime | None
    next_attempt_reason: str | None
    rate_limit_remaining: int | None
    rate_limit_reset_at: datetime | None


@dataclass(frozen=True)
class ScoreBucketCount:
    minimum: int
    count: int


@dataclass(frozen=True)
class CountryCount:
    country_code: str | None
    count: int


@dataclass(frozen=True)
class IpVersionCount:
    ip_version: int
    count: int


@dataclass(frozen=True)
class SnapshotChurnCount:
    current_snapshot_id: int
    previous_snapshot_id: int
    added: int
    removed: int
    retained: int


@dataclass(frozen=True)
class TurnoverBucketSummary:
    snapshot_id: int
    period_start: datetime
    turnover_percent: Decimal | None
    added_count: int | None
    removed_count: int | None


class BlacklistRepository:
    """Query and mutate blacklist records through a supplied session."""

    def add_snapshot(
        self,
        session: Session,
        snapshot: BlacklistSnapshot,
        entries: list[BlacklistSnapshotEntry],
    ) -> BlacklistSnapshot:
        snapshot.provider_generated_at = self._as_mariadb_utc(
            snapshot.provider_generated_at
        )
        snapshot.fetched_at = self._as_mariadb_utc(snapshot.fetched_at)
        snapshot.received_at = self._as_mariadb_utc(snapshot.received_at)
        snapshot.rate_limit_reset_at = self._as_mariadb_utc(
            snapshot.rate_limit_reset_at
        )
        for entry in entries:
            entry.last_reported_at = self._as_mariadb_utc(entry.last_reported_at)
        snapshot.entries.extend(entries)
        session.add(snapshot)
        session.flush()
        return snapshot

    def get_by_delivery_id(
        self, session: Session, delivery_id: str
    ) -> BlacklistSnapshot | None:
        statement = select(BlacklistSnapshot).where(
            BlacklistSnapshot.delivery_id == delivery_id
        )
        return session.scalar(statement)

    def get_by_provider_generation(
        self,
        session: Session,
        *,
        provider: str,
        provider_generated_at: datetime,
    ) -> BlacklistSnapshot | None:
        statement = select(BlacklistSnapshot).where(
            BlacklistSnapshot.provider == provider,
            BlacklistSnapshot.provider_generated_at
            == self._as_mariadb_utc(provider_generated_at),
        )
        return session.scalar(statement)

    def get_previous_snapshot_ip_addresses(
        self,
        session: Session,
        *,
        provider: str,
        confidence_minimum: int,
        requested_limit: int,
    ) -> set[str] | None:
        previous_id = session.scalar(
            select(BlacklistSnapshot.snapshot_id)
            .where(
                BlacklistSnapshot.provider == provider,
                BlacklistSnapshot.confidence_minimum == confidence_minimum,
                BlacklistSnapshot.requested_limit == requested_limit,
            )
            .order_by(BlacklistSnapshot.snapshot_id.desc())
            .limit(1)
        )
        if previous_id is None:
            return None
        statement = select(BlacklistSnapshotEntry.ip_address).where(
            BlacklistSnapshotEntry.snapshot_id == previous_id
        )
        return set(session.scalars(statement))

    def get_snapshot(
        self, session: Session, snapshot_id: int
    ) -> BlacklistSnapshot | None:
        return session.get(BlacklistSnapshot, snapshot_id)

    def get_latest_snapshot(self, session: Session) -> BlacklistSnapshot | None:
        statement = (
            select(BlacklistSnapshot)
            .order_by(BlacklistSnapshot.snapshot_id.desc())
            .limit(1)
        )
        return session.scalar(statement)

    def list_snapshots(
        self, session: Session, *, limit: int, offset: int
    ) -> list[BlacklistSnapshot]:
        statement = (
            select(BlacklistSnapshot)
            .order_by(BlacklistSnapshot.snapshot_id.desc())
            .limit(limit)
            .offset(offset)
        )
        return list(session.scalars(statement))

    def count_snapshots(self, session: Session) -> int:
        statement = select(func.count()).select_from(BlacklistSnapshot)
        return session.scalar(statement) or 0

    def turnover_data_range(
        self,
        session: Session,
        *,
        provider: str,
    ) -> tuple[datetime, datetime] | None:
        statement = select(
            func.min(BlacklistSnapshot.provider_generated_at),
            func.max(BlacklistSnapshot.provider_generated_at),
        ).where(BlacklistSnapshot.provider == provider)
        earliest, latest = session.execute(statement).one()
        if earliest is None or latest is None:
            return None
        return (
            cast(datetime, self._as_aware_utc(earliest)),
            cast(datetime, self._as_aware_utc(latest)),
        )

    def turnover_buckets_between(
        self,
        session: Session,
        *,
        provider: str,
        from_: datetime,
        to: datetime,
        granularity: str,
    ) -> list[TurnoverBucketSummary]:
        period_start = self._turnover_period_expression(granularity)
        ranked = (
            select(
                BlacklistSnapshot.snapshot_id.label("snapshot_id"),
                period_start.label("period_start"),
                BlacklistSnapshot.turnover_percent.label("turnover_percent"),
                BlacklistSnapshot.added_count.label("added_count"),
                BlacklistSnapshot.removed_count.label("removed_count"),
                func.row_number()
                .over(
                    partition_by=period_start,
                    order_by=(
                        BlacklistSnapshot.provider_generated_at.desc(),
                        BlacklistSnapshot.snapshot_id.desc(),
                    ),
                )
                .label("bucket_rank"),
            )
            .where(
                BlacklistSnapshot.provider == provider,
                BlacklistSnapshot.provider_generated_at >= self._as_mariadb_utc(from_),
                BlacklistSnapshot.provider_generated_at < self._as_mariadb_utc(to),
            )
            .subquery("ranked_turnover_snapshots")
        )
        statement = (
            select(
                ranked.c.snapshot_id,
                ranked.c.period_start,
                ranked.c.turnover_percent,
                ranked.c.added_count,
                ranked.c.removed_count,
            )
            .where(ranked.c.bucket_rank == 1)
            .order_by(ranked.c.period_start.asc())
        )
        return [
            TurnoverBucketSummary(
                snapshot_id=int(snapshot_id),
                period_start=cast(datetime, self._as_aware_utc(period_start)),
                turnover_percent=turnover_percent,
                added_count=added_count,
                removed_count=removed_count,
            )
            for (
                snapshot_id,
                period_start,
                turnover_percent,
                added_count,
                removed_count,
            ) in session.execute(statement)
        ]

    @staticmethod
    def _turnover_period_expression(granularity: str):
        timestamp = BlacklistSnapshot.provider_generated_at
        if granularity == "hour":
            return sql_cast(func.date_format(timestamp, "%Y-%m-%d %H:00:00"), DateTime)
        if granularity == "day":
            return sql_cast(func.date(timestamp), DateTime)
        if granularity == "week":
            return sql_cast(
                func.timestampadd(
                    text("DAY"), -func.weekday(timestamp), func.date(timestamp)
                ),
                DateTime,
            )
        if granularity == "month":
            return sql_cast(func.date_format(timestamp, "%Y-%m-01 00:00:00"), DateTime)
        raise ValueError(f"Unsupported turnover granularity: {granularity}")

    def list_entries(
        self,
        session: Session,
        *,
        snapshot_id: int,
        limit: int,
        offset: int,
        ip_version: int | None = None,
        minimum_score: int | None = None,
        country_code: str | None = None,
    ) -> list[BlacklistSnapshotEntry]:
        statement = select(BlacklistSnapshotEntry).where(
            BlacklistSnapshotEntry.snapshot_id == snapshot_id
        )
        statement = self._filter_entries(
            statement,
            ip_version=ip_version,
            minimum_score=minimum_score,
            country_code=country_code,
        )
        statement = (
            statement.order_by(
                BlacklistSnapshotEntry.abuse_confidence_score.desc(),
                BlacklistSnapshotEntry.last_reported_at.desc(),
                BlacklistSnapshotEntry.ip_address.asc(),
            )
            .limit(limit)
            .offset(offset)
        )
        return list(session.scalars(statement))

    def count_entries(
        self,
        session: Session,
        *,
        snapshot_id: int,
        ip_version: int | None = None,
        minimum_score: int | None = None,
        country_code: str | None = None,
    ) -> int:
        statement = (
            select(func.count())
            .select_from(BlacklistSnapshotEntry)
            .where(BlacklistSnapshotEntry.snapshot_id == snapshot_id)
        )
        statement = self._filter_entries(
            statement,
            ip_version=ip_version,
            minimum_score=minimum_score,
            country_code=country_code,
        )
        return session.scalar(statement) or 0

    def score_distribution(
        self, session: Session, *, snapshot_id: int
    ) -> list[ScoreBucketCount]:
        bucket_minimum = case(
            (BlacklistSnapshotEntry.abuse_confidence_score == 100, 100),
            (BlacklistSnapshotEntry.abuse_confidence_score >= 95, 95),
            else_=func.floor(BlacklistSnapshotEntry.abuse_confidence_score / 10) * 10,
        ).label("bucket_minimum")
        statement = (
            select(bucket_minimum, func.count().label("entry_count"))
            .where(BlacklistSnapshotEntry.snapshot_id == snapshot_id)
            .group_by(bucket_minimum)
            .order_by(bucket_minimum.asc())
        )
        return [
            ScoreBucketCount(minimum=int(minimum), count=int(count))
            for minimum, count in session.execute(statement)
        ]

    def country_distribution(
        self, session: Session, *, snapshot_id: int
    ) -> list[CountryCount]:
        statement = (
            select(
                BlacklistSnapshotEntry.country_code,
                func.count().label("entry_count"),
            )
            .where(BlacklistSnapshotEntry.snapshot_id == snapshot_id)
            .group_by(BlacklistSnapshotEntry.country_code)
            .order_by(
                func.count().desc(),
                BlacklistSnapshotEntry.country_code.asc(),
            )
        )
        return [
            CountryCount(country_code=country_code, count=int(count))
            for country_code, count in session.execute(statement)
        ]

    def ip_version_distribution(
        self, session: Session, *, snapshot_id: int
    ) -> list[IpVersionCount]:
        statement = (
            select(
                BlacklistSnapshotEntry.ip_version,
                func.count().label("entry_count"),
            )
            .where(BlacklistSnapshotEntry.snapshot_id == snapshot_id)
            .group_by(BlacklistSnapshotEntry.ip_version)
            .order_by(BlacklistSnapshotEntry.ip_version.asc())
        )
        return [
            IpVersionCount(ip_version=int(ip_version), count=int(count))
            for ip_version, count in session.execute(statement)
        ]

    def snapshot_churn(
        self, session: Session, *, provider: str, pair_limit: int
    ) -> list[SnapshotChurnCount]:
        recent = (
            select(
                BlacklistSnapshot.snapshot_id.label("current_snapshot_id"),
                func.lead(BlacklistSnapshot.snapshot_id)
                .over(order_by=BlacklistSnapshot.snapshot_id.desc())
                .label("previous_snapshot_id"),
            )
            .where(BlacklistSnapshot.provider == provider)
            .order_by(BlacklistSnapshot.snapshot_id.desc())
            .limit(pair_limit + 1)
            .cte("recent_analytics_snapshots")
        )
        pairs = (
            select(recent.c.current_snapshot_id, recent.c.previous_snapshot_id)
            .where(recent.c.previous_snapshot_id.is_not(None))
            .limit(pair_limit)
            .cte("analytics_snapshot_pairs")
        )
        current_entry = BlacklistSnapshotEntry.__table__.alias("current_entry")
        previous_match = BlacklistSnapshotEntry.__table__.alias("previous_match")
        previous_entry = BlacklistSnapshotEntry.__table__.alias("previous_entry")
        current_match = BlacklistSnapshotEntry.__table__.alias("current_match")

        current_counts = (
            select(
                pairs.c.current_snapshot_id,
                pairs.c.previous_snapshot_id,
                func.sum(
                    case(
                        (
                            current_entry.c.entry_id.is_not(None)
                            & previous_match.c.entry_id.is_(None),
                            1,
                        ),
                        else_=0,
                    )
                ).label("added"),
                func.sum(
                    case(
                        (previous_match.c.entry_id.is_not(None), 1),
                        else_=0,
                    )
                ).label("retained"),
            )
            .select_from(
                pairs.outerjoin(
                    current_entry,
                    current_entry.c.snapshot_id == pairs.c.current_snapshot_id,
                ).outerjoin(
                    previous_match,
                    (previous_match.c.snapshot_id == pairs.c.previous_snapshot_id)
                    & (previous_match.c.ip_address == current_entry.c.ip_address),
                )
            )
            .group_by(pairs.c.current_snapshot_id, pairs.c.previous_snapshot_id)
            .cte("analytics_current_counts")
        )
        removed_counts = (
            select(
                pairs.c.current_snapshot_id,
                pairs.c.previous_snapshot_id,
                func.sum(
                    case(
                        (
                            previous_entry.c.entry_id.is_not(None)
                            & current_match.c.entry_id.is_(None),
                            1,
                        ),
                        else_=0,
                    )
                ).label("removed"),
            )
            .select_from(
                pairs.outerjoin(
                    previous_entry,
                    previous_entry.c.snapshot_id == pairs.c.previous_snapshot_id,
                ).outerjoin(
                    current_match,
                    (current_match.c.snapshot_id == pairs.c.current_snapshot_id)
                    & (current_match.c.ip_address == previous_entry.c.ip_address),
                )
            )
            .group_by(pairs.c.current_snapshot_id, pairs.c.previous_snapshot_id)
            .cte("analytics_removed_counts")
        )
        statement = (
            select(
                current_counts.c.current_snapshot_id,
                current_counts.c.previous_snapshot_id,
                current_counts.c.added,
                removed_counts.c.removed,
                current_counts.c.retained,
            )
            .join(
                removed_counts,
                (
                    removed_counts.c.current_snapshot_id
                    == current_counts.c.current_snapshot_id
                )
                & (
                    removed_counts.c.previous_snapshot_id
                    == current_counts.c.previous_snapshot_id
                ),
            )
            .order_by(current_counts.c.current_snapshot_id.desc())
        )
        return [
            SnapshotChurnCount(
                current_snapshot_id=int(current_snapshot_id),
                previous_snapshot_id=int(previous_snapshot_id),
                added=int(added or 0),
                removed=int(removed or 0),
                retained=int(retained or 0),
            )
            for (
                current_snapshot_id,
                previous_snapshot_id,
                added,
                removed,
                retained,
            ) in session.execute(statement)
        ]

    @staticmethod
    def _filter_entries(
        statement,
        *,
        ip_version: int | None,
        minimum_score: int | None,
        country_code: str | None,
    ):
        if ip_version is not None:
            statement = statement.where(BlacklistSnapshotEntry.ip_version == ip_version)
        if minimum_score is not None:
            statement = statement.where(
                BlacklistSnapshotEntry.abuse_confidence_score >= minimum_score
            )
        if country_code is not None:
            statement = statement.where(
                BlacklistSnapshotEntry.country_code == country_code
            )
        return statement

    def add_sync_run(self, session: Session, run: BlacklistSyncRun) -> BlacklistSyncRun:
        for field_name in (
            "started_at",
            "finished_at",
            "rate_limit_reset_at",
            "next_attempt_at",
        ):
            setattr(run, field_name, self._as_mariadb_utc(getattr(run, field_name)))
        session.add(run)
        session.flush()
        return run

    def get_latest_sync_run(self, session: Session) -> BlacklistSyncRun | None:
        statement = (
            select(BlacklistSyncRun)
            .order_by(BlacklistSyncRun.sync_run_id.desc())
            .limit(1)
        )
        return session.scalar(statement)

    def get_latest_successful_sync_run(
        self, session: Session
    ) -> BlacklistSyncRun | None:
        statement = (
            select(BlacklistSyncRun)
            .where(BlacklistSyncRun.status.in_(("succeeded", "duplicate")))
            .order_by(BlacklistSyncRun.sync_run_id.desc())
            .limit(1)
        )
        return session.scalar(statement)

    def get_sync_run_for_update(
        self, session: Session, sync_run_id: int
    ) -> BlacklistSyncRun | None:
        statement = (
            select(BlacklistSyncRun)
            .where(BlacklistSyncRun.sync_run_id == sync_run_id)
            .with_for_update()
        )
        return session.scalar(statement)

    def count_consecutive_temporary_failures(
        self, session: Session, *, before_sync_run_id: int, maximum: int
    ) -> int:
        statement = (
            select(BlacklistSyncRun.status, BlacklistSyncRun.error_code)
            .where(BlacklistSyncRun.sync_run_id < before_sync_run_id)
            .order_by(BlacklistSyncRun.sync_run_id.desc())
            .limit(maximum)
        )
        count = 0
        for status, error_code in session.execute(statement):
            if status != "failed" or error_code not in TEMPORARY_SYNC_ERROR_CODES:
                break
            count += 1
        return count

    def get_persisted_schedule(
        self, session: Session
    ) -> PersistedBlacklistSchedule | None:
        run = self.get_latest_sync_run(session)
        if run is None:
            return None
        return PersistedBlacklistSchedule(
            status=run.status,
            next_attempt_at=self._as_aware_utc(run.next_attempt_at),
            next_attempt_reason=run.next_attempt_reason,
            rate_limit_remaining=run.rate_limit_remaining,
            rate_limit_reset_at=self._as_aware_utc(run.rate_limit_reset_at),
        )

    @staticmethod
    @overload
    def _as_mariadb_utc(value: datetime) -> datetime: ...

    @staticmethod
    @overload
    def _as_mariadb_utc(value: None) -> None: ...

    @staticmethod
    def _as_mariadb_utc(value: datetime | None) -> datetime | None:
        if value is None:
            return None
        if value.tzinfo is None or value.utcoffset() is None:
            raise ValueError("Blacklist timestamps must include a timezone.")
        return value.astimezone(UTC).replace(tzinfo=None)

    @staticmethod
    def _as_aware_utc(value: datetime | None) -> datetime | None:
        return value.replace(tzinfo=UTC) if value is not None else None
