import asyncio

from ui_service.redis_session_store import RedisSessionStore
from ui_service.sessions import SessionPreferences


class FakeRedis:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}
        self.ttls: dict[str, int] = {}

    async def ping(self) -> bool:
        return True

    async def get(self, key: str) -> str | None:
        return self.values.get(key)

    async def setex(self, key: str, ttl: int, value: str) -> None:
        self.values[key] = value
        self.ttls[key] = ttl


def test_redis_session_store_uses_hashed_keys_and_ttl() -> None:
    async def exercise() -> None:
        store = RedisSessionStore("redis://localhost", ttl_seconds=300)
        fake = FakeRedis()
        store.redis = fake  # type: ignore[assignment]

        defaults = await store.get("session-id-that-must-not-appear-in-redis")
        assert defaults == SessionPreferences()

        key = next(iter(fake.values))
        assert "session-id" not in key
        assert fake.ttls[key] == 300

        updated = SessionPreferences(range="90", smooth=False)
        await store.update("session-id-that-must-not-appear-in-redis", updated)
        assert await store.get("session-id-that-must-not-appear-in-redis") == updated

    asyncio.run(exercise())
