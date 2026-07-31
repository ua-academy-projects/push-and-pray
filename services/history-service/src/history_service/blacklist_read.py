"""Read-only application service for persisted blacklist resources."""

from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Literal

from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from history_service.blacklist_repository import (
    BlacklistRepository,
)
from history_service.config import get_settings
from history_service.models import BlacklistSnapshot, BlacklistSyncRun
from history_service.schemas import (
    BlacklistAnalyticsQuery,
    BlacklistAnalyticsResponse,
    BlacklistAnalyticsSnapshot,
    BlacklistCountryCount,
    BlacklistCountryDistribution,
    BlacklistEntryPageQuery,
    BlacklistEntryQuery,
    BlacklistEntryResponse,
    BlacklistIpVersionCount,
    BlacklistLastError,
    BlacklistPage,
    BlacklistRequestPoint,
    BlacklistRequestSeriesQuery,
    BlacklistRequestSeriesResponse,
    BlacklistScoreBucket,
    BlacklistSnapshotChurn,
    BlacklistSnapshotList,
    BlacklistSnapshotListQuery,
    BlacklistSnapshotSummary,
    BlacklistStatusResponse,
    BlacklistTurnoverPoint,
    BlacklistTurnoverQuery,
    BlacklistTurnoverResponse,
)
from history_service.service import HistoryUnavailableError

FAILED_SYNC_STATUSES = {"failed", "rate_limited"}
SCORE_BUCKET_MINIMUMS = (*range(0, 100, 10), 95, 100)
TOP_COUNTRY_LIMIT = 5


