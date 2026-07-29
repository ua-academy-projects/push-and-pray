from datetime import UTC, datetime, timedelta
from decimal import Decimal
from unittest.mock import ANY, Mock

import pytest
from history_service.blacklist_read import BlacklistReadService
from history_service.blacklist_repository import (
    BlacklistRepository,
    CountryCount,
    IpVersionCount,
    ScoreBucketCount,
    SnapshotChurnCount,
    TurnoverBucketSummary,
)
from history_service.models import (
    BlacklistSnapshot,
    BlacklistSnapshotEntry,
    BlacklistSyncRun,
)
from history_service.schemas import (
    BlacklistAnalyticsQuery,
    BlacklistEntryQuery,
    BlacklistSnapshotListQuery,
    BlacklistTurnoverQuery,
)
from sqlalchemy.orm import Session

NOW = datetime(2026, 7, 22, 12, 0, tzinfo=UTC)


def snapshot(*, snapshot_id: int = 42, age_hours: int = 1) -> BlacklistSnapshot:
    generated = NOW - timedelta(hours=age_hours)
    return BlacklistSnapshot(
        snapshot_id=snapshot_id,
        provider="AbuseIPDB",
        provider_generated_at=generated.replace(tzinfo=None),
        fetched_at=(generated + timedelta(seconds=2)).replace(tzinfo=None),
        received_at=(generated + timedelta(seconds=3)).replace(tzinfo=None),
        confidence_minimum=90,
        requested_limit=1000,
        returned_count=2,
    )


def entry(address: str, score: int) -> BlacklistSnapshotEntry:
    return BlacklistSnapshotEntry(
        entry_id=score,
        snapshot_id=42,
        ip_address=address,
        ip_version=6 if ":" in address else 4,
        abuse_confidence_score=score,
        country_code="US",
        last_reported_at=NOW.replace(tzinfo=None),
    )


def sync_run(status: str, *, error_code: str | None = None) -> BlacklistSyncRun:
    return BlacklistSyncRun(
        sync_run_id=7,
        request_id="6f5aa064-43e8-4dbb-a544-d60b68af5cbd",
        status=status,
        started_at=(NOW - timedelta(minutes=1)).replace(tzinfo=None),
        finished_at=NOW.replace(tzinfo=None) if status != "running" else None,
        confidence_minimum=90,
        requested_limit=1000,
        next_attempt_at=(NOW + timedelta(hours=6)).replace(tzinfo=None),
        rate_limit_limit=5,
        rate_limit_remaining=4,
        error_code=error_code,
        error_message="database details that must never be returned",
    )


@pytest.mark.parametrize(
    ("record", "run", "age_hours", "expected_state", "stale"),
    [
        (None, None, 1, "empty", False),
        (None, sync_run("running"), 1, "syncing", False),
        (snapshot(), sync_run("succeeded"), 1, "ready", False),
        (snapshot(), sync_run("running"), 1, "syncing", False),
        (snapshot(age_hours=13), sync_run("succeeded"), 13, "stale", True),
        (
            snapshot(),
            sync_run("failed", error_code="UPSTREAM_TIMEOUT"),
            1,
            "degraded",
            False,
        ),
    ],
)
def test_status_states(
    record: BlacklistSnapshot | None,
    run: BlacklistSyncRun | None,
    age_hours: int,
    expected_state: str,
    stale: bool,
) -> None:
    repository = Mock()
    repository.get_latest_snapshot.return_value = record
    repository.get_latest_sync_run.return_value = run
    repository.get_latest_successful_sync_run.return_value = (
        sync_run("succeeded") if record is not None else None
    )
    service = BlacklistReadService(
        repository, stale_after_seconds=43200, clock=lambda: NOW
    )

    result = service.status(Mock())

    assert result.state == expected_state
    assert result.data_stale is stale
    if expected_state == "degraded":
        assert result.latest_snapshot_id == 42
        assert result.last_error is not None
        assert result.last_error.code == "UPSTREAM_TIMEOUT"
        assert "database details" not in result.last_error.message


