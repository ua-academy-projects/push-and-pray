from __future__ import annotations

from psycopg import AsyncConnection
from psycopg.types.json import Jsonb
from pydantic import ValidationError

from .sessions import SessionPreferences


class PostgreSQLSessionStore:
    def __init__(self, database_url: str, ttl_seconds: int) -> None:
        self.database_url = database_url.replace("postgresql+psycopg://", "postgresql://", 1)
        self.ttl_seconds = ttl_seconds

    async def is_ready(self) -> bool:
        async with await AsyncConnection.connect(
            self.database_url, connect_timeout=5
        ) as connection:
            async with connection.cursor() as cursor:
                await cursor.execute(
                    """
                    SELECT
                        to_regclass('public.ui_sessions') IS NOT NULL
                        AND EXISTS (
                            SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto'
                        )
                        AND EXISTS (
                            SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
                        )
                        AND EXISTS (
                            SELECT 1
                            FROM cron.job
                            WHERE jobname = 'delete-expired-ui-sessions'
                              AND database = current_database()
                              AND active
                        )
                    """
                )
                row = await cursor.fetchone()
        return bool(row and row[0])

    async def get(self, session_id: str) -> SessionPreferences:
        defaults = SessionPreferences()
        async with await AsyncConnection.connect(
            self.database_url, connect_timeout=5
        ) as connection:
            async with connection.cursor() as cursor:
                await cursor.execute(
                    """
                    INSERT INTO ui_sessions AS sessions (session_hash, preferences, expires_at)
                    VALUES (
                        digest(%s, 'sha256'),
                        %s,
                        CURRENT_TIMESTAMP + make_interval(secs => %s)
                    )
                    ON CONFLICT (session_hash) DO UPDATE
                    SET preferences = CASE
                            WHEN sessions.expires_at <= CURRENT_TIMESTAMP
                                THEN EXCLUDED.preferences
                            ELSE sessions.preferences
                        END,
                        expires_at = EXCLUDED.expires_at
                    RETURNING preferences
                    """,
                    (session_id, Jsonb(defaults.model_dump(mode="json")), self.ttl_seconds),
                )
                row = await cursor.fetchone()

        try:
            return SessionPreferences.model_validate(row[0] if row else {})
        except ValidationError:
            return await self.update(session_id, defaults)

    async def update(
        self,
        session_id: str,
        preferences: SessionPreferences,
    ) -> SessionPreferences:
        async with await AsyncConnection.connect(
            self.database_url, connect_timeout=5
        ) as connection:
            async with connection.cursor() as cursor:
                await cursor.execute(
                    """
                    INSERT INTO ui_sessions (session_hash, preferences, expires_at)
                    VALUES (
                        digest(%s, 'sha256'),
                        %s,
                        CURRENT_TIMESTAMP + make_interval(secs => %s)
                    )
                    ON CONFLICT (session_hash) DO UPDATE
                    SET preferences = EXCLUDED.preferences,
                        expires_at = EXCLUDED.expires_at
                    """,
                    (
                        session_id,
                        Jsonb(preferences.model_dump(mode="json")),
                        self.ttl_seconds,
                    ),
                )
        return preferences
