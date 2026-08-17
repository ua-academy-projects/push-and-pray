import asyncio

import httpx
from sqlalchemy.orm import Session

from ui_service.main import app


async def session_round_trip(db_session: Session) -> None:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
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


def test_session_preferences_round_trip_through_postgres(client_db_override: Session) -> None:
    asyncio.run(session_round_trip(client_db_override))


def test_spa_fallback_serves_vite_entrypoint() -> None:
    async def request_page() -> None:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/analysis/custom-view")
            assert response.status_code == 200
            assert '<div id="root"></div>' in response.text
            assert "/static/assets/" in response.text

    asyncio.run(request_page())
