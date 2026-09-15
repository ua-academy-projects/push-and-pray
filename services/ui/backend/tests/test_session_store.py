import pytest

from ui_service.session_store import (
    PostgreSQLSessionStore,
    RedisSessionStore,
    create_session_store,
)


def build(backend: str):
    return create_session_store(
        backend,
        database_url="postgresql://oil_tracker:x@localhost:5432/oil_tracker",
        redis_url="redis://:x@localhost:6379/0",
        ttl_seconds=60,
    )


def test_postgres_backend() -> None:
    store = build("postgres")

    assert isinstance(store, PostgreSQLSessionStore)
    assert store.label == "postgresql"


def test_redis_backend() -> None:
    store = build("redis")

    assert isinstance(store, RedisSessionStore)
    assert store.label == "redis"


def test_unknown_backend_is_rejected() -> None:
    with pytest.raises(ValueError):
        build("memcached")


def test_redis_key_never_holds_the_session_id() -> None:
    session_id = "a" * 43
    key = RedisSessionStore._key(session_id)

    assert session_id not in key
    assert key.startswith("session:")
    assert len(key) == len("session:") + 64
