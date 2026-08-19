import asyncio
import os
from datetime import timedelta
from time import monotonic

import httpx
import psycopg
import pytest
from psycopg.types.json import Jsonb

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


def test_extensions_and_postgresql_hashing_are_active() -> None:
    reset_sessions()
    store = PostgreSQLSessionStore(database_url(), SESSION_TTL_SECONDS)
    session_id = "a" * 43
    preferences = SessionPreferences()
    asyncio.run(store.update(session_id, preferences))

    with psycopg.connect(database_url()) as connection, connection.cursor() as cursor:
        cursor.execute(
            """
            SELECT array_agg(extname ORDER BY extname)
            FROM pg_extension
            WHERE extname IN ('pg_cron', 'pgcrypto')
            """
        )
        assert cursor.fetchone()[0] == ["pg_cron", "pgcrypto"]
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
        cursor.execute(
            """
            SELECT preferences, octet_length(session_hash)
            FROM ui_sessions
            WHERE session_hash = digest(%s, 'sha256')
            """,
            (session_id,),
        )
        stored_preferences, hash_length = cursor.fetchone()
        assert stored_preferences == preferences.model_dump(mode="json")
        assert hash_length == 32


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
        expired_preferences = {**SessionPreferences().model_dump(), "range": "365"}

        with psycopg.connect(database_url()) as connection, connection.cursor() as cursor:
            cursor.execute(
                """
                SELECT cron.alter_job(jobid, schedule := '1 second')
                FROM cron.job
                WHERE jobname = 'delete-expired-ui-sessions'
                  AND database = current_database()
                """
            )
            cursor.executemany(
                """
                INSERT INTO ui_sessions (session_hash, preferences, expires_at)
                VALUES (digest(%s, 'sha256'), %s, CURRENT_TIMESTAMP - interval '1 minute')
                """,
                [
                    (expired_session_id, Jsonb(expired_preferences)),
                    (cleanup_session_id, Jsonb(expired_preferences)),
                ],
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
