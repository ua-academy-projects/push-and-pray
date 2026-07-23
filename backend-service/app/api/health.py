import logging

from fastapi import APIRouter, Depends, Response
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database.session import get_db

logger = logging.getLogger(__name__)

router = APIRouter(tags=["health"])


@router.get("/api/health")
def health(response: Response, db: Session = Depends(get_db)) -> dict:
    """Service status + direct database connectivity. The Backend has no scheduler of its own
    as of Stage 2 (that moved to the Fetcher Service, which has its own /health) -- never calls
    Open-Meteo, never triggers a synchronization."""
    try:
        db.execute(text("SELECT 1"))
        database_connected = True
    except Exception:
        logger.exception("health check: database connectivity failed")
        database_connected = False

    response.status_code = 200 if database_connected else 503
    return {
        "status": "ok" if database_connected else "degraded",
        "database_connected": database_connected,
    }
