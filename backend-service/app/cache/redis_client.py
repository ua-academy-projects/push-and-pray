from functools import lru_cache

import redis

from app.config import get_settings


@lru_cache
def get_redis_client() -> redis.Redis:
    """One process-wide client, same lifetime as the SQLAlchemy engine in
    app/database/session.py. decode_responses=True so callers get str, not bytes."""
    settings = get_settings()
    return redis.Redis.from_url(settings.redis_url, decode_responses=True)


def get_redis() -> redis.Redis:
    """FastAPI dependency -- mirrors get_db()'s role for Postgres, but Redis's client is
    already connection-pooled internally, so there's no per-request session to open/close."""
    return get_redis_client()
