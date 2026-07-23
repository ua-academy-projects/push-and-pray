import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app import models  # noqa: F401  (registers all models on Base.metadata)
from app.config import get_settings
from app.database.base import Base
from app.main import app


@pytest.fixture(scope="session", autouse=True)
def _require_test_database():
    """Refuse to run if DATABASE_URL doesn't look like a test database -- these tests truncate every table."""
    url = get_settings().database_url
    if "test" not in url.rsplit("/", 1)[-1]:
        pytest.exit(
            f"DATABASE_URL does not point at a database named like '*test*' (got: {url!r}). "
            "Tests truncate all tables after every run -- refusing to run against what looks like "
            "the dev database. Set DATABASE_URL to skyivano_test before running pytest.",
            returncode=1,
        )


@pytest.fixture(scope="session")
def engine():
    return create_engine(get_settings().database_url)


@pytest.fixture(autouse=True)
def _clean_tables(engine):
    """Truncate everything after each test so tests never depend on execution order."""
    yield
    with engine.begin() as connection:
        for table in reversed(Base.metadata.sorted_tables):
            connection.execute(table.delete())


@pytest.fixture
def db_session(engine) -> Session:
    session_factory = sessionmaker(bind=engine)
    session = session_factory()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)
