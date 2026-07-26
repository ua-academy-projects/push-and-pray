import os
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from threading import Barrier
from uuid import UUID, uuid4

import pytest
from history_service.blacklist_ingestion import BlacklistIngestionService
from history_service.blacklist_read import BlacklistReadService
from history_service.blacklist_repository import BlacklistRepository
from history_service.blacklist_sync import MariaDBBlacklistSyncLock
from history_service.models import (
    BlacklistSnapshot,
    BlacklistSnapshotEntry,
    BlacklistSyncRun,
    IpCheckHistory,
)
from history_service.schemas import (
    ApplicationCheckRequest,
    BlacklistEntryQuery,
    BlacklistSnapshotDelivery,
    CheckCreate,
    HistoryListQuery,
    ProviderReputationRequest,
    ProviderReputationResponse,
)
from history_service.service import ApplicationService, HistoryService
from sqlalchemy import URL, create_engine, delete, event
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .conftest import check_payload

pytestmark = pytest.mark.mariadb


def test_concurrent_blacklist_delivery_is_idempotent_against_mariadb() -> None:
    if os.getenv("RUN_MARIADB_TESTS") != "1":
        pytest.skip("Set RUN_MARIADB_TESTS=1 for MariaDB integration tests.")

    required = {
        name: os.getenv(name)
        for name in (
            "TEST_MARIADB_DATABASE",
            "TEST_MARIADB_USER",
            "TEST_MARIADB_PASSWORD",
        )
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        pytest.fail(f"Missing MariaDB test settings: {', '.join(missing)}")

    url = URL.create(
        "mariadb+pymysql",
        username=required["TEST_MARIADB_USER"],
        password=required["TEST_MARIADB_PASSWORD"],
        host=os.getenv("TEST_MARIADB_HOST", "127.0.0.1"),
        port=int(os.getenv("TEST_MARIADB_PORT", "3306")),
        database=required["TEST_MARIADB_DATABASE"],
        query={"charset": "utf8mb4"},
    )
    engine = create_engine(url, pool_pre_ping=True)
    delivery_id = uuid4()
    generated_at = datetime.now(UTC)
    delivery = BlacklistSnapshotDelivery.model_validate(
        {
            "delivery_id": str(delivery_id),
            "snapshot": {
                "provider": "AbuseIPDB",
                "generated_at": generated_at.isoformat(),
                "fetched_at": generated_at.isoformat(),
                "request": {"confidence_minimum": 90, "limit": 1000},
                "rate_limit": {},
                "items": [],
            },
        }
    )
    barrier = Barrier(2)

    class RacingRepository(BlacklistRepository):
        def get_by_provider_generation(
            self,
            session: Session,
            *,
            provider: str,
            provider_generated_at: datetime,
        ) -> BlacklistSnapshot | None:
            existing = super().get_by_provider_generation(
                session,
                provider=provider,
                provider_generated_at=provider_generated_at,
            )
            if existing is None:
                barrier.wait(timeout=10)
            return existing

    def ingest_once() -> tuple[bool, int]:
        with Session(engine, expire_on_commit=False) as session:
            result = BlacklistIngestionService(repository=RacingRepository()).ingest(
                session, delivery
            )
            session.execute(BlacklistSnapshot.__table__.select().limit(1))
            return result.created, result.snapshot.snapshot_id

    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _: ingest_once(), range(2)))

        assert sorted(created for created, _ in results) == [False, True]
        assert len({snapshot_id for _, snapshot_id in results}) == 1
    finally:
        with Session(engine) as cleanup_session:
            cleanup_session.execute(
                delete(BlacklistSnapshot).where(
                    BlacklistSnapshot.delivery_id == str(delivery_id)
                )
            )
            cleanup_session.commit()
        engine.dispose()


