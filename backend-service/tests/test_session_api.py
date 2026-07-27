import pytest

from app.cache.redis_client import get_redis_client
from app.config import get_settings

TEST_REDIS_URL = "redis://localhost:6379/15"


@pytest.fixture(autouse=True)
def _redis_test_db(monkeypatch):
    """Points REDIS_URL at a dedicated logical DB (15) so these tests never touch whatever a
    developer has running in DB 0, and flushes it after every test -- same spirit as
    conftest.py's _clean_tables for Postgres, adapted to Redis's numbered-DB model."""
    monkeypatch.setenv("REDIS_URL", TEST_REDIS_URL)
    get_settings.cache_clear()
    get_redis_client.cache_clear()
    yield
    get_redis_client().flushdb()
    get_settings.cache_clear()
    get_redis_client.cache_clear()


def test_get_session_without_header_creates_new_session(client):
    response = client.get("/api/session")

    assert response.status_code == 200
    body = response.json()
    assert body["session_id"]
    assert body["state"] == {
        "averages_range": {"preset": "30", "range_from": None, "range_to": None},
        "history_range": {"preset": "30", "range_from": None, "range_to": None},
        "history_open": False,
    }


def test_get_session_with_known_id_returns_persisted_state(client):
    session_id = client.get("/api/session").json()["session_id"]
    client.put("/api/session/state", json={"history_open": True}, headers={"X-Session-Id": session_id})

    response = client.get("/api/session", headers={"X-Session-Id": session_id})

    body = response.json()
    assert body["session_id"] == session_id
    assert body["state"]["history_open"] is True


def test_patch_only_updates_the_fields_sent(client):
    session_id = client.get("/api/session").json()["session_id"]
    client.put(
        "/api/session/state",
        json={"averages_range": {"preset": "7"}},
        headers={"X-Session-Id": session_id},
    )

    state = client.get("/api/session", headers={"X-Session-Id": session_id}).json()["state"]

    assert state["averages_range"]["preset"] == "7"
    assert state["history_open"] is False  # untouched by the patch above
    assert state["history_range"]["preset"] == "30"  # untouched by the patch above


def test_different_sessions_have_independent_state(client):
    session_a = client.get("/api/session").json()["session_id"]
    session_b = client.get("/api/session").json()["session_id"]
    assert session_a != session_b

    client.put("/api/session/state", json={"history_open": True}, headers={"X-Session-Id": session_a})

    state_b = client.get("/api/session", headers={"X-Session-Id": session_b}).json()["state"]
    assert state_b["history_open"] is False


def test_put_without_session_header_is_rejected(client):
    response = client.put("/api/session/state", json={"history_open": True})

    assert response.status_code == 400


def test_unknown_or_expired_session_id_falls_back_to_a_fresh_default_session(client):
    response = client.get("/api/session", headers={"X-Session-Id": "does-not-exist"})

    body = response.json()
    assert response.status_code == 200
    assert body["session_id"] != "does-not-exist"
    assert body["state"]["history_open"] is False
