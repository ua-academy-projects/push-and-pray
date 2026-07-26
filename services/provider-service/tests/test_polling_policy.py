from datetime import UTC, datetime, timedelta

from provider_service.polling_policy import PollingPolicy

NOW = datetime(2026, 7, 23, 9, 0, tzinfo=UTC)


def policy() -> PollingPolicy:
    return PollingPolicy(
        interval_seconds=21600,
        publish_initial_seconds=30,
        publish_maximum_seconds=900,
    )


def test_rate_limit_uses_all_valid_not_before_constraints() -> None:
    reset_at = NOW + timedelta(hours=2)

    result = policy().after_rate_limit(NOW, retry_after_seconds=3600, reset_at=reset_at)

    assert result == reset_at


def test_poll_and_publish_failures_use_independent_progressions() -> None:
    assert policy().after_poll_failure(NOW, attempt=2) == NOW + timedelta(minutes=15)
    assert policy().after_publish_failure(NOW, attempt=2) == NOW + timedelta(seconds=60)
    assert policy().after_publish_failure(NOW, attempt=20) == NOW + timedelta(
        seconds=900
    )
