from __future__ import annotations

from datetime import datetime

from sqlalchemy import select, func
from sqlalchemy.orm import Session
from .models import SessionRecord

def get_session(db:Session, session_id: str) -> SessionRecord | None:
    statement = select(SessionRecord).where(
        SessionRecord.session_id == session_id,
        SessionRecord.expires_at > func.now(),
    )
    return db.execute(statement).scalar_one_or_none()

def create_session(db: Session, session_id: str, preferences: str, expires_at: datetime) -> SessionRecord:
    sessionRecord = SessionRecord(session_id=session_id, preferences=preferences, expires_at=expires_at)
    db.add(sessionRecord)
    db.commit()
    return sessionRecord

def refresh_session(db: Session, session_id: str, expires_at: datetime) -> None:
    sessionRecord = db.get(SessionRecord, session_id)
    sessionRecord.expires_at = expires_at
    db.commit()