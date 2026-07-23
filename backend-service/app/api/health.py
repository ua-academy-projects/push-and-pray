import logging

from fastapi import APIRouter

from app.clients.history_service_client import HistoryServiceClient
from app.config import get_settings

logger = logging.getLogger(__name__)

router = APIRouter(tags=["health"])


@router.get("/api/health")
async def health() -> dict:
    """Service status + scheduler flag + optional History Service reachability.
    Never calls Open-Meteo, never triggers a synchronization."""
    settings = get_settings()

    history_reachable: bool | None
    try:
        await HistoryServiceClient(settings).health()
        history_reachable = True
    except Exception:
        logger.warning("health check: history service unreachable")
        history_reachable = False

    return {
        "status": "ok",
        "scheduler_enabled": settings.weather_sync_enabled,
        "history_service_reachable": history_reachable,
    }
