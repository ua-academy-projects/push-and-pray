from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import ValidationError

from .sessions import SessionPreferences, resolve_session_id

from datetime import datetime, timedelta, timezone
from sqlalchemy.orm import Session
from fastapi import Depends
from sqlalchemy import text

from .database import get_db
from .repository import get_session, create_session, refresh_session
logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

STATIC_DIR = Path(__file__).parent / "static"
HISTORY_SERVICE_URL = os.getenv("HISTORY_SERVICE_URL", "http://localhost:8001").rstrip("/")
SESSION_COOKIE_NAME = os.getenv("SESSION_COOKIE_NAME", "petroscope_session")
SESSION_TTL_SECONDS = int(os.getenv("SESSION_TTL_SECONDS", "2592000"))
SESSION_COOKIE_SECURE = os.getenv("SESSION_COOKIE_SECURE", "false").lower() == "true"


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.client = httpx.AsyncClient(base_url=HISTORY_SERVICE_URL, timeout=10.0)
    try:
        yield
    finally:
        await app.state.client.aclose()


app = FastAPI(
    title="Oil Price Tracker — UI Service",
    version="3.0.0",
    lifespan=lifespan,
)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


@app.get("/", include_in_schema=False)
def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


async def proxy_get(request: Request, path: str, params: dict | None = None) -> Response:
    try:
        upstream = await request.app.state.client.get(path, params=params)
        upstream.raise_for_status()
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail="History Service is unavailable") from exc
    return Response(
        content=upstream.content,
        status_code=upstream.status_code,
        media_type="application/json",
    )


@app.get("/health", tags=["operations"])
async def health(request: Request, db: Session = Depends(get_db)) -> dict[str, str]:
    try:
        upstream = await request.app.state.client.get("/health")
        upstream.raise_for_status()
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=503, detail="History Service is unavailable") from exc
    try:
        db.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Database is unavailable") from exc
    return {"status": "ok", "history": "connected", "database": "connected"}


def _set_session_cookie(response: Response, session_id: str) -> None:
    response.set_cookie(
        SESSION_COOKIE_NAME,
        session_id,
        max_age=SESSION_TTL_SECONDS,
        httponly=True,
        secure=SESSION_COOKIE_SECURE,
        samesite="lax",
        path="/",
    )

@app.get(
    "/api/session/preferences",
    response_model=SessionPreferences,
    tags=["session"],
)
async def get_session_preferences(
    request: Request,
    response: Response,
    db: Annotated[Session, Depends(get_db)],
) -> SessionPreferences:
    session_id, _ = resolve_session_id(request.cookies.get(SESSION_COOKIE_NAME))
    record = get_session(db, session_id)
    if record is None:
        preferences = SessionPreferences()
        create_session(db, session_id, preferences.model_dump(), _new_expiry())
    else:
        try:
            preferences = SessionPreferences.model_validate(record.preferences)
        except ValidationError:
            preferences = SessionPreferences()
            record.preferences = preferences.model_dump()
            record.expires_at = _new_expiry()
            db.commit()
        else:
            refresh_session(db, session_id, _new_expiry())
    _set_session_cookie(response, session_id)
    return preferences

@app.put(
    "/api/session/preferences",
    response_model=SessionPreferences,
    tags=["session"],
)
async def update_session_preferences(
    payload: SessionPreferences,
    request: Request,
    response: Response,
    db: Annotated[Session, Depends(get_db)],
) -> SessionPreferences:
    session_id, _ = resolve_session_id(request.cookies.get(SESSION_COOKIE_NAME))
    record = get_session(db, session_id)
    if record is None:
        create_session(db, session_id, payload.model_dump(), _new_expiry())
    else:
        record.preferences = payload.model_dump()
        record.expires_at = _new_expiry()
        db.commit()
    _set_session_cookie(response, session_id)
    return payload


@app.get("/api/observations", tags=["history"])
async def observations(
    request: Request,
    instrument: str | None = None,
    category: str | None = None,
    date_from: str | None = None,
    date_to: str | None = None,
    limit: int = Query(default=1000, ge=1, le=5000),
    offset: int = Query(default=0, ge=0),
) -> Response:
    params = {
        key: value
        for key, value in {
            "instrument": instrument,
            "category": category,
            "date_from": date_from,
            "date_to": date_to,
            "limit": limit,
            "offset": offset,
        }.items()
        if value is not None
    }
    return await proxy_get(request, "/v1/observations", params)


@app.get("/api/latest", tags=["history"])
async def latest(request: Request) -> Response:
    return await proxy_get(request, "/v1/observations/latest")


@app.get("/api/instruments", tags=["history"])
async def instruments(request: Request) -> Response:
    return await proxy_get(request, "/v1/instruments")


@app.get("/{full_path:path}", include_in_schema=False)
def spa_fallback(full_path: str) -> FileResponse:
    del full_path
    return FileResponse(STATIC_DIR / "index.html")
