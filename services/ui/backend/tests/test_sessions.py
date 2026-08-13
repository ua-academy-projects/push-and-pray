import pytest
from pydantic import ValidationError

from ui_service.sessions import SessionPreferences, resolve_session_id


def test_default_preferences_select_all_on_first_visit() -> None:
    preferences = SessionPreferences()
    assert preferences.selected is None
    assert preferences.range == "30"
    assert preferences.layout == "compare"
    assert preferences.style == "line"
    assert preferences.smooth is True


def test_preferences_validate_supported_controls() -> None:
    with pytest.raises(ValidationError):
        SessionPreferences(range="999")


def test_invalid_session_cookie_is_rotated() -> None:
    session_id, created = resolve_session_id("not-valid")
    assert created is True
    assert len(session_id) >= 32


def test_valid_session_cookie_is_reused() -> None:
    session_id = "a" * 43
    resolved, created = resolve_session_id(session_id)
    assert resolved == session_id
    assert created is False
