import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api import health, internal_weather, public_weather, sync_trigger
from app.config import get_settings
from app.exceptions import PersistenceError

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# NOTE: /internal/* endpoints are unauthenticated in this assignment (v1). In production
# they must sit behind a private network boundary and/or a shared secret -- see
# docs/architecture.md §11. The UI must never call them; only /api/* is UI-facing.
# As of Stage 2, this service no longer runs a scheduler or calls Open-Meteo -- that moved to
# the Weather Fetcher Service. This app's lifespan has no startup/shutdown work of its own.
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
app.include_router(sync_trigger.router)
app.include_router(internal_weather.router)


@app.exception_handler(PersistenceError)
async def persistence_error_handler(request: Request, exc: PersistenceError) -> JSONResponse:
    """A rolled-back persistence failure (e.g. a malformed Fetcher payload) is a Fetcher-side
    problem, not a crash -- respond with a clean 500 and no leaked internals (no raw exception
    text, no partial data), rather than letting the traceback propagate."""
    logger.error("persistence error: %s", exc)
    return JSONResponse(status_code=500, content={"detail": "Failed to persist weather data"})
