import asyncio
import os

import httpx
import pytest
from redis.asyncio import Redis

from ui_service.main import SESSION_TTL_SECONDS, app
from ui_service.session_store import RedisSessionStore
from ui_service.sessions import SessionPreferences

TEST_REDIS_URL = os.getenv("TEST_REDIS_URL")

pytestmark = pytest.mark.skipif(
    not TEST_REDIS_URL,
    reason="TEST_REDIS_URL must point to a Redis server",
)


def redis_url() -> str:
    assert TEST_REDIS_URL
    return TEST_REDIS_URL


async def reset_sessions() -> None:
    client = Redis.from_url(redis_url())
    try:
        await client.flushdb()
    finally:
        await client.aclose()


def test_session_persistence_and_sliding_expiration() -> None:
    async def exercise_session() -> None:
        await reset_sessions()
        app.state.session_store = RedisSessionStore(redis_url(), SESSION_TTL_SECONDS)
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            initial = await client.get("/api/session/preferences")
            assert initial.status_code == 200
            assert initial.json()["selected"] is None
            session_id = initial.cookies["petroscope_session"]

            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
                cookies={"petroscope_session": "invalid-cookie"},
            ) as invalid_cookie_client:
                invalid_cookie_response = await invalid_cookie_client.get(
                    "/api/session/preferences"
                )
            assert invalid_cookie_response.status_code == 200
            assert invalid_cookie_response.json() == initial.json()
            assert invalid_cookie_response.cookies["petroscope_session"] != "invalid-cookie"

            payloads = [
                {**initial.json(), "selected": ["WTI_USD_BBL"], "range": "7"},
                {**initial.json(), "selected": ["BRENT_USD_BBL"], "range": "90"},
            ]
            responses = await asyncio.gather(
                *(client.put("/api/session/preferences", json=payload) for payload in payloads)
            )
            assert all(response.status_code == 200 for response in responses)

            redis = Redis.from_url(redis_url(), decode_responses=True)
            try:
                key = RedisSessionStore._key(session_id)
                await redis.expire(key, 3600)
                assert await redis.ttl(key) <= 3600

                restored = await client.get("/api/session/preferences")
                assert restored.json() in payloads

                # Reading slid the expiry back out to the full TTL.
                assert await redis.ttl(key) > SESSION_TTL_SECONDS - 5
                assert len(await redis.keys("session:*")) == 2
            finally:
                await redis.aclose()

    asyncio.run(exercise_session())


def test_expired_and_corrupt_sessions_fall_back_to_defaults() -> None:
    async def exercise_expiration() -> None:
        await reset_sessions()
        store = RedisSessionStore(redis_url(), SESSION_TTL_SECONDS)
        app.state.session_store = store
        expired_session_id = "e" * 43
        corrupt_session_id = "c" * 43

        await store.update(expired_session_id, SessionPreferences(range="365"))

        redis = Redis.from_url(redis_url(), decode_responses=True)
        try:
            # Redis drops the key itself once the TTL runs out.
            await redis.pexpire(RedisSessionStore._key(expired_session_id), 50)
            await redis.set(RedisSessionStore._key(corrupt_session_id), "{not json")
        finally:
            await redis.aclose()

        await asyncio.sleep(0.2)

        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            client.cookies.set("petroscope_session", expired_session_id)
            expired = await client.get("/api/session/preferences")
            assert expired.status_code == 200
            assert expired.json()["range"] == "30"

            client.cookies.set("petroscope_session", corrupt_session_id)
            corrupt = await client.get("/api/session/preferences")
            assert corrupt.status_code == 200
            assert corrupt.json() == SessionPreferences().model_dump(mode="json")

        assert await store.is_ready() is True

    asyncio.run(exercise_expiration())


def test_health_reports_redis_sessions() -> None:
    async def exercise_health() -> None:
        await reset_sessions()
        app.state.session_store = RedisSessionStore(redis_url(), SESSION_TTL_SECONDS)

        class HistoryStub:
            async def get(self, path):
                request = httpx.Request("GET", f"http://history{path}")
                return httpx.Response(200, json={"status": "ok"}, request=request)

        app.state.client = HistoryStub()

        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/health")

        assert response.status_code == 200
        assert response.json()["sessions"] == "redis"

    asyncio.run(exercise_health())
