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

    async def set(self, key: str, value: str, ex: int) -> None:
        self.values[key] = value
        self.expirations[key] = ex

    async def expire(self, key: str, ttl: int) -> None:
        self.expirations[key] = ttl


def test_redis_sessions_are_hashed_and_refresh_ttl() -> None:
    async def exercise() -> None:
        store = RedisSessionStore("redis://localhost:6379/0", 300)
        fake = FakeRedis()
        store.client = fake

        session_id = "a" * 43
        initial = await store.get(session_id)
        assert initial == SessionPreferences()

        key = store._key(session_id)
        assert session_id not in key
        assert fake.expirations[key] == 300

        updated = SessionPreferences(range="90")
        await store.update(session_id, updated)
        assert await store.get(session_id) == updated
        assert fake.expirations[key] == 300

    asyncio.run(exercise())
