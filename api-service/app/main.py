from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, status

from app.clients.history import HistoryClient
from app.config import Settings, get_settings
from app.routers.air_quality import router as air_quality_router
from app.routers.history import router as history_router


app = FastAPI(
    title="AirAware API Service",
    description=(
        "Retrieves current air-quality information from Open-Meteo, "
        "normalizes it, and coordinates history persistence."
    ),
    version="0.1.0",
)

app.include_router(air_quality_router)
app.include_router(history_router)


def get_history_client(
    settings: Annotated[Settings, Depends(get_settings)],
) -> HistoryClient:
    return HistoryClient(settings)


HistoryDependency = Annotated[
    HistoryClient,
    Depends(get_history_client),
]


@app.get(
    "/health",
    tags=["health"],
)
def health_check() -> dict[str, str]:
    """Check whether the API Service process is running."""

    return {
        "service": "api-service",
        "status": "healthy",
    }


@app.get(
    "/health/ready",
    tags=["health"],
)
async def readiness_check(
    history: HistoryDependency,
) -> dict[str, str]:
    """Check whether the required internal service is available."""

    if not await history.is_ready():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="History Service is unavailable",
        )

    return {
        "service": "api-service",
        "status": "ready",
        "history_service": "connected",
    }