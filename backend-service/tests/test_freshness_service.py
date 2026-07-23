from datetime import datetime, timedelta, timezone

from app.services.freshness_service import compute_freshness

NOW = datetime(2026, 7, 20, 12, 0, tzinfo=timezone.utc)


def test_no_successful_sync_ever_is_stale_with_time_unavailable_reason():
    is_stale, reason = compute_freshness(None, None, max_age_minutes=90, now=NOW)

    assert is_stale is True
    assert reason == "synchronization time unavailable"


def test_recent_successful_sync_is_fresh():
    last_success = NOW - timedelta(minutes=10)

    is_stale, reason = compute_freshness(last_success, "success", max_age_minutes=90, now=NOW)

    assert is_stale is False
    assert reason is None


def test_old_successful_sync_is_stale_with_overdue_reason():
    last_success = NOW - timedelta(minutes=200)

    is_stale, reason = compute_freshness(last_success, "success", max_age_minutes=90, now=NOW)

    assert is_stale is True
    assert reason == "synchronization overdue"


def test_recent_data_but_latest_attempt_failed_is_stale_with_failed_reason():
    last_success = NOW - timedelta(minutes=5)

    is_stale, reason = compute_freshness(last_success, "failed", max_age_minutes=90, now=NOW)

    assert is_stale is True
    assert reason == "latest synchronization failed"


def test_overdue_takes_priority_over_latest_attempt_status():
    last_success = NOW - timedelta(minutes=200)

    is_stale, reason = compute_freshness(last_success, "success", max_age_minutes=90, now=NOW)

    assert is_stale is True
    assert reason == "synchronization overdue"


def test_boundary_exactly_at_max_age_is_not_yet_stale():
    last_success = NOW - timedelta(minutes=90)

    is_stale, _ = compute_freshness(last_success, "success", max_age_minutes=90, now=NOW)

    assert is_stale is False
