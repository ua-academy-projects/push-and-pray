import asyncio

import httpx
import pytest
from history_service.config import Settings
from history_service.main import (
    app,
    create_app,
    create_provider_http_client,
    lifespan,
)


def settings() -> Settings:
    return Settings(
        mariadb_database="aegis_history",
        mariadb_user="history",
        mariadb_password="secret",
        provider_service_url="http://provider.test",
        provider_connect_timeout_seconds=1,
        provider_read_timeout_seconds=2,
        provider_write_timeout_seconds=3,
        provider_pool_timeout_seconds=4,
    )


def test_provider_http_client_has_fixed_base_url_and_timeout() -> None:
    client = create_provider_http_client(settings())
    try:
        assert client.base_url == httpx.URL("http://provider.test")
        assert client.timeout.connect == 1
        assert client.timeout.read == 2
        assert client.timeout.write == 3
        assert client.timeout.pool == 4
        assert client.follow_redirects is False
    finally:
        client.close()


@pytest.mark.anyio
async def test_lifespan_reuses_and_closes_provider_client(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    http_client = create_provider_http_client(settings())
    monkeypatch.setattr("history_service.main.get_settings", settings)
    monkeypatch.setattr(
        "history_service.main.create_provider_http_client", lambda _: http_client
    )

    async with lifespan(app):
        first = app.state.provider_client
        assert app.state.provider_client is first
        assert first.client is http_client
        assert http_client.is_closed is False

    assert http_client.is_closed is True


@pytest.mark.anyio
async def test_history_lifespan_never_creates_blacklist_scheduler() -> None:
    application = create_app(settings=settings())

    async with application.router.lifespan_context(application):
        assert not hasattr(application.state, "blacklist_scheduler_task")


@pytest.mark.anyio
async def test_history_lifespan_stops_enabled_consumer(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    configured = settings().model_copy(update={"blacklist_consumer_enabled": True})
    started = asyncio.Event()

    class Consumer:
        is_ready = True

        async def run(self, stop_event: asyncio.Event) -> None:
            started.set()
            await stop_event.wait()

    monkeypatch.setattr("history_service.main.create_consumer", lambda _: Consumer())
    application = create_app(settings=configured)

    async with application.router.lifespan_context(application):
        await started.wait()
        assert application.state.blacklist_consumer_task.done() is False

    assert application.state.blacklist_consumer_task.done() is True
