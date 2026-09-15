from __future__ import annotations

import hashlib

import redis.asyncio as redis
from pydantic import ValidationError

from .sessions import SessionPreferences


class RedisSessionStore:
    """Redis implementation of the session store, used in managed mode.

    Mirrors PostgreSQLSessionStore's contract (is_ready / get / update). As
    with the Postgres store, the raw session id is never stored: the Redis key
    is its SHA-256 hash. TTL is the session expiry, refreshed on every read so
    an active session keeps rolling; Redis expiry replaces the pg_cron cleanup
    job used by the Postgres backend.
    """

    def __init__(self, redis_url: str, ttl_seconds: int) -> None:
        self.redis_url = redis_url
        self.ttl_seconds = ttl_seconds
        self._client: redis.Redis | None = None

    def _key(self, session_id: str) -> str:
        digest = hashlib.sha256(session_id.encode("utf-8")).hexdigest()
        return f"ui_session:{digest}"

    async def _connect(self) -> redis.Redis:
        if self._client is None:
            self._client = redis.from_url(
                self.redis_url,
                encoding="utf-8",
                decode_responses=True,
            )
        return self._client

    async def is_ready(self) -> bool:
        try:
            client = await self._connect()
            return bool(await client.ping())
        except Exception:
            return False

    async def get(self, session_id: str) -> SessionPreferences:
        client = await self._connect()
        key = self._key(session_id)

        raw = await client.get(key)
        if raw is None:
            defaults = SessionPreferences()
            await client.set(key, defaults.model_dump_json(), ex=self.ttl_seconds)
            return defaults

        try:
            preferences = SessionPreferences.model_validate_json(raw)
        except ValidationError:
            defaults = SessionPreferences()
            await client.set(key, defaults.model_dump_json(), ex=self.ttl_seconds)
            return defaults

        await client.expire(key, self.ttl_seconds)
        return preferences

    async def update(
        self,
        session_id: str,
        preferences: SessionPreferences,
    ) -> SessionPreferences:
        client = await self._connect()
        await client.set(
            self._key(session_id),
            preferences.model_dump_json(),
            ex=self.ttl_seconds,
        )
        return preferences
