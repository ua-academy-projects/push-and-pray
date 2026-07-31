import asyncio

import httpx
import pytest
from provider_service.config import Settings
from provider_service.main import app, create_abuseipdb_http_client, lifespan
from provider_service.provider import AbuseIPDBProvider


def settings() -> Settings:
    return Settings(
        abuseipdb_api_key="test-key",
        abuseipdb_connect_timeout_seconds=1,
        abuseipdb_read_timeout_seconds=2,
        abuseipdb_write_timeout_seconds=3,
        abuseipdb_pool_timeout_seconds=4,
    )


@pytest.mark.anyio
async def test_http_client_has_fixed_security_and_timeout_configuration() -> None:
    client = create_abuseipdb_http_client(settings())
    try:
        assert client.base_url == httpx.URL("https://api.abuseipdb.com")
        assert client.headers["Accept"] == "application/json"
        assert client.headers["Key"] == "test-key"
        assert client.timeout.connect == 1
        assert client.timeout.read == 2
        assert client.timeout.write == 3
        assert client.timeout.pool == 4
        assert client.follow_redirects is False
    finally:
        await client.aclose()


@pytest.mark.anyio
async def test_lifespan_reuses_one_client_and_closes_it(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    abuseipdb_client = create_abuseipdb_http_client(settings())
    monkeypatch.setattr("provider_service.main.get_settings", settings)
    monkeypatch.setattr(
        "provider_service.main.create_abuseipdb_http_client", lambda _: abuseipdb_client
    )

    async with lifespan(app):
        provider = app.state.reputation_provider
        assert isinstance(provider, AbuseIPDBProvider)
        assert app.state.reputation_provider is provider
        assert provider.client is abuseipdb_client
        assert abuseipdb_client.is_closed is False

    assert abuseipdb_client.is_closed is True


@pytest.mark.anyio
async def test_lifespan_stops_enabled_scheduler_and_closes_publisher(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    configured = settings().model_copy(update={"blacklist_polling_enabled": True})
    started = asyncio.Event()
    stopped = asyncio.Event()

    class Publisher:
        is_connected = True

        async def close(self) -> None:
            stopped.set()

    async def run_worker(_: Settings, stop_event: asyncio.Event, **__: object) -> None:
        started.set()
        await stop_event.wait()

    monkeypatch.setattr("provider_service.main.get_settings", lambda: configured)
    monkeypatch.setattr(
        "provider_service.main.AioPikaBlacklistPublisher", lambda _: Publisher()
    )
    monkeypatch.setattr("provider_service.main.run_worker", run_worker)

    async with lifespan(app):
        await started.wait()
        assert app.state.blacklist_scheduler_task.done() is False

    assert stopped.is_set()
    assert app.state.blacklist_scheduler_task.done() is True
