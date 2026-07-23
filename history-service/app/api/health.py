import logging

from fastapi import APIRouter, Depends, Response
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.database.session import get_db

logger = logging.getLogger(__name__)

router = APIRouter(tags=["health"])


@router.get("/health")
def health(response: Response, db: Session = Depends(get_db)):
    """Service status + database connectivity. Never calls Open-Meteo, never has side effects."""
    try:
        db.execute(text("SELECT 1"))
        database_connected = True
    except Exception:
        logger.exception("health check: database connectivity failed")
        database_connected = False

    response.status_code = 200 if database_connected else 503
    return {
        "status": "ok" if database_connected else "degraded",
        "database": "connected" if database_connected else "unreachable",
    }
