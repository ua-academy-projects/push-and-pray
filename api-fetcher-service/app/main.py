import asyncio
import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from fastapi import FastAPI, HTTPException, Request, status

from app.clients.backend import BackendClient
from app.clients.open_meteo import OpenMeteoClient
from app.config import get_settings
from app.schemas import FetchRunResult, FetchStatus
from app.service import FetchService


logging.basicConfig(
    level=logging.INFO,
    format=(
        "%(asctime)s | %(levelname)s | "
        "%(name)s | %(message)s"
    ),
)

logger = logging.getLogger(__name__)


async def execute_scheduled_fetch(
    fetch_service: FetchService,
) -> None:
    try:
        await fetch_service.run_fetch()
    except RuntimeError:
        logger.warning(
            "Scheduled fetch skipped because another "
            "fetch is already running"
        )
    except Exception:
        logger.exception(
            "Unexpected scheduled fetch failure"
        )


@asynccontextmanager
async def lifespan(
    app: FastAPI,
) -> AsyncIterator[None]:
    settings = get_settings()

    backend_client = BackendClient(settings)
    open_meteo_client = OpenMeteoClient(settings)

    fetch_service = FetchService(
        backend_client=backend_client,
        open_meteo_client=open_meteo_client,
    )

    scheduler = AsyncIOScheduler(
        timezone="UTC",
    )

    app.state.fetch_service = fetch_service
    app.state.backend_client = backend_client
    app.state.scheduler = scheduler

    if settings.scheduler_enabled:
        scheduler.add_job(
            execute_scheduled_fetch,
            trigger="cron",
            minute=settings.fetch_minute_of_hour,
            second=0,
            args=[fetch_service],
            id="hourly-air-quality-fetch",
            replace_existing=True,
            max_instances=1,
            coalesce=True,
        )

        scheduler.start()

        logger.info(
            "Scheduler started; fetch runs hourly at minute %s",
            settings.fetch_minute_of_hour,
        )

    if settings.fetch_on_startup:
        asyncio.create_task(
            execute_scheduled_fetch(fetch_service)
        )

    yield

    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("Scheduler stopped")


app = FastAPI(
    title="AirAware API Fetcher Service",
    description=(
        "Collects air-quality data from Open-Meteo "
        "and submits it to the Backend Service."
    ),
    version="0.2.0",
    lifespan=lifespan,
)


def get_fetch_service(
    request: Request,
) -> FetchService:
    return request.app.state.fetch_service


def get_backend_client(
    request: Request,
) -> BackendClient:
    return request.app.state.backend_client


@app.get(
    "/health",
    tags=["health"],
)
def health_check() -> dict[str, str]:
    return {
        "service": "api-fetcher-service",
        "status": "healthy",
    }


@app.get(
    "/health/ready",
    tags=["health"],
)
async def readiness_check(
    request: Request,
) -> dict[str, str]:
    backend_client = get_backend_client(request)

    if not await backend_client.is_ready():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Backend Service is unavailable",
        )

    return {
        "service": "api-fetcher-service",
        "status": "ready",
        "backend_service": "connected",
    }


@app.get(
    "/fetch/status",
    response_model=FetchStatus,
    tags=["fetching"],
)
def fetch_status(
    request: Request,
) -> FetchStatus:
    fetch_service = get_fetch_service(request)

    return fetch_service.status


@app.post(
    "/fetch",
    response_model=FetchRunResult,
    tags=["fetching"],
)
async def trigger_fetch(
    request: Request,
) -> FetchRunResult:
    fetch_service = get_fetch_service(request)

    try:
        return await fetch_service.run_fetch()

    except RuntimeError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc