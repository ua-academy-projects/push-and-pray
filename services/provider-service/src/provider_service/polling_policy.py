"""Deterministic scheduling policy for polling and outbox delivery."""

from datetime import UTC, datetime, timedelta


def aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("Scheduling timestamps must include a timezone.")
    return value.astimezone(UTC)


class PollingPolicy:
    """Calculate independent bounded polling and delivery retry times."""

    temporary_delays = (300, 900, 1800, 3600)

    def __init__(
        self,
        *,
        interval_seconds: int,
        publish_initial_seconds: int,
        publish_maximum_seconds: int,
    ) -> None:
        self.interval_seconds = interval_seconds
        self.publish_initial_seconds = publish_initial_seconds
        self.publish_maximum_seconds = publish_maximum_seconds

    def after_success(
        self,
        now: datetime,
        *,
        remaining: int | None,
        reset_at: datetime | None,
    ) -> datetime:
        current = aware_utc(now)
        scheduled = current + timedelta(seconds=self.interval_seconds)
        if remaining == 0 and reset_at is not None:
            scheduled = max(scheduled, aware_utc(reset_at))
        return scheduled

    def after_rate_limit(
        self,
        now: datetime,
        *,
        retry_after_seconds: int | None,
        reset_at: datetime | None,
    ) -> datetime:
        current = aware_utc(now)
        constraints = [current + timedelta(seconds=self.temporary_delays[0])]
        if retry_after_seconds is not None:
            constraints.append(current + timedelta(seconds=retry_after_seconds))
        if reset_at is not None:
            constraints.append(aware_utc(reset_at))
        return max(constraints)

    def after_poll_failure(self, now: datetime, *, attempt: int) -> datetime:
        current = aware_utc(now)
        index = min(max(attempt, 1), len(self.temporary_delays)) - 1
        return current + timedelta(seconds=self.temporary_delays[index])

    def after_publish_failure(self, now: datetime, *, attempt: int) -> datetime:
        current = aware_utc(now)
        exponent = min(max(attempt, 1) - 1, 30)
        delay = min(
            self.publish_initial_seconds * (2**exponent),
            self.publish_maximum_seconds,
        )
        return current + timedelta(seconds=delay)
