from __future__ import annotations

import hashlib
import json

from psycopg import AsyncConnection
from psycopg.types.json import Jsonb
from pydantic import ValidationError
from redis.asyncio import Redis

from .sessions import SessionPreferences


class PostgreSQLSessionStore:
    def __init__(self, database_url: str, ttl_seconds: int) -> None:
        self.database_url = database_url.replace("postgresql+psycopg://", "postgresql://", 1)
        self.ttl_seconds = ttl_seconds

    async def _connect(self) -> AsyncConnection:
        return await AsyncConnection.connect(self.database_url, connect_timeout=5)

    @staticmethod
    def _serialize(preferences: SessionPreferences) -> Jsonb:
        return Jsonb(preferences.model_dump(mode="json"))

    @staticmethod
    def _session_hash(session_id: str) -> bytes:
        return hashlib.sha256(session_id.encode()).digest()

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
                            SELECT 1
                            FROM information_schema.columns
                            WHERE table_schema = 'public'
                              AND table_name = 'ui_sessions'
                              AND column_name = 'preferences'
                              AND udt_name = 'jsonb'
                              AND is_nullable = 'NO'
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
                    "DELETE FROM ui_sessions WHERE expires_at <= CURRENT_TIMESTAMP"
                )
                await cursor.execute(
                    """
                    INSERT INTO ui_sessions AS sessions (session_hash, preferences, expires_at)
                    VALUES (
                        %s,
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
                    (
                        self._session_hash(session_id),
                        self._serialize(defaults),
                        self.ttl_seconds,
                    ),
                )
                row = await cursor.fetchone()

        try:
            stored_preferences = row[0] if row else {}
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
                    "DELETE FROM ui_sessions WHERE expires_at <= CURRENT_TIMESTAMP"
                )
                await cursor.execute(
                    """
                    INSERT INTO ui_sessions (session_hash, preferences, expires_at)
                    VALUES (
                        %s,
                        %s,
                        CURRENT_TIMESTAMP + make_interval(secs => %s)
                    )
                    ON CONFLICT (session_hash) DO UPDATE
                    SET preferences = EXCLUDED.preferences,
                        expires_at = EXCLUDED.expires_at
                    """,
                    (
                        self._session_hash(session_id),
                        self._serialize(preferences),
                        self.ttl_seconds,
                    ),
                )
        return preferences


class RedisSessionStore:
    def __init__(self, redis_url: str, ttl_seconds: int) -> None:
        self.client = Redis.from_url(redis_url, decode_responses=True)
        self.ttl_seconds = ttl_seconds

    @staticmethod
    def _key(session_id: str) -> str:
        digest = hashlib.sha256(session_id.encode()).hexdigest()
        return f"oilscope:session:{digest}"

    async def is_ready(self) -> bool:
        return bool(await self.client.ping())

    async def get(self, session_id: str) -> SessionPreferences:
        key = self._key(session_id)
        stored = await self.client.get(key)
        if stored is None:
            return await self.update(session_id, SessionPreferences())

        await self.client.expire(key, self.ttl_seconds)
        try:
            return SessionPreferences.model_validate_json(stored)
        except (TypeError, ValueError, ValidationError):
            return await self.update(session_id, SessionPreferences())

    async def update(
        self,
        session_id: str,
        preferences: SessionPreferences,
    ) -> SessionPreferences:
        await self.client.set(
            self._key(session_id),
            json.dumps(preferences.model_dump(mode="json"), separators=(",", ":")),
            ex=self.ttl_seconds,
        )
        return preferences

    async def close(self) -> None:
        await self.client.aclose()