def test_create_idempotency_listing_and_filtering_against_mariadb() -> None:
    if os.getenv("RUN_MARIADB_TESTS") != "1":
        pytest.skip("Set RUN_MARIADB_TESTS=1 for MariaDB integration tests.")

    required = {
        name: os.getenv(name)
        for name in (
            "TEST_MARIADB_DATABASE",
            "TEST_MARIADB_USER",
            "TEST_MARIADB_PASSWORD",
        )
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        pytest.fail(f"Missing MariaDB test settings: {', '.join(missing)}")

    url = URL.create(
        "mariadb+pymysql",
        username=required["TEST_MARIADB_USER"],
        password=required["TEST_MARIADB_PASSWORD"],
        host=os.getenv("TEST_MARIADB_HOST", "127.0.0.1"),
        port=int(os.getenv("TEST_MARIADB_PORT", "3306")),
        database=required["TEST_MARIADB_DATABASE"],
        query={"charset": "utf8mb4"},
    )
    engine = create_engine(url, pool_pre_ping=True)
    request_id = str(uuid4())
    payload = CheckCreate.model_validate(check_payload(request_id=request_id))
    service = HistoryService()

    try:
        with Session(engine, expire_on_commit=False) as session:
            first = service.create(session, payload)
            duplicate = service.create(session, payload)
            page = service.list(
                session, HistoryListQuery(ip_address=payload.ip_address)
            )

            assert first.created is True
            assert duplicate.created is False
            assert duplicate.record.id == first.record.id
            assert any(record.id == first.record.id for record in page.records)
    finally:
        with Session(engine) as cleanup_session:
            cleanup_session.execute(
                delete(IpCheckHistory).where(IpCheckHistory.request_id == request_id)
            )
            cleanup_session.commit()
        engine.dispose()


def test_application_lookup_persists_and_resolves_idempotency_against_mariadb() -> None:
    if os.getenv("RUN_MARIADB_TESTS") != "1":
        pytest.skip("Set RUN_MARIADB_TESTS=1 for MariaDB integration tests.")

    required = {
        name: os.getenv(name)
        for name in (
            "TEST_MARIADB_DATABASE",
            "TEST_MARIADB_USER",
            "TEST_MARIADB_PASSWORD",
        )
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        pytest.fail(f"Missing MariaDB test settings: {', '.join(missing)}")

    class FakeProvider:
        def __init__(self) -> None:
            self.calls = 0

        def check(
            self, payload: ProviderReputationRequest, *, request_id: str
        ) -> ProviderReputationResponse:
            self.calls += 1
            data = check_payload(request_id=request_id)
            data.pop("request_id")
            data["ip_address"] = payload.ip_address
            data["max_age_days"] = payload.max_age_days
            return ProviderReputationResponse.model_validate(data)

    url = URL.create(
        "mariadb+pymysql",
        username=required["TEST_MARIADB_USER"],
        password=required["TEST_MARIADB_PASSWORD"],
        host=os.getenv("TEST_MARIADB_HOST", "127.0.0.1"),
        port=int(os.getenv("TEST_MARIADB_PORT", "3306")),
        database=required["TEST_MARIADB_DATABASE"],
        query={"charset": "utf8mb4"},
    )
    engine = create_engine(url, pool_pre_ping=True)
    request_id = UUID(str(uuid4()))
    provider = FakeProvider()
    service = ApplicationService(HistoryService())
    payload = ApplicationCheckRequest(ip_address="8.8.8.8", max_age_days=90)

    try:
        with Session(engine, expire_on_commit=False) as session:
            first = service.check(session, payload, request_id, provider)
            duplicate = service.check(session, payload, request_id, provider)

            assert first.created is True
            assert duplicate.created is False
            assert duplicate.record.id == first.record.id
            assert provider.calls == 1
    finally:
        with Session(engine) as cleanup_session:
            cleanup_session.execute(
                delete(IpCheckHistory).where(
                    IpCheckHistory.request_id == str(request_id)
                )
            )
            cleanup_session.commit()
        engine.dispose()


def test_blacklist_repository_constraints_ordering_relationships_and_rollback() -> None:
    if os.getenv("RUN_MARIADB_TESTS") != "1":
        pytest.skip("Set RUN_MARIADB_TESTS=1 for MariaDB integration tests.")

    required = {
        name: os.getenv(name)
        for name in (
            "TEST_MARIADB_DATABASE",
            "TEST_MARIADB_USER",
            "TEST_MARIADB_PASSWORD",
        )
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        pytest.fail(f"Missing MariaDB test settings: {', '.join(missing)}")

    url = URL.create(
        "mariadb+pymysql",
        username=required["TEST_MARIADB_USER"],
        password=required["TEST_MARIADB_PASSWORD"],
        host=os.getenv("TEST_MARIADB_HOST", "127.0.0.1"),
        port=int(os.getenv("TEST_MARIADB_PORT", "3306")),
        database=required["TEST_MARIADB_DATABASE"],
        query={"charset": "utf8mb4"},
    )
    engine = create_engine(url, pool_pre_ping=True)
    repository = BlacklistRepository()
    generated_at = datetime.now(UTC)
    request_id = str(uuid4())
    snapshot_id: int | None = None
    run_id: int | None = None

    try:
        with Session(engine, expire_on_commit=False) as session:
            snapshot = BlacklistSnapshot(
                provider="AbuseIPDB",
                provider_generated_at=generated_at,
                fetched_at=generated_at + timedelta(seconds=2),
                confidence_minimum=90,
                requested_limit=1000,
                returned_count=2,
            )
            entries = [
                BlacklistSnapshotEntry(
                    ip_address="2606:4700:4700::1111",
                    ip_version=6,
                    abuse_confidence_score=95,
                    country_code=None,
                    last_reported_at=None,
                ),
                BlacklistSnapshotEntry(
                    ip_address="8.8.8.8",
                    ip_version=4,
                    abuse_confidence_score=100,
                    country_code="US",
                    last_reported_at=generated_at,
                ),
            ]
            repository.add_snapshot(session, snapshot, entries)
            run = BlacklistSyncRun(
                request_id=request_id,
                status="succeeded",
                started_at=generated_at,
                finished_at=generated_at + timedelta(seconds=3),
                next_attempt_at=generated_at + timedelta(hours=6),
                next_attempt_reason="base_interval",
                confidence_minimum=90,
                requested_limit=1000,
                snapshot=snapshot,
            )
            repository.add_sync_run(session, run)
            session.commit()
            snapshot_id = snapshot.snapshot_id
            run_id = run.sync_run_id
            assert run.next_attempt_reason == "base_interval"

            assert [entry.ip_address for entry in snapshot.entries] == [
                "2606:4700:4700::1111",
                "8.8.8.8",
            ]
            ordered = repository.list_entries(
                session, snapshot_id=snapshot.snapshot_id, limit=100, offset=0
            )
            assert [entry.ip_address for entry in ordered] == [
                "8.8.8.8",
                "2606:4700:4700::1111",
            ]

            query_count = 0

            def count_query(*_: object) -> None:
                nonlocal query_count
                query_count += 1

            event.listen(engine, "before_cursor_execute", count_query)
            try:
                page = BlacklistReadService(repository).latest(
                    session, BlacklistEntryQuery(limit=100, offset=0)
                )
            finally:
                event.remove(engine, "before_cursor_execute", count_query)
            assert page is not None
            assert len(page.items) == 2
            assert query_count == 3

            duplicate_snapshot = BlacklistSnapshot(
                provider="AbuseIPDB",
                provider_generated_at=generated_at,
                fetched_at=generated_at + timedelta(seconds=4),
                confidence_minimum=90,
                requested_limit=1000,
                returned_count=0,
            )
            session.add(duplicate_snapshot)
            with pytest.raises(IntegrityError):
                session.flush()
            session.rollback()

            duplicate_run = BlacklistSyncRun(
                request_id=request_id,
                status="failed",
                started_at=generated_at + timedelta(seconds=5),
                finished_at=generated_at + timedelta(seconds=6),
                confidence_minimum=90,
                requested_limit=1000,
                error_code="DUPLICATE_TEST",
            )
            with pytest.raises(IntegrityError):
                repository.add_sync_run(session, duplicate_run)
            session.rollback()

            rolled_back_generation = generated_at + timedelta(minutes=1)
            rolled_back_snapshot = BlacklistSnapshot(
                provider="AbuseIPDB",
                provider_generated_at=rolled_back_generation,
                fetched_at=generated_at + timedelta(minutes=1, seconds=2),
                confidence_minimum=90,
                requested_limit=1000,
                returned_count=2,
            )
            duplicate_entries = [
                BlacklistSnapshotEntry(
                    ip_address="1.1.1.1",
                    ip_version=4,
                    abuse_confidence_score=100,
                ),
                BlacklistSnapshotEntry(
                    ip_address="1.1.1.1",
                    ip_version=4,
                    abuse_confidence_score=99,
                ),
            ]
            with pytest.raises(IntegrityError):
                repository.add_snapshot(
                    session, rolled_back_snapshot, duplicate_entries
                )
            session.rollback()
            assert (
                repository.get_by_provider_generation(
                    session,
                    provider="AbuseIPDB",
                    provider_generated_at=rolled_back_generation,
                )
                is None
            )

            persisted_snapshot = session.get(BlacklistSnapshot, snapshot_id)
            assert persisted_snapshot is not None
            session.delete(persisted_snapshot)
            session.commit()
            assert repository.count_entries(session, snapshot_id=snapshot_id) == 0
            persisted_run = session.get(BlacklistSyncRun, run_id)
            assert persisted_run is not None
            session.refresh(persisted_run)
            assert persisted_run.snapshot_id is None
    finally:
        with Session(engine) as cleanup_session:
            if run_id is not None:
                cleanup_session.execute(
                    delete(BlacklistSyncRun).where(
                        BlacklistSyncRun.sync_run_id == run_id
                    )
                )
            if snapshot_id is not None:
                cleanup_session.execute(
                    delete(BlacklistSnapshot).where(
                        BlacklistSnapshot.snapshot_id == snapshot_id
                    )
                )
            cleanup_session.execute(
                delete(BlacklistSyncRun).where(
                    BlacklistSyncRun.request_id == request_id
                )
            )
            cleanup_session.execute(
                delete(BlacklistSnapshot).where(
                    BlacklistSnapshot.provider == "AbuseIPDB",
                    BlacklistSnapshot.provider_generated_at
                    == generated_at.replace(tzinfo=None),
                )
            )
            cleanup_session.commit()
        engine.dispose()


def test_blacklist_sync_named_lock_excludes_concurrent_connection() -> None:
    if os.getenv("RUN_MARIADB_TESTS") != "1":
        pytest.skip("Set RUN_MARIADB_TESTS=1 for MariaDB integration tests.")

    required = {
        name: os.getenv(name)
        for name in (
            "TEST_MARIADB_DATABASE",
            "TEST_MARIADB_USER",
            "TEST_MARIADB_PASSWORD",
        )
    }
    missing = [name for name, value in required.items() if not value]
    if missing:
        pytest.fail(f"Missing MariaDB test settings: {', '.join(missing)}")

    url = URL.create(
        "mariadb+pymysql",
        username=required["TEST_MARIADB_USER"],
        password=required["TEST_MARIADB_PASSWORD"],
        host=os.getenv("TEST_MARIADB_HOST", "127.0.0.1"),
        port=int(os.getenv("TEST_MARIADB_PORT", "3306")),
        database=required["TEST_MARIADB_DATABASE"],
        query={"charset": "utf8mb4"},
    )
    first_engine = create_engine(url, pool_pre_ping=True)
    second_engine = create_engine(url, pool_pre_ping=True)
    lock_name = f"aegis:test:blacklist-sync:{uuid4()}"
    first = MariaDBBlacklistSyncLock(first_engine, lock_name)
    second = MariaDBBlacklistSyncLock(second_engine, lock_name)

    try:
        with first.acquire() as first_acquired:
            assert first_acquired is True
            with second.acquire() as second_acquired:
                assert second_acquired is False
        with second.acquire() as acquired_after_release:
            assert acquired_after_release is True
    finally:
        first_engine.dispose()
        second_engine.dispose()
