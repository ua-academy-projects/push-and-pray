import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI, HTTPException, Request, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from app.config import get_settings
from app.consumer import RabbitMQConsumer
from app.database import SessionLocal
from app.routers.cities import router as cities_router
from app.routers.measurements import router as measurements_router


logger = logging.getLogger(__name__)
settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    consumer = RabbitMQConsumer(settings)
    app.state.rabbitmq_consumer = consumer
    await consumer.start()

    try:
        yield
    finally:
        await consumer.stop()


app = FastAPI(
    title="AirAware Backend Service",
    description=(
        "Stores air-quality measurements and provides "
        "dashboard data to the Frontend Service."
    ),
    version="0.3.0",
    lifespan=lifespan,
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
def readiness_check(request: Request) -> dict[str, str]:
    try:
        with SessionLocal() as db:
            db.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        logger.exception("Database readiness check failed")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database is unavailable",
        ) from exc

    consumer: RabbitMQConsumer = request.app.state.rabbitmq_consumer

    if consumer.enabled and not consumer.is_connected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="RabbitMQ consumer is unavailable",
        )

    return {
        "service": "backend-service",
        "status": "ready",
        "database": "connected",
        "rabbitmq_consumer": (
            "connected" if consumer.enabled else "disabled"
        ),
    }
