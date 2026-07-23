import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import health, internal_weather, public_weather
from app.config import get_settings
from app.scheduler.weather_scheduler import configure_scheduler, maybe_run_startup_sync, shutdown_scheduler

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI):
    settings = get_settings()
    await maybe_run_startup_sync(settings)
    configure_scheduler(settings)
    yield
    shutdown_scheduler()


# NOTE: /internal/* endpoints are unauthenticated in this assignment (v1). In production
# they must sit behind a private network boundary and/or a shared secret -- see
# docs/architecture.md §11. The UI must never call them; only /api/* is UI-facing.
app = FastAPI(title="SkyIvano Backend Service", lifespan=lifespan)

settings = get_settings()
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(public_weather.router)
app.include_router(internal_weather.router)
