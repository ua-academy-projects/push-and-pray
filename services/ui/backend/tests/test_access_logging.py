from __future__ import annotations

import io
import json
import logging

from fastapi import FastAPI, Response
from fastapi.testclient import TestClient

from ui_service.access_logging import JsonFormatter, install_access_logging


def test_access_log_is_structured_and_excludes_request_secrets() -> None:
    app = FastAPI()
    install_access_logging(app, "ui")

    @app.get("/items/{item_id}")
    def item(item_id: str, response: Response) -> dict[str, str]:
        response.status_code = 503
        return {"item_id": item_id}

    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(JsonFormatter("ui"))
    logger = logging.getLogger("ui.access")
    previous_handlers = logger.handlers
    previous_propagate = logger.propagate
    logger.handlers = [handler]
    logger.propagate = False
    try:
        response = TestClient(app).get(
            "/items/private-value?token=secret",
            headers={"Authorization": "Bearer secret", "X-Request-ID": "invalid id"},
        )
    finally:
        logger.handlers = previous_handlers
        logger.propagate = previous_propagate

    entry = json.loads(stream.getvalue())
    assert response.status_code == 503
    assert response.headers["X-Request-ID"] == entry["request_id"]
    assert entry["service"] == "ui"
    assert entry["event"] == "http_access"
    assert entry["method"] == "GET"
    assert entry["route"] == "/items/{item_id}"
    assert entry["status"] == 503
    assert entry["duration_ms"] >= 0
    assert "secret" not in stream.getvalue()
    assert "private-value" not in stream.getvalue()
