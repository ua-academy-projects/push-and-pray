from __future__ import annotations

import json

import redis.asyncio as redis
from psycopg import AsyncConnection, ProgrammingError
from psycopg.types import TypeInfo
from psycopg.types.hstore import register_hstore
from pydantic import ValidationError

from .sessions import SessionPreferences


class PostgreSQLSessionStore:
    def __init__(self, database_url: str, ttl_seconds: int) -> None:
        self.database_url = database_url.replace("postgresql+psycopg://", "postgresql://", 1)
        self.ttl_seconds = ttl_seconds
        self._hstore_info: TypeInfo | None = None

    async def _connect(self) -> AsyncConnection:
        connection = await AsyncConnection.connect(self.database_url, connect_timeout=5)
        hstore_info = self._hstore_info
        if hstore_info is None:
            hstore_info = await TypeInfo.fetch(connection, "hstore")
            if hstore_info is None:
                await connection.close()
                raise ProgrammingError("the PostgreSQL hstore extension is not installed")
            self._hstore_info = hstore_info
        register_hstore(hstore_info, connection)
        return connection

    @staticmethod
    def _serialize(preferences: SessionPreferences) -> dict[str, str]:
        return {
            key: json.dumps(value, separators=(",", ":"))
            for key, value in preferences.model_dump(mode="json").items()
        }

    @staticmethod
    def _deserialize(preferences: dict[str, str | None]) -> dict[str, object]:
        return {key: json.loads(value) for key, value in preferences.items()}

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
                            SELECT 1 FROM pg_extension WHERE extname = 'hstore'
                        )
                        AND EXISTS (
                            SELECT 1
                            FROM information_schema.columns
                            WHERE table_schema = 'public'
                              AND table_name = 'ui_sessions'
                              AND column_name = 'preferences'
                              AND udt_name = 'hstore'
                              AND is_nullable = 'NO'
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
        async with await self._connect() as connection:
            async with connection.cursor(binary=True) as cursor:
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
                    (session_id, self._serialize(defaults), self.ttl_seconds),
                )
                row = await cursor.fetchone()

        try:
            stored_preferences = self._deserialize(row[0]) if row else {}
            return SessionPreferences.model_validate(stored_preferences)
        except (TypeError, ValueError, ValidationError):
            return await self.update(session_id, defaults)

    async def update(
        self,
        session_id: str,
        preferences: SessionPreferences,
    ) -> SessionPreferences:
        async with await self._connect() as connection:
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
                        self._serialize(preferences),
                        self.ttl_seconds,
                    ),
                )
        return preferences


class RedisSessionStore:
    def __init__(self, redis_url: str, ttl_seconds: int) -> None:
        self.ttl_seconds = ttl_seconds
        self.client = redis.Redis.from_url(
            redis_url,
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5,
            health_check_interval=30,
        )

    @staticmethod
    def _key(session_id: str) -> str:
        return f"ui:session:{session_id}"

    async def close(self) -> None:
        await self.client.aclose()

    async def is_ready(self) -> bool:
        return bool(await self.client.ping())

    async def get(self, session_id: str) -> SessionPreferences:
        key = self._key(session_id)
        stored = await self.client.get(key)
        if stored is None:
            preferences = SessionPreferences()
            await self.client.set(key, preferences.model_dump_json(), ex=self.ttl_seconds)
            return preferences

        try:
            preferences = SessionPreferences.model_validate_json(stored)
        except ValidationError:
            preferences = SessionPreferences()
            await self.client.set(key, preferences.model_dump_json(), ex=self.ttl_seconds)
        else:
            await self.client.expire(key, self.ttl_seconds)
        return preferences

    async def update(
        self,
        session_id: str,
        preferences: SessionPreferences,
    ) -> SessionPreferences:
        await self.client.set(
            self._key(session_id), preferences.model_dump_json(), ex=self.ttl_seconds
        )
        return preferences
