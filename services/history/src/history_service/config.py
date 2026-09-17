from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import AliasChoices, Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://oil_tracker:change-me@localhost:5432/oil_tracker"

    queue_backend: Literal["pgmq", "rabbitmq"] = "pgmq"
    queue_name: str = Field(
        "price_observations",
        validation_alias=AliasChoices("QUEUE_NAME", "PGMQ_QUEUE"),
    )
    rabbitmq_url: str = ""

    pgmq_visibility_timeout_seconds: int = 60
    pgmq_poll_interval_seconds: float = 1.0
    pgmq_max_attempts: int = 5

    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
        populate_by_name=True,
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
