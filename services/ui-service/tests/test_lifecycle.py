import httpx
import pytest
from redis.asyncio import ConnectionPool
from ui_service.application_client import ApplicationClient
from ui_service.config import Settings
from ui_service.main import (
    app,
    create_history_http_client,
    create_redis_client,
    lifespan,
)


def settings() -> Settings:
    return Settings(
        history_service_url="http://history.test",
        history_connect_timeout_seconds=1,
        history_read_timeout_seconds=2,
        history_write_timeout_seconds=3,
        history_pool_timeout_seconds=4,
    )


@pytest.mark.anyio
async def test_history_http_client_configuration() -> None:
    client = create_history_http_client(settings())
    try:
        assert client.base_url == httpx.URL("http://history.test")
        assert client.timeout.connect == 1
        assert client.timeout.read == 2
        assert client.timeout.write == 3
        assert client.timeout.pool == 4
        assert client.follow_redirects is False
    finally:
        await client.aclose()


@pytest.mark.anyio
async def test_redis_client_uses_lazy_connection_pool() -> None:
    client = create_redis_client(settings())
    try:
        pool = client.connection_pool
        assert isinstance(pool, ConnectionPool)
        assert pool.connection_kwargs["host"] == "127.0.0.1"
        assert pool.connection_kwargs["port"] == 6379
        assert pool.connection_kwargs["db"] == 0
        assert pool._available_connections == []
        assert pool._in_use_connections == set()
    finally:
        await client.aclose()


@pytest.mark.anyio
async def test_lifespan_reuses_one_application_client_and_closes_it(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    class FakeRedis:
        def __init__(self) -> None:
            self.closed = False

        async def aclose(self) -> None:
            self.closed = True

    http_client = create_history_http_client(settings())
    redis_client = FakeRedis()
    monkeypatch.setattr("ui_service.main.get_settings", settings)
    monkeypatch.setattr(
        "ui_service.main.create_history_http_client", lambda _: http_client
    )
    monkeypatch.setattr("ui_service.main.create_redis_client", lambda _: redis_client)

    async with lifespan(app):
        first = app.state.application_client
        second = app.state.application_client
        assert isinstance(first, ApplicationClient)
        assert first is second
        assert first.client is http_client
        assert http_client.is_closed is False

    assert http_client.is_closed is True
    assert redis_client.closed is True
