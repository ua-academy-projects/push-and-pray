import asyncio
import contextlib
import logging
import os
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api import health, public_weather, session, sync_trigger
from app.broker.consumer import consume_forever
from app.config import get_settings
from app.database.session import init_db
from app.exceptions import PersistenceError

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

init_db()


def _on_consumer_done(task: asyncio.Task) -> None:
    """The RabbitMQ consumer runs alongside the API in this same process (see lifespan below).
    If it dies (lost connection, unhandled error), the API half would otherwise keep serving
    HTTP traffic looking healthy while sync data silently stops flowing -- exit the process
    instead so gunicorn respawns this worker, the same fail-fast behavior a separate
    `restart: unless-stopped` worker container used to give us."""
    if task.cancelled():
        return
    exc = task.exception()
    if exc is not None:
        logger.critical("RabbitMQ consumer crashed -- exiting process to be restarted", exc_info=exc)
        os._exit(1)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    consumer_task = asyncio.create_task(consume_forever())
    consumer_task.add_done_callback(_on_consumer_done)
    try:
        yield
    finally:
        consumer_task.remove_done_callback(_on_consumer_done)
        consumer_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await consumer_task


# The RabbitMQ consumer (app/broker/consumer.py) runs as a background task in this same
# process via the lifespan above, rather than as a separate worker process/container -- one
# process, one event loop, handling both the public HTTP API and the Fetcher's async sync
# results. This app exposes no /internal/* HTTP endpoints -- sync results only ever arrive
# over RabbitMQ. The one exception to "Backend never calls Fetcher," POST /api/sync/trigger,
# is itself public (UI-facing), not internal.
app = FastAPI(title="SkyIvano Backend Service", lifespan=lifespan)

settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_methods=["GET", "POST", "PUT"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(public_weather.router)
app.include_router(session.router)
app.include_router(sync_trigger.router)


@app.exception_handler(PersistenceError)
async def persistence_error_handler(request: Request, exc: PersistenceError) -> JSONResponse:
    """A rolled-back persistence failure (e.g. a malformed Fetcher payload) is a Fetcher-side
    problem, not a crash -- respond with a clean 500 and no leaked internals (no raw exception
    text, no partial data), rather than letting the traceback propagate."""
    logger.error("persistence error: %s", exc)
    return JSONResponse(status_code=500, content={"detail": "Failed to persist weather data"})