@pytest.mark.parametrize("legacy_status", ["running", "failed"])
def test_new_rabbitmq_snapshot_supersedes_legacy_sync_status(
    legacy_status: str,
) -> None:
    repository = Mock()
    latest = snapshot(age_hours=0)
    latest.received_at = (NOW + timedelta(minutes=1)).replace(tzinfo=None)
    legacy = sync_run(legacy_status, error_code="UPSTREAM_TIMEOUT")
    repository.get_latest_snapshot.return_value = latest
    repository.get_latest_sync_run.return_value = legacy
    repository.get_latest_successful_sync_run.return_value = sync_run("succeeded")
    service = BlacklistReadService(repository, clock=lambda: NOW)

    result = service.status(Mock())

    assert result.state == "ready"
    assert result.sync_in_progress is False
    assert result.last_error is None
    assert result.last_success_at == latest.fetched_at.replace(tzinfo=UTC)


def test_latest_snapshot_filters_paginates_and_uses_constant_query_count() -> None:
    repository = Mock()
    repository.get_latest_snapshot.return_value = snapshot()
    repository.list_entries.return_value = [
        entry("8.8.8.8", 100),
        entry("2606:4700:4700::1111", 95),
    ]
    repository.count_entries.return_value = 12
    service = BlacklistReadService(repository, clock=lambda: NOW)
    query = BlacklistEntryQuery(
        limit=2, offset=4, ip_version=4, minimum_score=95, country_code="US"
    )

    result = service.latest(Mock(), query)

    assert result is not None
    assert len(result.items) == 2
    assert result.total == 12
    repository.get_latest_snapshot.assert_called_once()
    repository.list_entries.assert_called_once_with(
        repository.get_latest_snapshot.call_args.args[0],
        snapshot_id=42,
        limit=2,
        offset=4,
        ip_version=4,
        minimum_score=95,
        country_code="US",
    )
    repository.count_entries.assert_called_once()
    assert (
        sum(
            method.call_count
            for method in (
                repository.get_latest_snapshot,
                repository.list_entries,
                repository.count_entries,
            )
        )
        == 3
    )


def test_snapshot_lists_are_paginated_and_ordered_by_repository() -> None:
    repository = Mock()
    repository.list_snapshots.return_value = [snapshot(snapshot_id=43), snapshot()]
    repository.count_snapshots.return_value = 9
    service = BlacklistReadService(repository, clock=lambda: NOW)

    result = service.snapshots(Mock(), BlacklistSnapshotListQuery(limit=2, offset=2))

    assert [item.snapshot_id for item in result.items] == [43, 42]
    assert result.total == 9
    repository.list_snapshots.assert_called_once()
    repository.count_snapshots.assert_called_once()


def test_empty_latest_and_missing_snapshot_return_none() -> None:
    repository = Mock()
    repository.get_latest_snapshot.return_value = None
    repository.get_snapshot.return_value = None
    service = BlacklistReadService(repository, clock=lambda: NOW)
    query = BlacklistEntryQuery()

    assert service.latest(Mock(), query) is None
    assert service.snapshot(Mock(), 999, query) is None
    repository.list_entries.assert_not_called()
    repository.count_entries.assert_not_called()


