import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api import health, public_weather, session, sync_trigger
from app.config import get_settings
from app.exceptions import PersistenceError

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# As of the RabbitMQ refactor, this app exposes no /internal/* HTTP endpoints at all -- the
# Fetcher's sync results arrive over RabbitMQ instead, consumed by the separate worker process
# in app/worker.py (app/broker/consumer.py), not by this FastAPI app. The one remaining
# exception to "Backend never calls Fetcher," POST /api/sync/trigger, is itself public
# (UI-facing), not internal. This app's lifespan has no startup/shutdown work of its own.
app = FastAPI(title="SkyIvano Backend Service")

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
