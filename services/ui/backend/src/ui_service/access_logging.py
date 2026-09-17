from __future__ import annotations

import json
import logging
import os
import re
import sys
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from uuid import uuid4

from fastapi import FastAPI, Request, Response

_REQUEST_ID = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")


class JsonFormatter(logging.Formatter):
    def __init__(self, service: str) -> None:
        super().__init__()
        self.service = service

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.now(UTC).isoformat(),
            "service": self.service,
            "level": record.levelname.lower(),
            "event": "application_log",
            "message": record.getMessage(),
        }
        access_fields = getattr(record, "access_fields", None)
        if isinstance(access_fields, dict):
            payload.update(access_fields)
        if record.exc_info:
            payload["exception_type"] = record.exc_info[0].__name__
        return json.dumps(payload, separators=(",", ":"), ensure_ascii=True)


def configure_structured_logging(service: str, level: str) -> None:
    formatter = JsonFormatter(service)
    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stdout)]
    log_file = os.getenv("OILSCOPE_LOG_FILE", "")
    if log_file:
        path = Path(log_file)
        path.parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(path, encoding="utf-8"))
    for handler in handlers:
        handler.setFormatter(formatter)
    logging.basicConfig(level=level, handlers=handlers, force=True)


def install_access_logging(app: FastAPI, service: str) -> None:
    access_logger = logging.getLogger(f"{service}.access")

    @app.middleware("http")
    async def log_request(request: Request, call_next: Any) -> Response:
        supplied_id = request.headers.get("x-request-id", "")
        request_id = supplied_id if _REQUEST_ID.fullmatch(supplied_id) else uuid4().hex
        started = time.perf_counter()
        status = 500
        try:
            response = await call_next(request)
            status = response.status_code
            response.headers["X-Request-ID"] = request_id
            return response
        finally:
            route = getattr(request.scope.get("route"), "path", "<unmatched>")
            access_logger.info(
                "HTTP request completed",
                extra={
                    "access_fields": {
                        "event": "http_access",
                        "method": request.method,
                        "route": route,
                        "status": status,
                        "duration_ms": round((time.perf_counter() - started) * 1000, 3),
                        "request_id": request_id,
                    }
                },
            )
