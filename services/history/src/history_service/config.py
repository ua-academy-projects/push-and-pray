from __future__ import annotations

from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://oil_tracker:change-me@localhost:5432/oil_tracker"

    pgmq_queue: str = "price_observations"
    pgmq_visibility_timeout_seconds: int = 60
    pgmq_poll_interval_seconds: float = 1.0
    pgmq_max_attempts: int = 5

    messaging_backend: str = "pgmq"
    rabbitmq_host: str = ""
    rabbitmq_port: int = 5672
    rabbitmq_user: str = "oil_tracker"
    rabbitmq_password: str = ""
    rabbitmq_vhost: str = "oil_tracker"
    rabbitmq_queue: str = "price_observations"

    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
    )

    @field_validator("messaging_backend")
    @classmethod
    def validate_messaging_backend(cls, value: str) -> str:
        if value not in {"pgmq", "rabbitmq"}:
            raise ValueError("MESSAGING_BACKEND must be pgmq or rabbitmq")
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
