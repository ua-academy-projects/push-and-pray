import logging

from fastapi import FastAPI, HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.database import SessionLocal
from app.routers.cities import router as cities_router
from app.routers.measurements import router as measurements_router


logger = logging.getLogger(__name__)


app = FastAPI(
    title="AirAware Backend Service",
    description=(
        "Stores air-quality measurements and provides "
        "dashboard data to the Frontend Service."
    ),
    version="0.2.0",
)

app.include_router(cities_router)
app.include_router(measurements_router)


@app.get(
    "/health",
    tags=["health"],
)
def health_check() -> dict[str, str]:
    return {
        "service": "backend-service",
        "status": "healthy",
    }


@app.get(
    "/health/ready",
    tags=["health"],
)
def readiness_check() -> dict[str, str]:
    try:
        with SessionLocal() as db:
            db.execute(text("SELECT 1"))

    except SQLAlchemyError as exc:
        logger.exception(
            "Database readiness check failed"
        )

        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database is unavailable",
        ) from exc

    return {
        "service": "backend-service",
        "status": "ready",
        "database": "connected",
    }