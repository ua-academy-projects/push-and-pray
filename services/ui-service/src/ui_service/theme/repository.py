"""Persistence boundary and Redis adapter for UI theme state."""

from typing import Protocol

from pydantic import ValidationError
from redis.asyncio import Redis
from redis.exceptions import RedisError

from ui_service.theme.models import RedisThemeValue, Theme


class ThemeApplicationError(RuntimeError):
    """Base application error for theme persistence."""


class ThemeRepositoryError(ThemeApplicationError):
    """A safe UI-state persistence failure."""


class ThemeRepository(Protocol):
    """Store UI theme state without exposing infrastructure to callers."""

    async def get_theme(self, session_id: str) -> Theme: ...

    async def set_theme(self, session_id: str, theme: Theme) -> None: ...

    async def delete_theme(self, session_id: str) -> None: ...

    async def ping(self) -> None: ...

    async def close(self) -> None: ...


class RedisThemeRepository:
    """Persist versioned theme preferences with an inactivity TTL."""

    def __init__(
        self, client: Redis, *, prefix: str = "theme", ttl_seconds: int
    ) -> None:
        normalized_prefix = prefix.strip().strip(":")
        if not normalized_prefix:
            raise ValueError("Theme key prefix must not be empty.")
        self._client = client
        self._prefix = normalized_prefix
        self._ttl_seconds = ttl_seconds

    async def get_theme(self, session_id: str) -> Theme:
        key = self._key(session_id)
        try:
            value = await self._client.get(key)
            if value is None:
                return "dark"
            await self._client.expire(key, self._ttl_seconds)
        except RedisError as error:
            raise ThemeRepositoryError("Theme storage is unavailable.") from error
        if isinstance(value, bytes):
            value = value.decode("utf-8", errors="replace")
        try:
            return RedisThemeValue.model_validate(value).root
        except ValidationError:
            return "dark"

    async def set_theme(self, session_id: str, theme: Theme) -> None:
        try:
            validated = RedisThemeValue.model_validate(theme).root
        except ValidationError:
            validated = "dark"
        try:
            await self._client.set(
                self._key(session_id),
                validated,
                ex=self._ttl_seconds,
            )
        except RedisError as error:
            raise ThemeRepositoryError("Theme storage is unavailable.") from error

    async def delete_theme(self, session_id: str) -> None:
        try:
            await self._client.delete(self._key(session_id))
        except RedisError as error:
            raise ThemeRepositoryError("Theme storage is unavailable.") from error

    async def ping(self) -> None:
        try:
            await self._client.ping()
        except RedisError as error:
            raise ThemeRepositoryError("Theme storage is unavailable.") from error

    async def close(self) -> None:
        await self._client.aclose()

    def _key(self, session_id: str) -> str:
        return f"{self._prefix}:{session_id}"