def test_analytics_returns_stable_buckets_unknown_other_and_bounded_churn() -> None:
    repository = Mock()
    repository.get_latest_snapshot.return_value = snapshot()
    repository.get_latest_snapshot.return_value.returned_count = 1000
    repository.score_distribution.return_value = [
        ScoreBucketCount(minimum=90, count=10),
        ScoreBucketCount(minimum=95, count=20),
        ScoreBucketCount(minimum=100, count=970),
    ]
    repository.country_distribution.return_value = [
        CountryCount(country_code="US", count=300),
        CountryCount(country_code=None, count=200),
        CountryCount(country_code="CA", count=150),
        CountryCount(country_code="DE", count=100),
        CountryCount(country_code="FR", count=90),
        CountryCount(country_code="GB", count=80),
        CountryCount(country_code="NL", count=50),
        CountryCount(country_code="AU", count=30),
    ]
    repository.ip_version_distribution.return_value = [
        IpVersionCount(ip_version=4, count=900),
        IpVersionCount(ip_version=6, count=100),
    ]
    repository.snapshot_churn.return_value = [
        SnapshotChurnCount(
            current_snapshot_id=42,
            previous_snapshot_id=41,
            added=20,
            removed=10,
            retained=980,
        )
    ]
    service = BlacklistReadService(repository, clock=lambda: NOW)

    result = service.analytics(Mock(), BlacklistAnalyticsQuery(pair_limit=7))

    assert result.latest_snapshot is not None
    assert result.latest_snapshot.result_limit_reached is True
    assert [(item.minimum, item.maximum) for item in result.score_distribution] == [
        (0, 9),
        (10, 19),
        (20, 29),
        (30, 39),
        (40, 49),
        (50, 59),
        (60, 69),
        (70, 79),
        (80, 89),
        (90, 94),
        (95, 99),
        (100, 100),
    ]
    assert result.score_distribution[0].count == 0
    assert result.score_distribution[-1].count == 970
    assert [item.country_code for item in result.top_countries.items] == [
        "US",
        "CA",
        "DE",
        "FR",
        "GB",
    ]
    assert result.top_countries.unknown_count == 200
    assert result.top_countries.other_count == 80
    assert [(item.ip_version, item.count) for item in result.ip_versions] == [
        (4, 900),
        (6, 100),
    ]
    assert result.snapshot_churn[0].retained == 980
    repository.snapshot_churn.assert_called_once_with(
        repository.get_latest_snapshot.call_args.args[0],
        provider="AbuseIPDB",
        pair_limit=7,
    )


def test_analytics_query_count_is_constant_and_empty_state_short_circuits() -> None:
    repository = Mock()
    repository.get_latest_snapshot.return_value = snapshot()
    repository.score_distribution.return_value = [
        ScoreBucketCount(minimum=100, count=2)
    ]
    repository.country_distribution.return_value = [
        CountryCount(country_code="US", count=2)
    ]
    repository.ip_version_distribution.return_value = [
        IpVersionCount(ip_version=4, count=2)
    ]
    repository.snapshot_churn.return_value = []
    service = BlacklistReadService(repository, clock=lambda: NOW)

    populated = service.analytics(Mock(), BlacklistAnalyticsQuery(pair_limit=30))

    assert populated.latest_snapshot is not None
    analytics_methods = (
        repository.get_latest_snapshot,
        repository.score_distribution,
        repository.country_distribution,
        repository.ip_version_distribution,
        repository.snapshot_churn,
    )
    assert sum(method.call_count for method in analytics_methods) == 5

    repository.reset_mock()
    repository.get_latest_snapshot.return_value = None
    empty = service.analytics(Mock(), BlacklistAnalyticsQuery(pair_limit=30))

    assert empty.latest_snapshot is None
    assert empty.score_distribution == []
    assert empty.top_countries.unknown_count == 0
    assert empty.ip_versions == []
    assert empty.snapshot_churn == []
    repository.get_latest_snapshot.assert_called_once()
    repository.score_distribution.assert_not_called()
    repository.snapshot_churn.assert_not_called()


def turnover_query(
    *,
    from_: datetime,
    to: datetime,
    interval: str,
) -> BlacklistTurnoverQuery:
    return BlacklistTurnoverQuery.model_validate(
        {"from": from_, "to": to, "interval": interval}
    )


def test_hourly_turnover_uses_latest_snapshot_and_emits_missing_buckets() -> None:
    repository = Mock()
    repository.turnover_data_range.return_value = (
        datetime(2026, 7, 22, 12, 10, tzinfo=UTC),
        datetime(2026, 7, 22, 14, 0, tzinfo=UTC),
    )
    repository.turnover_buckets_between.return_value = [
        TurnoverBucketSummary(
            snapshot_id=40,
            period_start=datetime(2026, 7, 22, 12, 0, tzinfo=UTC),
            turnover_percent=Decimal("10.00"),
            added_count=10,
            removed_count=5,
        ),
        TurnoverBucketSummary(
            snapshot_id=41,
            period_start=datetime(2026, 7, 22, 12, 0, tzinfo=UTC),
            turnover_percent=Decimal("20.00"),
            added_count=20,
            removed_count=8,
        ),
        TurnoverBucketSummary(
            snapshot_id=42,
            period_start=datetime(2026, 7, 22, 14, 0, tzinfo=UTC),
            turnover_percent=None,
            added_count=None,
            removed_count=None,
        ),
    ]
    service = BlacklistReadService(repository)
    query = turnover_query(
        from_=datetime(2026, 7, 22, 12, 0, tzinfo=UTC),
        to=datetime(2026, 7, 22, 15, 0, tzinfo=UTC),
        interval="hour",
    )

    result = service.turnover(Mock(), query)

    assert [point.period_start.hour for point in result.points] == [12, 13, 14]
    assert result.points[0].snapshot_id == 41
    assert result.points[0].turnover_percent == 20.0
    assert result.points[1].model_dump() == {
        "period_start": datetime(2026, 7, 22, 13, 0, tzinfo=UTC),
        "turnover_percent": None,
        "added_count": None,
        "removed_count": None,
        "snapshot_id": None,
    }
    assert result.points[2].snapshot_id == 42
    assert result.points[2].turnover_percent is None


