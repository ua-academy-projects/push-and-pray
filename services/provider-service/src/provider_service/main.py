"""FastAPI application for the Aegis provider service."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import cast

import httpx
from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from starlette.types import ExceptionHandler

from provider_service.config import Settings, get_settings
from provider_service.exceptions import ApplicationError
from provider_service.provider import AbuseIPDBProvider
from provider_service.routes import (
    application_exception_handler,
    request_id_middleware,
    router,
    unexpected_exception_handler,
    validation_exception_handler,
)


def create_abuseipdb_http_client(settings: Settings) -> httpx.AsyncClient:
    """Create the one AbuseIPDB client owned by the application lifespan."""
    return httpx.AsyncClient(
        base_url=str(settings.abuseipdb_base_url).rstrip("/"),
        headers={
            "Accept": "application/json",
            "Key": settings.abuseipdb_api_key.get_secret_value(),
        },
        timeout=httpx.Timeout(
            connect=settings.abuseipdb_connect_timeout_seconds,
            read=settings.abuseipdb_read_timeout_seconds,
            write=settings.abuseipdb_write_timeout_seconds,
            pool=settings.abuseipdb_pool_timeout_seconds,
        ),
        follow_redirects=False,
        # transport=httpx.AsyncHTTPTransport(local_address="0.0.0.0"),
    )


@asynccontextmanager
async def lifespan(application: FastAPI) -> AsyncIterator[None]:
    """Open and close the reusable AbuseIPDB client exactly once."""
    settings = get_settings()
    abuseipdb_client = create_abuseipdb_http_client(settings)
    application.state.reputation_provider = AbuseIPDBProvider(
        abuseipdb_client,
        operation_timeout_seconds=settings.abuseipdb_operation_timeout_seconds,
    )
    try:
        yield
    finally:
        await abuseipdb_client.aclose()


app = FastAPI(title="Aegis Provider Service", lifespan=lifespan, debug=False)
app.middleware("http")(request_id_middleware)
app.add_exception_handler(
    ApplicationError, cast(ExceptionHandler, application_exception_handler)
)
app.add_exception_handler(
    RequestValidationError, cast(ExceptionHandler, validation_exception_handler)
)
app.add_exception_handler(Exception, unexpected_exception_handler)
app.include_router(router)
