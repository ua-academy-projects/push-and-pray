import asyncio

import httpx
from sqlalchemy.orm import Session

from history_service.main import app


def test_health_reports_database_and_worker_status(client_db_override: Session) -> None:
    async def request_health() -> httpx.Response:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            return await client.get("/health")

    response = asyncio.run(request_health())

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["database"] == "connected"
    assert body["worker"] in {"running", "stopped"}
    assert "rabbitmq" not in body
