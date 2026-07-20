from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.database import get_db_session
from app.routers.history import router as history_router


app = FastAPI(
    title="Air Quality History Service",
    description=(
        "Stores and returns successful air-quality request history."
    ),
    version="0.1.0",
)

app.include_router(history_router)

DatabaseSession = Annotated[Session, Depends(get_db_session)]


@app.get(
    "/health",
    tags=["health"],
)
def health_check() -> dict[str, str]:
    """Check whether the application process is running."""

    return {
        "service": "history-service",
        "status": "healthy",
    }


@app.get(
    "/health/ready",
    tags=["health"],
)
def readiness_check(
    session: DatabaseSession,
) -> dict[str, str]:
    """Check whether the application can connect to PostgreSQL."""

    try:
        session.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Database is unavailable",
        ) from exc

    return {
        "service": "history-service",
        "status": "ready",
        "database": "connected",
    }