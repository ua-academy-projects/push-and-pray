from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://oil_tracker:change-me@localhost:5432/oil_tracker"
    history_worker_poll_interval_seconds: float = 2.0
    history_worker_max_attempts: int = 5
    history_worker_retry_backoff_seconds: float = 5.0
    history_worker_stuck_after_seconds: float = 300.0
    log_level: str = "INFO"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
