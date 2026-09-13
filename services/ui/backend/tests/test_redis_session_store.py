import asyncio

from ui_service.session_store import RedisSessionStore
from ui_service.sessions import SessionPreferences


class FakeRedis:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}

    async def get(self, key: str) -> str | None:
        return self.values.get(key)

    async def set(self, key: str, value: str, *, ex: int) -> bool:
        assert ex > 0
        self.values[key] = value
        return True

    async def expire(self, key: str, ttl: int) -> bool:
        return key in self.values and ttl > 0

    async def ping(self) -> bool:
        return True

    async def aclose(self) -> None:
        return None


def test_redis_session_round_trip(monkeypatch) -> None:
    fake = FakeRedis()
    monkeypatch.setattr(
        "ui_service.session_store.redis.Redis.from_url",
        lambda *args, **kwargs: fake,
    )
    store = RedisSessionStore("redis://example", 60)

    async def exercise() -> None:
        assert await store.get("session") == SessionPreferences()
        updated = SessionPreferences(range="7", selected=["WTI_USD_BBL"])
        await store.update("session", updated)
        assert await store.get("session") == updated
        assert await store.is_ready() is True

    asyncio.run(exercise())
