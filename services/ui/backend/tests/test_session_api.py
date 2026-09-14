import asyncio
import json

import httpx

from ui_service.main import SESSION_TTL_SECONDS, app
from ui_service.session_store import RedisSessionStore


class FakeRedis:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}
        self.expirations: dict[str, int] = {}

    async def get(self, key: str) -> str | None:
        return self.values.get(key)

    async def set(self, key: str, value: str, *, ex: int) -> bool:
        self.values[key] = value
        self.expirations[key] = ex
        return True

    async def expire(self, key: str, ttl: int) -> bool:
        if key not in self.values:
            return False
        self.expirations[key] = ttl
        return True

    async def ping(self) -> bool:
        return True

    async def aclose(self) -> None:
        pass


def install_fake_store() -> tuple[RedisSessionStore, FakeRedis]:
    store = RedisSessionStore("redis://localhost:6379/0", SESSION_TTL_SECONDS)
    fake = FakeRedis()
    store.client = fake
    app.state.session_store = store
    return store, fake


def test_session_preferences_round_trip_through_redis() -> None:
    async def exercise_session() -> None:
        store, fake = install_fake_store()
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            initial = await client.get("/api/session/preferences")
            assert initial.status_code == 200
            assert initial.json()["selected"] is None
            session_id = initial.cookies["petroscope_session"]
            key = f"ui:session:{session_id}"
            assert fake.expirations[key] == SESSION_TTL_SECONDS

            payload = {
                **initial.json(),
                "selected": ["WTI_USD_BBL"],
                "range": "7",
                "moving_average": "3",
            }
            updated = await client.put("/api/session/preferences", json=payload)
            assert updated.status_code == 200
            assert json.loads(fake.values[key]) == payload

            fake.expirations[key] = 1
            restored = await client.get("/api/session/preferences")
            assert restored.json() == payload
            assert fake.expirations[key] == SESSION_TTL_SECONDS

            fake.values[key] = "not-json"
            reset = await client.get("/api/session/preferences")
            assert reset.status_code == 200
            assert reset.json()["selected"] is None
            assert fake.expirations[key] == SESSION_TTL_SECONDS

            await store.close()

    asyncio.run(exercise_session())


def test_invalid_session_cookie_is_rotated() -> None:
    async def exercise_invalid_cookie() -> None:
        install_fake_store()
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://test",
            cookies={"petroscope_session": "invalid-cookie"},
        ) as client:
            response = await client.get("/api/session/preferences")
        assert response.status_code == 200
        assert response.cookies["petroscope_session"] != "invalid-cookie"

    asyncio.run(exercise_invalid_cookie())


def test_spa_fallback_serves_vite_entrypoint() -> None:
    async def request_page() -> None:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/analysis/custom-view")
            assert response.status_code == 200
            assert '<div id="root"></div>' in response.text
            assert "/static/assets/" in response.text

    asyncio.run(request_page())
