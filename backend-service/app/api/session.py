from fastapi import APIRouter, Depends, Header, HTTPException
from redis import Redis

from app.cache.redis_client import get_redis
from app.config import Settings, get_settings
from app.schemas.session import SessionResponse, UIStatePatch
from app.services import session_service

router = APIRouter(tags=["session"])


@router.get("/api/session", response_model=SessionResponse)
def get_session(
    x_session_id: str | None = Header(default=None),
    redis: Redis = Depends(get_redis),
    settings: Settings = Depends(get_settings),
) -> SessionResponse:
    """Ensures a session exists for this browser and returns its stored UI preferences.
    Called with no header on the very first visit -- the Backend mints a new id and returns it
    in the body (never a Set-Cookie; see docs/architecture.md for why). Redis here holds only
    UI state (selected period, filters, toggles) -- never weather/business data."""
    session_id, state = session_service.load_or_create(redis, x_session_id, settings.redis_session_ttl_seconds)
    return SessionResponse(session_id=session_id, state=state)


@router.put("/api/session/state", response_model=SessionResponse)
def patch_session_state(
    patch: UIStatePatch,
    x_session_id: str | None = Header(default=None),
    redis: Redis = Depends(get_redis),
    settings: Settings = Depends(get_settings),
) -> SessionResponse:
    """Merges a partial UI-state change into this session and refreshes its TTL. Requires a
    session id already minted by GET /api/session -- the UI always calls that first."""
    if not x_session_id:
        raise HTTPException(status_code=400, detail="Missing X-Session-Id header; call GET /api/session first")
    state = session_service.patch_state(redis, x_session_id, patch, settings.redis_session_ttl_seconds)
    return SessionResponse(session_id=x_session_id, state=state)
