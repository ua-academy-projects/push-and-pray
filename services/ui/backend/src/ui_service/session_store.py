from __future__ import annotations

import hashlib

from redis.asyncio import Redis
from redis.exceptions import RedisError

from .sessions import SessionPreferences


class RedisSessionStore:
    def __init__(self, url: str, ttl_seconds: int, key_prefix: str) -> None:
        self.client = Redis.from_url(url, decode_responses=True, socket_timeout=5)
        self.ttl_seconds = ttl_seconds
        self.key_prefix = key_prefix

    def _key(self, session_id: str) -> str:
        return self.key_prefix + hashlib.sha256(session_id.encode()).hexdigest()

    async def is_ready(self) -> bool:
        return bool(await self.client.ping())

    async def diagnostics(self) -> dict[str, object]:
        """Memory pressure and persistence status for operator visibility.

        Never raises: a failed INFO call is reported as an error field, not
        propagated, since readiness is already governed by is_ready()/PING.
        """
        try:
            memory = await self.client.info("memory")
            persistence = await self.client.info("persistence")
        except RedisError as exc:
            return {"error": str(exc)}
        return {
            "used_memory": memory.get("used_memory"),
            "used_memory_human": memory.get("used_memory_human"),
            "maxmemory": memory.get("maxmemory"),
            "maxmemory_policy": memory.get("maxmemory_policy"),
            "aof_enabled": bool(persistence.get("aof_enabled")),
            "aof_last_write_status": persistence.get("aof_last_write_status"),
            "aof_last_bgrewrite_status": persistence.get("aof_last_bgrewrite_status"),
            "rdb_last_bgsave_status": persistence.get("rdb_last_bgsave_status"),
        }

    async def close(self) -> None:
        await self.client.aclose()

    async def get(self, session_id: str) -> SessionPreferences:
        defaults = SessionPreferences().model_dump_json()
        key = self._key(session_id)
        raw = await self.client.eval(
            """
            local value = redis.call('GET', KEYS[1])
            if not value then value = ARGV[1]; redis.call('SET', KEYS[1], value) end
            redis.call('EXPIRE', KEYS[1], ARGV[2])
            return value
            """,
            1,
            key,
            defaults,
            self.ttl_seconds,
        )
        try:
            return SessionPreferences.model_validate_json(raw)
        except ValueError:
            # Repair only the corrupt value we read; do not overwrite a concurrent PUT.
            raw = await self.client.eval(
                """
                local value = redis.call('GET', KEYS[1])
                if not value or value == ARGV[1] then
                    value = ARGV[2]
                    redis.call('SET', KEYS[1], value, 'EX', ARGV[3])
                end
                return value
                """,
                1,
                key,
                raw,
                defaults,
                self.ttl_seconds,
            )
            try:
                return SessionPreferences.model_validate_json(raw)
            except ValueError as exc:
                raise RedisError("Invalid session data") from exc

    async def update(self, session_id: str, preferences: SessionPreferences) -> SessionPreferences:
        await self.client.set(
            self._key(session_id), preferences.model_dump_json(), ex=self.ttl_seconds
        )
        return preferences
