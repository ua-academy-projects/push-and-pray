from collections.abc import Generator

import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from history_service.database import Base, get_db
from history_service.main import app


@pytest.fixture
def db_engine():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )

    # SQLite lacks char_length(), which the price_observations currency
    # check constraint relies on; map it onto Python's len() for tests.
    @event.listens_for(engine, "connect")
    def _register_functions(dbapi_connection, _connection_record) -> None:
        dbapi_connection.create_function("char_length", 1, len)

    Base.metadata.create_all(bind=engine)
    try:
        yield engine
    finally:
        engine.dispose()


@pytest.fixture
def session_factory(db_engine) -> sessionmaker[Session]:
    return sessionmaker(bind=db_engine, expire_on_commit=False)


@pytest.fixture
def db_session(session_factory: sessionmaker[Session]) -> Generator[Session, None, None]:
    session = session_factory()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def client_db_override(db_session: Session) -> Generator[Session, None, None]:
    def _get_db_override() -> Generator[Session, None, None]:
        yield db_session

    app.dependency_overrides[get_db] = _get_db_override
    yield db_session
    app.dependency_overrides.clear()
