from datetime import datetime, timezone


def compute_freshness(
    last_success_at: datetime | None,
    latest_attempt_status: str | None,
    max_age_minutes: int,
    now: datetime | None = None,
) -> tuple[bool, str | None]:
    """Always Europe/Kyiv-aware in spirit (compares timezone-aware instants) -- never naive
    datetimes. `latest_attempt_status` lets a very recent *failed* attempt surface as a
    warning even when the still-displayed data (from an earlier success) isn't old yet."""
    now = now or datetime.now(timezone.utc)

    if last_success_at is None:
        return True, "synchronization time unavailable"

    age_minutes = (now - last_success_at).total_seconds() / 60
    if age_minutes > max_age_minutes:
        return True, "synchronization overdue"

    if latest_attempt_status == "failed":
        return True, "latest synchronization failed"

    return False, None
