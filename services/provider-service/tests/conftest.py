from collections.abc import AsyncIterator, Callable, Iterator
from typing import Any

import pytest
from httpx2 import ASGITransport, AsyncClient
from provider_service.config import get_settings
from provider_service.main import app
from provider_service.provider import FakeReputationProvider, get_reputation_provider


@pytest.fixture(autouse=True)
def isolate_provider_settings(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.setenv("BLACKLIST_POLLING_ENABLED", "false")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    async def reputation_provider_override() -> FakeReputationProvider:
        return FakeReputationProvider()

    app.dependency_overrides[get_reputation_provider] = reputation_provider_override
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture
def override_dependency() -> Iterator[Any]:
    def apply(dependency: Callable[..., Any], replacement: object) -> None:
        async def override() -> object:
            return replacement

        app.dependency_overrides[dependency] = override

    yield apply
    app.dependency_overrides.clear()


@pytest.fixture
def anyio_backend() -> str:
    return "asyncio"