@pytest.mark.parametrize(
    ("interval", "from_", "to", "expected"),
    [
        (
            "day",
            datetime(2026, 7, 22, 16, 0, tzinfo=UTC),
            datetime(2026, 7, 24, 1, 0, tzinfo=UTC),
            [
                datetime(2026, 7, 22, 0, 0, tzinfo=UTC),
                datetime(2026, 7, 23, 0, 0, tzinfo=UTC),
                datetime(2026, 7, 24, 0, 0, tzinfo=UTC),
            ],
        ),
        (
            "week",
            datetime(2026, 7, 22, 16, 0, tzinfo=UTC),
            datetime(2026, 8, 4, 1, 0, tzinfo=UTC),
            [
                datetime(2026, 7, 20, 0, 0, tzinfo=UTC),
                datetime(2026, 7, 27, 0, 0, tzinfo=UTC),
                datetime(2026, 8, 3, 0, 0, tzinfo=UTC),
            ],
        ),
    ],
)
def test_daily_and_weekly_bucket_boundaries(
    interval: str,
    from_: datetime,
    to: datetime,
    expected: list[datetime],
) -> None:
    repository = Mock()
    repository.turnover_data_range.return_value = (from_, to)
    repository.turnover_buckets_between.return_value = []
    result = BlacklistReadService(repository).turnover(
        Mock(), turnover_query(from_=from_, to=to, interval=interval)
    )

    assert [point.period_start for point in result.points] == expected


def test_turnover_query_normalizes_offset_boundaries_to_utc() -> None:
    repository = Mock()
    repository.turnover_data_range.return_value = (
        datetime(2026, 7, 22, 0, 30, tzinfo=UTC),
        datetime(2026, 7, 22, 2, 0, tzinfo=UTC),
    )
    repository.turnover_buckets_between.return_value = []
    query = BlacklistTurnoverQuery.model_validate(
        {
            "from": "2026-07-22T03:30:00+03:00",
            "to": "2026-07-22T05:30:00+03:00",
            "interval": "hour",
        }
    )

    result = BlacklistReadService(repository).turnover(Mock(), query)

    assert [point.period_start for point in result.points] == [
        datetime(2026, 7, 22, 0, 0, tzinfo=UTC),
        datetime(2026, 7, 22, 1, 0, tzinfo=UTC),
        datetime(2026, 7, 22, 2, 0, tzinfo=UTC),
    ]


@pytest.mark.parametrize(
    ("duration", "expected_granularity"),
    [
        (timedelta(hours=48), "hour"),
        (timedelta(hours=49), "day"),
        (timedelta(days=31), "day"),
        (timedelta(days=32), "week"),
        (timedelta(days=180), "week"),
        (timedelta(days=181), "month"),
    ],
)
def test_automatic_turnover_selects_granularity_for_requested_range(
    duration: timedelta,
    expected_granularity: str,
) -> None:
    start = datetime(2026, 1, 1, tzinfo=UTC)
    end = start + duration
    repository = Mock()
    repository.turnover_data_range.return_value = (start, end)
    repository.turnover_buckets_between.return_value = []

    result = BlacklistReadService(repository).turnover(
        Mock(),
        turnover_query(from_=start, to=end, interval="auto"),
    )

    assert result.interval == expected_granularity
    assert result.granularity == expected_granularity
    assert result.requested_period == "custom"
    assert result.bucket_count == len(result.points)
    repository.turnover_buckets_between.assert_called_once_with(
        ANY,
        provider="AbuseIPDB",
        from_=start,
        to=end,
        granularity=expected_granularity,
    )


