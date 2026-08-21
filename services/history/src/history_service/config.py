from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://oil_tracker:change-me@localhost:5432/oil_tracker"

    pgmq_queue: str = "price_observations"
    pgmq_visibility_timeout_seconds: int = 60
    pgmq_poll_interval_seconds: float = 1.0
    pgmq_max_attempts: int = 5

    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
