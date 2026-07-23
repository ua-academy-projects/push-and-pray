import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api import health, internal_fetch
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
# docs/architecture.md §11. The UI must never call this service at all, directly or
# indirectly -- a manual refresh always goes UI -> Backend -> here.
app = FastAPI(title="SkyIvano Weather Fetcher Service", lifespan=lifespan)

app.include_router(health.router)
app.include_router(internal_fetch.router)
