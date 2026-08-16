from datetime import UTC, datetime, timedelta

from sqlalchemy.orm import Session

from ui_service.repository import create_session, get_session, refresh_session


def _future(minutes: int = 30) -> datetime:
    return datetime.now(UTC) + timedelta(minutes=minutes)


def _past(minutes: int = 30) -> datetime:
    return datetime.now(UTC) - timedelta(minutes=minutes)


def test_get_session_returns_none_when_missing(db_session: Session) -> None:
    assert get_session(db_session, "does-not-exist") is None


def test_create_session_can_be_read_back(db_session: Session) -> None:
    create_session(db_session, "abc123", {"range": "30"}, _future())
    record = get_session(db_session, "abc123")
    assert record is not None
    assert record.preferences == {"range": "30"}


def test_expired_session_is_treated_as_missing(db_session: Session) -> None:
    create_session(db_session, "expired-one", {"range": "30"}, _past())
    assert get_session(db_session, "expired-one") is None


def test_refresh_session_extends_expiry(db_session: Session) -> None:
    create_session(db_session, "refresh-me", {"range": "30"}, _future(minutes=5))
    new_expiry = _future(minutes=30)
    refresh_session(db_session, "refresh-me", new_expiry)
    record = get_session(db_session, "refresh-me")
    assert record is not None
    assert record.expires_at.replace(tzinfo=UTC) == new_expiry