class BlacklistReadService:
    """Read blacklist state from MariaDB without contacting Provider Service."""

    def __init__(
        self,
        repository: BlacklistRepository | None = None,
        *,
        stale_after_seconds: int = 43200,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self.repository = repository or BlacklistRepository()
        self.stale_after = timedelta(seconds=stale_after_seconds)
        self.clock = clock or (lambda: datetime.now(UTC))

    def status(self, session: Session) -> BlacklistStatusResponse:
        try:
            snapshot = self.repository.get_latest_snapshot(session)
            latest_run = self.repository.get_latest_sync_run(session)
            successful_run = self.repository.get_latest_successful_sync_run(session)
            if snapshot is not None:
                if self._run_predates_snapshot(latest_run, snapshot):
                    latest_run = None
                if self._run_predates_snapshot(successful_run, snapshot):
                    successful_run = None
            return self._status_response(snapshot, latest_run, successful_run)
        except SQLAlchemyError as error:
            raise HistoryUnavailableError from error

    def latest(
        self, session: Session, query: BlacklistEntryQuery
    ) -> BlacklistPage | None:
        try:
            snapshot = self.repository.get_latest_snapshot(session)
            if snapshot is None:
                return None
            return self._page(session, snapshot, query)
        except SQLAlchemyError as error:
            raise HistoryUnavailableError from error

    def snapshots(
        self, session: Session, query: BlacklistSnapshotListQuery
    ) -> BlacklistSnapshotList:
        try:
            records = self.repository.list_snapshots(
                session, limit=query.limit, offset=query.offset
            )
            total = self.repository.count_snapshots(session)
            return BlacklistSnapshotList(
                items=[BlacklistSnapshotSummary.from_record(item) for item in records],
                limit=query.limit,
                offset=query.offset,
                total=total,
            )
        except SQLAlchemyError as error:
            raise HistoryUnavailableError from error

    def snapshot(
        self, session: Session, snapshot_id: int, query: BlacklistEntryPageQuery
    ) -> BlacklistPage | None:
        try:
            snapshot = self.repository.get_snapshot(session, snapshot_id)
            if snapshot is None:
                return None
            return self._page(session, snapshot, query)
        except SQLAlchemyError as error:
            raise HistoryUnavailableError from error

    def analytics(
        self, session: Session, query: BlacklistAnalyticsQuery
    ) -> BlacklistAnalyticsResponse:
        """Aggregate bounded accepted-snapshot analytics from MariaDB only."""
        try:
            snapshot = self.repository.get_latest_snapshot(session)
            if snapshot is None:
                return self._empty_analytics()

            score_counts = {
                item.minimum: item.count
                for item in self.repository.score_distribution(
                    session, snapshot_id=snapshot.snapshot_id
                )
            }
            countries = self.repository.country_distribution(
                session, snapshot_id=snapshot.snapshot_id
            )
            version_counts = {
                item.ip_version: item.count
                for item in self.repository.ip_version_distribution(
                    session, snapshot_id=snapshot.snapshot_id
                )
            }
            churn = self.repository.snapshot_churn(
                session,
                provider=snapshot.provider,
                pair_limit=query.pair_limit,
            )
        except SQLAlchemyError as error:
            raise HistoryUnavailableError from error

        known_countries = [item for item in countries if item.country_code is not None]
        top_countries = known_countries[:TOP_COUNTRY_LIMIT]
        return BlacklistAnalyticsResponse(
            latest_snapshot=BlacklistAnalyticsSnapshot(
                snapshot_id=snapshot.snapshot_id,
                provider_generated_at=self._utc(snapshot.provider_generated_at),
                confidence_minimum=snapshot.confidence_minimum,
                requested_limit=snapshot.requested_limit,
                returned_count=snapshot.returned_count,
                result_limit_reached=(
                    snapshot.returned_count == snapshot.requested_limit
                ),
            ),
            score_distribution=[
                BlacklistScoreBucket(
                    minimum=minimum,
                    maximum=self._score_bucket_maximum(minimum),
                    count=score_counts.get(minimum, 0),
                )
                for minimum in SCORE_BUCKET_MINIMUMS
            ],
            top_countries=BlacklistCountryDistribution(
                items=[
                    BlacklistCountryCount(
                        country_code=item.country_code,
                        count=item.count,
                    )
                    for item in top_countries
                    if item.country_code is not None
                ],
                unknown_count=sum(
                    item.count for item in countries if item.country_code is None
                ),
                other_count=sum(
                    item.count for item in known_countries[TOP_COUNTRY_LIMIT:]
                ),
            ),
            ip_versions=[
                BlacklistIpVersionCount(
                    ip_version=ip_version,
                    count=version_counts.get(ip_version, 0),
                )
                for ip_version in (4, 6)
            ],
            snapshot_churn=[
                BlacklistSnapshotChurn(
                    current_snapshot_id=item.current_snapshot_id,
                    previous_snapshot_id=item.previous_snapshot_id,
                    added=item.added,
                    removed=item.removed,
                    retained=item.retained,
                )
                for item in churn
            ],
        )

    def turnover(
        self, session: Session, query: BlacklistTurnoverQuery
    ) -> BlacklistTurnoverResponse:
        """Return adaptive UTC buckets from persisted snapshot summaries only."""
        try:
            available_range = self.repository.turnover_data_range(
                session,
                provider="AbuseIPDB",
            )
        except SQLAlchemyError as error:
            raise HistoryUnavailableError from error

        requested_period = "custom" if query.from_ is not None else "all"
        if available_range is None:
            granularity = query.interval if query.interval != "auto" else "hour"
            return BlacklistTurnoverResponse(
                **{
                    "from": query.from_,
                    "to": query.to,
                    "interval": granularity,
                    "requested_period": requested_period,
                    "effective_start": None,
                    "effective_end": None,
                    "granularity": granularity,
                    "bucket_count": 0,
                    "points": [],
                }
            )

        available_start, available_end = available_range
        range_start = query.from_ or available_start
        range_end = query.to or available_end
        duration = range_end - range_start
        granularity = (
            query.interval
            if query.interval != "auto"
            else self._adaptive_granularity(duration)
        )
        query_end = (
            range_end if query.to is not None else range_end + timedelta(microseconds=1)
        )

        try:
            records = self.repository.turnover_buckets_between(
                session,
                provider="AbuseIPDB",
                from_=range_start,
                to=query_end,
                granularity=granularity,
            )
        except SQLAlchemyError as error:
            raise HistoryUnavailableError from error

        by_bucket = {self._utc(record.period_start): record for record in records}

        points: list[BlacklistTurnoverPoint] = []
        period_start = self._period_start(range_start, granularity)
        final_period = self._period_start(
            (
                range_end - timedelta(microseconds=1)
                if query.to is not None
                else range_end
            ),
            granularity,
        )
        while period_start <= final_period:
            bucket_record = by_bucket.get(period_start)
            points.append(
                BlacklistTurnoverPoint(
                    period_start=period_start,
                    turnover_percent=(
                        float(bucket_record.turnover_percent)
                        if bucket_record is not None
                        and bucket_record.turnover_percent is not None
                        else None
                    ),
                    added_count=(
                        bucket_record.added_count if bucket_record is not None else None
                    ),
                    removed_count=(
                        bucket_record.removed_count
                        if bucket_record is not None
                        else None
                    ),
                    snapshot_id=(
                        bucket_record.snapshot_id if bucket_record is not None else None
                    ),
                )
            )
            period_start = self._next_period(period_start, granularity)

        overlaps = available_end >= range_start and available_start < query_end
        effective_start = max(available_start, range_start) if overlaps else None
        effective_end = min(available_end, range_end) if overlaps else None
        return BlacklistTurnoverResponse(
            **{
                "from": range_start,
                "to": range_end,
                "interval": granularity,
                "requested_period": requested_period,
                "effective_start": effective_start,
                "effective_end": effective_end,
                "granularity": granularity,
                "bucket_count": len(points),
                "points": points,
            }
        )

    def request_series(
        self, session: Session, query: BlacklistRequestSeriesQuery
    ) -> BlacklistRequestSeriesResponse:
        """Return the latest successful delivered snapshots chronologically."""
        try:
            records = self.repository.latest_request_snapshots(
                session, provider="AbuseIPDB", limit=query.limit
            )
        except SQLAlchemyError as error:
            raise HistoryUnavailableError from error
        return BlacklistRequestSeriesResponse(
            limit=query.limit,
            points=[
                BlacklistRequestPoint(
                    request_id=record.delivery_id,
                    created_at=self._utc(record.provider_generated_at),
                    total_ips=record.returned_count,
                    new_ips=(
                        record.added_count
                        if record.added_count is not None
                        else record.returned_count
                    ),
                )
                for record in reversed(records)
                if record.delivery_id is not None
            ],
        )

    @staticmethod
    def _empty_analytics() -> BlacklistAnalyticsResponse:
        return BlacklistAnalyticsResponse(
            latest_snapshot=None,
            score_distribution=[],
            top_countries=BlacklistCountryDistribution(
                items=[], unknown_count=0, other_count=0
            ),
            ip_versions=[],
            snapshot_churn=[],
        )

    @staticmethod
    def _score_bucket_maximum(minimum: int) -> int:
        if minimum == 100:
            return 100
        if minimum == 95:
            return 99
        if minimum == 90:
            return 94
        return minimum + 9

    @staticmethod
    def _adaptive_granularity(
        duration: timedelta,
    ) -> Literal["hour", "day", "week", "month"]:
        if duration <= timedelta(hours=48):
            return "hour"
        if duration <= timedelta(days=31):
            return "day"
        if duration <= timedelta(days=180):
            return "week"
        return "month"

    @staticmethod
    def _next_period(period_start: datetime, interval: str) -> datetime:
        if interval == "hour":
            return period_start + timedelta(hours=1)
        if interval == "day":
            return period_start + timedelta(days=1)
        if interval == "week":
            return period_start + timedelta(weeks=1)
        if period_start.month == 12:
            return period_start.replace(year=period_start.year + 1, month=1, day=1)
        return period_start.replace(month=period_start.month + 1, day=1)

    @staticmethod
    def _period_start(value: datetime, interval: str) -> datetime:
        current = BlacklistReadService._utc(value)
        day_start = current.replace(hour=0, minute=0, second=0, microsecond=0)
        if interval == "hour":
            return current.replace(minute=0, second=0, microsecond=0)
        if interval == "day":
            return day_start
        if interval == "week":
            return day_start - timedelta(days=day_start.weekday())
        return day_start.replace(day=1)

    def _page(
        self,
        session: Session,
        snapshot: BlacklistSnapshot,
        query: BlacklistEntryPageQuery,
    ) -> BlacklistPage:
        filters = {
            "ip_version": getattr(query, "ip_version", None),
            "minimum_score": getattr(query, "minimum_score", None),
            "country_code": getattr(query, "country_code", None),
        }
        entries = self.repository.list_entries(
            session,
            snapshot_id=snapshot.snapshot_id,
            limit=query.limit,
            offset=query.offset,
            **filters,
        )
        total = self.repository.count_entries(
            session, snapshot_id=snapshot.snapshot_id, **filters
        )
        return BlacklistPage(
            snapshot=BlacklistSnapshotSummary.from_record(snapshot),
            items=[BlacklistEntryResponse.from_record(item) for item in entries],
            limit=query.limit,
            offset=query.offset,
            total=total,
        )

    def _status_response(
        self,
        snapshot: BlacklistSnapshot | None,
        latest_run: BlacklistSyncRun | None,
        successful_run: BlacklistSyncRun | None,
    ) -> BlacklistStatusResponse:
        now = self._now()
        fetched_at = self._utc(snapshot.fetched_at) if snapshot is not None else None
        data_stale = fetched_at is not None and now - fetched_at > self.stale_after
        sync_in_progress = latest_run is not None and latest_run.status == "running"
        latest_failed = (
            latest_run is not None and latest_run.status in FAILED_SYNC_STATUSES
        )
        if sync_in_progress:
            state = "syncing"
        elif snapshot is None:
            state = "empty"
        elif latest_failed:
            state = "degraded"
        elif data_stale:
            state = "stale"
        else:
            state = "ready"

        last_error = None
        if (
            latest_failed
            and latest_run is not None
            and latest_run.error_code is not None
        ):
            last_error = BlacklistLastError(
                code=latest_run.error_code,
                message="The latest synchronization attempt failed.",
            )
        return BlacklistStatusResponse(
            state=state,
            sync_in_progress=sync_in_progress,
            latest_snapshot_id=(snapshot.snapshot_id if snapshot is not None else None),
            latest_provider_generated_at=(
                self._utc(snapshot.provider_generated_at)
                if snapshot is not None
                else None
            ),
            latest_fetched_at=fetched_at,
            last_attempt_at=(
                self._utc(latest_run.started_at) if latest_run is not None else None
            ),
            last_success_at=(
                self._utc(successful_run.finished_at)
                if successful_run is not None and successful_run.finished_at is not None
                else fetched_at
            ),
            next_attempt_at=(
                self._utc(latest_run.next_attempt_at)
                if latest_run is not None and latest_run.next_attempt_at is not None
                else None
            ),
            rate_limit_limit=(
                latest_run.rate_limit_limit if latest_run is not None else None
            ),
            rate_limit_remaining=(
                latest_run.rate_limit_remaining if latest_run is not None else None
            ),
            rate_limit_reset_at=(
                self._utc(latest_run.rate_limit_reset_at)
                if latest_run is not None and latest_run.rate_limit_reset_at is not None
                else None
            ),
            data_stale=data_stale,
            last_error=last_error,
        )

    def _now(self) -> datetime:
        return self._utc(self.clock())

    def _run_predates_snapshot(
        self,
        run: BlacklistSyncRun | None,
        snapshot: BlacklistSnapshot,
    ) -> bool:
        """Ignore legacy pull-sync state superseded by RabbitMQ ingestion."""
        if run is None or snapshot.received_at is None:
            return False
        run_activity = run.finished_at or run.started_at
        return self._utc(run_activity) < self._utc(snapshot.received_at)

    @staticmethod
    def _utc(value: datetime) -> datetime:
        if value.tzinfo is None or value.utcoffset() is None:
            return value.replace(tzinfo=UTC)
        return value.astimezone(UTC)


blacklist_read_service = BlacklistReadService(
    stale_after_seconds=get_settings().blacklist_stale_after_seconds
)


def get_blacklist_read_service() -> BlacklistReadService:
    return blacklist_read_service
