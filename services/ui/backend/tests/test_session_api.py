import asyncio

import httpx

from ui_service.main import app


class FakeRedis:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}

    async def get(self, key: str) -> str | None:
        return self.values.get(key)

    async def set(self, key: str, value: str, *, ex: int) -> bool:
        self.values[key] = value
        return True

    async def expire(self, key: str, ttl: int) -> bool:
        return key in self.values and ttl > 0

    async def aclose(self) -> None:
        pass


async def session_round_trip() -> None:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        fake_redis = FakeRedis()
        app.state.redis = fake_redis

        initial = await client.get("/api/session/preferences")
        assert initial.status_code == 200
        assert initial.json()["selected"] is None
        assert initial.cookies.get("petroscope_session")

        updated = await client.put(
            "/api/session/preferences",
            json={
                "selected": ["WTI_USD_BBL"],
                "range": "7",
                "metric": "change",
                "layout": "compare",
                "style": "line",
                "table_order": "asc",
                "table_limit": 100,
                "scale": "linear",
                "moving_average": "3",
                "smooth": False,
            },
        )
        assert updated.status_code == 200

        restored = await client.get("/api/session/preferences")
        assert restored.json()["selected"] == ["WTI_USD_BBL"]
        assert restored.json()["range"] == "7"
        assert restored.json()["table_limit"] == 100
        assert restored.json()["moving_average"] == "3"
        assert restored.json()["smooth"] is False


def test_session_preferences_round_trip_through_redis() -> None:
    asyncio.run(session_round_trip())


def test_spa_fallback_serves_vite_entrypoint() -> None:
    async def request_page() -> None:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/analysis/custom-view")
            assert response.status_code == 200
            assert '<div id="root"></div>' in response.text
            assert "/static/assets/" in response.text

    asyncio.run(request_page())
