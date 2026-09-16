import asyncio

from ui_service.session_store import RedisSessionStore
from ui_service.sessions import SessionPreferences


class FakeRedis:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}
        self.expirations: dict[str, int] = {}

    async def ping(self) -> bool:
        return True

    async def get(self, key: str) -> str | None:
        return self.values.get(key)

    async def set(self, key: str, value: str, *, ex: int) -> bool:
        self.values[key] = value
        self.expirations[key] = ex
        return True

    async def expire(self, key: str, ttl: int) -> bool:
        self.expirations[key] = ttl
        return key in self.values

    async def aclose(self) -> None:
        return None


def test_redis_sessions_round_trip_and_refresh_ttl() -> None:
    async def exercise() -> None:
        store = RedisSessionStore("redis://localhost:6379/0", 120)
        fake = FakeRedis()
        store.client = fake
        session_id = "a" * 43

        assert await store.is_ready() is True
        assert (await store.get(session_id)).range == "30"
        await store.update(session_id, SessionPreferences(range="7"))
        assert (await store.get(session_id)).range == "7"
        assert fake.expirations[f"ui:session:{session_id}"] == 120

    asyncio.run(exercise())


def test_invalid_redis_session_is_replaced_with_defaults() -> None:
    async def exercise() -> None:
        store = RedisSessionStore("redis://localhost:6379/0", 120)
        fake = FakeRedis()
        store.client = fake
        key = "ui:session:" + "b" * 43
        fake.values[key] = "not-json"

        assert (await store.get("b" * 43)).range == "30"

    asyncio.run(exercise())
