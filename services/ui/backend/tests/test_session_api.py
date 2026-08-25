import asyncio
import json
import os
from datetime import timedelta
from time import monotonic

import httpx
import psycopg
import pytest
from psycopg.types import TypeInfo
from psycopg.types.hstore import register_hstore

from ui_service.main import SESSION_TTL_SECONDS, app
from ui_service.session_store import PostgreSQLSessionStore
from ui_service.sessions import SessionPreferences

TEST_DATABASE_URL = os.getenv("TEST_DATABASE_URL")

pytestmark = pytest.mark.skipif(
    not TEST_DATABASE_URL,
    reason="TEST_DATABASE_URL must point to a migrated PostgreSQL 18 test database",
)


def database_url() -> str:
    assert TEST_DATABASE_URL
    return TEST_DATABASE_URL.replace("postgresql+psycopg://", "postgresql://", 1)


def reset_sessions() -> None:
    with psycopg.connect(database_url()) as connection, connection.cursor() as cursor:
        cursor.execute("TRUNCATE ui_sessions")


def test_hstore_extensions_and_postgresql_hashing_are_active() -> None:
    reset_sessions()
    store = PostgreSQLSessionStore(database_url(), SESSION_TTL_SECONDS)
    session_id = "a" * 43
    preferences = SessionPreferences()
    asyncio.run(store.update(session_id, preferences))

    with psycopg.connect(database_url()) as connection:
        hstore_info = TypeInfo.fetch(connection, "hstore")
        assert hstore_info is not None
        register_hstore(hstore_info, connection)
        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT array_agg(extname ORDER BY extname)
            FROM pg_extension
            WHERE extname IN ('hstore', 'pg_cron', 'pgcrypto')
            """
        )
        assert cursor.fetchone()[0] == ["hstore", "pg_cron", "pgcrypto"]
        cursor.execute(
            """
            SELECT udt_name, is_nullable
            FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = 'ui_sessions'
              AND column_name = 'preferences'
            """
        )
        assert cursor.fetchone() == ("hstore", "NO")
        cursor.execute(
            """
            SELECT schedule, active, command
            FROM cron.job
            WHERE jobname = 'delete-expired-ui-sessions'
              AND database = current_database()
            """
        )
        schedule, active, command = cursor.fetchone()
        assert schedule == "* * * * *"
        assert active is True
        assert "DELETE FROM public.ui_sessions" in command
        hstore_cursor = connection.cursor(binary=True)
        hstore_cursor.execute(
            """
            SELECT preferences, octet_length(session_hash)
            FROM ui_sessions
            WHERE session_hash = digest(%s, 'sha256')
            """,
            (session_id,),
        )
        stored_preferences, hash_length = hstore_cursor.fetchone()
        restored_preferences = {key: json.loads(value) for key, value in stored_preferences.items()}
        assert restored_preferences == preferences.model_dump(mode="json")
        assert hash_length == 32
        assert asyncio.run(store.is_ready()) is True


def test_session_persistence_and_sliding_expiration() -> None:
    async def exercise_session() -> None:
        reset_sessions()
        app.state.session_store = PostgreSQLSessionStore(database_url(), SESSION_TTL_SECONDS)
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            initial = await client.get("/api/session/preferences")
            assert initial.status_code == 200
            assert initial.json()["selected"] is None
            session_id = initial.cookies["petroscope_session"]

            async with httpx.AsyncClient(
                transport=transport,
                base_url="http://test",
                cookies={"petroscope_session": "invalid-cookie"},
            ) as invalid_cookie_client:
                invalid_cookie_response = await invalid_cookie_client.get(
                    "/api/session/preferences"
                )
            assert invalid_cookie_response.status_code == 200
            assert invalid_cookie_response.json() == initial.json()
            assert invalid_cookie_response.cookies["petroscope_session"] != "invalid-cookie"

            payloads = [
                {**initial.json(), "selected": ["WTI_USD_BBL"], "range": "7"},
                {**initial.json(), "selected": ["BRENT_USD_BBL"], "range": "90"},
            ]
            responses = await asyncio.gather(
                *(client.put("/api/session/preferences", json=payload) for payload in payloads)
            )
            assert all(response.status_code == 200 for response in responses)

            with psycopg.connect(database_url()) as connection, connection.cursor() as cursor:
                cursor.execute(
                    """
                    UPDATE ui_sessions
                    SET expires_at = CURRENT_TIMESTAMP + interval '1 hour'
                    WHERE session_hash = digest(%s, 'sha256')
                    RETURNING expires_at
                    """,
                    (session_id,),
                )
                previous_expiration = cursor.fetchone()[0]

            restored = await client.get("/api/session/preferences")
            assert restored.json() in payloads

            with psycopg.connect(database_url()) as connection, connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT count(*), min(expires_at), CURRENT_TIMESTAMP
                    FROM ui_sessions
                    WHERE session_hash = digest(%s, 'sha256')
                    """,
                    (session_id,),
                )
                count, refreshed_expiration, database_now = cursor.fetchone()
            assert count == 1
            assert refreshed_expiration > previous_expiration
            assert refreshed_expiration - database_now >= timedelta(seconds=SESSION_TTL_SECONDS - 5)

    asyncio.run(exercise_session())


def test_expired_sessions_are_invalid_and_cleaned_by_pg_cron() -> None:
    async def exercise_expiration() -> None:
        reset_sessions()
        app.state.session_store = PostgreSQLSessionStore(database_url(), SESSION_TTL_SECONDS)
        expired_session_id = "e" * 43
        cleanup_session_id = "c" * 43
        expired_preferences = SessionPreferences(range="365")

        store = PostgreSQLSessionStore(database_url(), SESSION_TTL_SECONDS)
        await store.update(expired_session_id, expired_preferences)
        await store.update(cleanup_session_id, expired_preferences)

        with psycopg.connect(database_url()) as connection, connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT cron.alter_job(jobid, schedule := '1 second')
                FROM cron.job
                WHERE jobname = 'delete-expired-ui-sessions'
                  AND database = current_database()
                """
            )
            cursor.execute(
                """
                UPDATE ui_sessions
                SET expires_at = CURRENT_TIMESTAMP - interval '1 minute'
                WHERE session_hash IN (digest(%s, 'sha256'), digest(%s, 'sha256'))
                """,
                (expired_session_id, cleanup_session_id),
            )

        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            client.cookies.set("petroscope_session", expired_session_id)
            response = await client.get("/api/session/preferences")
        assert response.status_code == 200
        assert response.json()["range"] == "30"

        try:
            deadline = monotonic() + 10
            while monotonic() < deadline:
                with psycopg.connect(database_url()) as connection, connection.cursor() as cursor:
                    cursor.execute(
                        """
                        SELECT EXISTS (
                            SELECT 1 FROM ui_sessions
                            WHERE session_hash = digest(%s, 'sha256')
                        )
                        """,
                        (cleanup_session_id,),
                    )
                    if cursor.fetchone()[0] is False:
                        break
                await asyncio.sleep(0.5)
            else:
                pytest.fail("pg_cron did not delete the expired session within 10 seconds")
        finally:
            with psycopg.connect(database_url()) as connection, connection.cursor() as cursor:
                cursor.execute(
                    """
                    SELECT cron.alter_job(jobid, schedule := '* * * * *')
                    FROM cron.job
                    WHERE jobname = 'delete-expired-ui-sessions'
                      AND database = current_database()
                    """
                )

    asyncio.run(exercise_expiration())
