from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.config import get_settings
from app.database.base import Base

settings = get_settings()

engine = create_engine(
    settings.database_url,
    echo=settings.database_echo,
    pool_size=settings.database_pool_size,
    max_overflow=settings.database_max_overflow,
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def get_db() -> Generator[Session, None, None]:
    """FastAPI dependency yielding a request-scoped session, closed afterward."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    """Create any tables that don't exist yet, from the current model definitions.

    No migration step: this only ever adds missing tables and never alters or backfills
    columns on ones that already exist, so changing an existing table's columns requires
    recreating the database rather than an in-place upgrade."""
    import app.models  # noqa: F401 -- registers every model on Base.metadata

    Base.metadata.create_all(bind=engine)