def test_all_available_turnover_uses_data_bounds_and_month_boundaries() -> None:
    start = datetime(2025, 12, 20, 8, 30, tzinfo=UTC)
    end = datetime(2026, 7, 2, 14, 0, tzinfo=UTC)
    repository = Mock()
    repository.turnover_data_range.return_value = (start, end)
    repository.turnover_buckets_between.return_value = [
        TurnoverBucketSummary(
            snapshot_id=42,
            period_start=datetime(2026, 7, 1, tzinfo=UTC),
            turnover_percent=Decimal("12.50"),
            added_count=5,
            removed_count=2,
        )
    ]

    result = BlacklistReadService(repository).turnover(
        Mock(), BlacklistTurnoverQuery(period="all")
    )

    assert result.requested_period == "all"
    assert result.from_ == start
    assert result.to == end
    assert result.effective_start == start
    assert result.effective_end == end
    assert result.granularity == "month"
    assert [point.period_start for point in result.points] == [
        datetime(2025, 12, 1, tzinfo=UTC),
        datetime(2026, 1, 1, tzinfo=UTC),
        datetime(2026, 2, 1, tzinfo=UTC),
        datetime(2026, 3, 1, tzinfo=UTC),
        datetime(2026, 4, 1, tzinfo=UTC),
        datetime(2026, 5, 1, tzinfo=UTC),
        datetime(2026, 6, 1, tzinfo=UTC),
        datetime(2026, 7, 1, tzinfo=UTC),
    ]
    assert result.points[-1].snapshot_id == 42


def test_turnover_empty_dataset_returns_metadata_without_querying_buckets() -> None:
    repository = Mock()
    repository.turnover_data_range.return_value = None

    result = BlacklistReadService(repository).turnover(
        Mock(), BlacklistTurnoverQuery(period="all")
    )

    assert result.requested_period == "all"
    assert result.effective_start is None
    assert result.effective_end is None
    assert result.bucket_count == 0
    assert result.points == []
    repository.turnover_buckets_between.assert_not_called()


def test_partial_dataset_preserves_ordered_empty_requested_buckets() -> None:
    requested_start = datetime(2026, 7, 1, tzinfo=UTC)
    requested_end = datetime(2026, 7, 5, tzinfo=UTC)
    available_start = datetime(2026, 7, 2, 12, tzinfo=UTC)
    available_end = datetime(2026, 7, 3, 12, tzinfo=UTC)
    repository = Mock()
    repository.turnover_data_range.return_value = (available_start, available_end)
    repository.turnover_buckets_between.return_value = [
        TurnoverBucketSummary(
            snapshot_id=20,
            period_start=datetime(2026, 7, 3, tzinfo=UTC),
            turnover_percent=Decimal("8.00"),
            added_count=4,
            removed_count=3,
        )
    ]

    result = BlacklistReadService(repository).turnover(
        Mock(),
        turnover_query(
            from_=requested_start,
            to=requested_end,
            interval="auto",
        ),
    )

    assert result.effective_start == available_start
    assert result.effective_end == available_end
    assert result.bucket_count == 4
    assert [point.period_start.day for point in result.points] == [1, 2, 3, 4]
    assert [point.snapshot_id for point in result.points] == [None, None, 20, None]
    assert result.points[0].added_count is None


def test_analytics_executes_five_database_queries_independent_of_pair_limit() -> None:
    session = Mock(spec=Session)
    session.scalar.return_value = snapshot()
    session.execute.side_effect = [
        [(100, 2)],
        [("US", 2)],
        [(4, 2)],
        [],
    ]
    service = BlacklistReadService(BlacklistRepository(), clock=lambda: NOW)

    result = service.analytics(session, BlacklistAnalyticsQuery(pair_limit=30))

    assert result.latest_snapshot is not None
    assert session.scalar.call_count == 1
    assert session.execute.call_count == 4
    assert session.scalar.call_count + session.execute.call_count == 5
    for call in session.execute.call_args_list:
        sql = str(call.args[0])
        assert "ip_check_history" not in sql
