"""FastAPI application for the Aegis UI service."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI
from redis.asyncio import ConnectionPool, Redis

from ui_service.application_client import ApplicationClient
from ui_service.config import Settings, get_settings
from ui_service.routes import (
    request_logging_middleware,
    router,
    unexpected_exception_handler,
)
from ui_service.theme.http import router as theme_router
from ui_service.theme.repository import RedisThemeRepository
from ui_service.theme.service import ThemeService


def create_history_http_client(settings: Settings) -> httpx.AsyncClient:
    """Create the History client owned by the UI application lifespan."""
    return httpx.AsyncClient(
        base_url=str(settings.history_service_url).rstrip("/"),
        timeout=httpx.Timeout(
            connect=settings.history_connect_timeout_seconds,
            read=settings.history_read_timeout_seconds,
            write=settings.history_write_timeout_seconds,
            pool=settings.history_pool_timeout_seconds,
        ),
        follow_redirects=False,
    )


def create_redis_client(settings: Settings) -> Redis:
    """Create a pooled client whose connections open lazily on first command."""
    pool = ConnectionPool(
        host=settings.redis_host,
        port=settings.redis_port,
        db=settings.redis_db,
        username=settings.redis_username,
        password=(
            settings.redis_password.get_secret_value()
            if settings.redis_password is not None
            else None
        ),
        socket_connect_timeout=settings.redis_connection_timeout_seconds,
        socket_timeout=settings.redis_connection_timeout_seconds,
        decode_responses=True,
    )
    return Redis.from_pool(pool)


@asynccontextmanager
async def lifespan(application: FastAPI) -> AsyncIterator[None]:
    """Open and close reusable History and Redis clients."""
    settings = get_settings()
    http_client = create_history_http_client(settings)
    redis_repository = RedisThemeRepository(
        create_redis_client(settings),
        prefix=settings.redis_theme_prefix,
        ttl_seconds=settings.redis_theme_ttl_seconds,
    )
    application.state.application_client = ApplicationClient(
        http_client,
        operation_timeout_seconds=settings.history_operation_timeout_seconds,
    )
    application.state.theme_service = ThemeService(redis_repository)
    try:
        yield
    finally:
        await http_client.aclose()
        await redis_repository.close()


app = FastAPI(title="Aegis UI Service", lifespan=lifespan, debug=False)
app.middleware("http")(request_logging_middleware)
app.add_exception_handler(Exception, unexpected_exception_handler)
app.include_router(router)
app.include_router(theme_router)
