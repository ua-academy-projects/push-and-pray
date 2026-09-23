from __future__ import annotations

import hashlib

from pydantic import ValidationError
from redis.asyncio import Redis

from .sessions import SessionPreferences


class RedisSessionStore:
    def __init__(self, redis_url: str, ttl_seconds: int) -> None:
        self.redis = Redis.from_url(redis_url, decode_responses=True)
        self.ttl_seconds = ttl_seconds

    @staticmethod
    def _key(session_id: str) -> str:
        digest = hashlib.sha256(session_id.encode()).hexdigest()
        return f"petroscope:session:{digest}"

    async def is_ready(self) -> bool:
        return bool(await self.redis.ping())

    async def get(self, session_id: str) -> SessionPreferences:
        key = self._key(session_id)
        stored = await self.redis.get(key)
        if stored is None:
            preferences = SessionPreferences()
        else:
            try:
                preferences = SessionPreferences.model_validate_json(stored)
            except ValidationError:
                preferences = SessionPreferences()
        await self.redis.setex(key, self.ttl_seconds, preferences.model_dump_json())
        return preferences

    async def update(
        self,
        session_id: str,
        preferences: SessionPreferences,
    ) -> SessionPreferences:
        await self.redis.setex(
            self._key(session_id),
            self.ttl_seconds,
            preferences.model_dump_json(),
        )
        return preferences

    async def close(self) -> None:
        await self.redis.aclose()
