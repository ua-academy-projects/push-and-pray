import asyncio

import httpx

from ui_service.main import app
from ui_service.sessions import SessionPreferences


class FakeSessionStore:
    def __init__(self) -> None:
        self.values: dict[str, SessionPreferences] = {}

    async def get(self, session_id: str) -> SessionPreferences:
        return self.values.get(session_id, SessionPreferences())

    async def update(
        self,
        session_id: str,
        preferences: SessionPreferences,
    ) -> SessionPreferences:
        self.values[session_id] = preferences
        return preferences


def test_session_preferences_are_stored_by_session_id() -> None:
    async def exercise() -> None:
        app.state.session_store = FakeSessionStore()
        transport = httpx.ASGITransport(app=app)

        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            initial = await client.get("/api/session/preferences")
            assert initial.status_code == 200
            assert initial.json() == SessionPreferences().model_dump(mode="json")
            session_id = initial.cookies["petroscope_session"]

            payload = {**initial.json(), "range": "90", "smooth": False}
            updated = await client.put("/api/session/preferences", json=payload)
            restored = await client.get("/api/session/preferences")

        assert updated.status_code == 200
        assert restored.json() == payload
        assert session_id in app.state.session_store.values

    asyncio.run(exercise())


def test_invalid_session_cookie_is_rotated() -> None:
    async def exercise() -> None:
        app.state.session_store = FakeSessionStore()
        transport = httpx.ASGITransport(app=app)

        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://test",
            cookies={"petroscope_session": "invalid"},
        ) as client:
            response = await client.get("/api/session/preferences")

        assert response.status_code == 200
        assert response.cookies["petroscope_session"] != "invalid"

    asyncio.run(exercise())
