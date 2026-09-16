from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://oil_tracker:change-me@localhost:5432/oil_tracker"

    messaging_provider: str = "pgmq"
    pgmq_queue: str = "price_observations"
    pgmq_visibility_timeout_seconds: int = 60
    pgmq_poll_interval_seconds: float = 1
    pgmq_max_attempts: int = 5

    rabbitmq_url: str = ""
    rabbitmq_exchange: str = "oil.price.events"
    rabbitmq_queue: str = "price_observations"
    rabbitmq_routing_key: str = "prices.observed"
    rabbitmq_max_attempts: int = 5

    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    settings = Settings()
    if settings.messaging_provider not in {"pgmq", "rabbitmq"}:
        raise ValueError("MESSAGING_PROVIDER must be pgmq or rabbitmq")
    if settings.messaging_provider == "rabbitmq" and not settings.rabbitmq_url:
        raise ValueError("RABBITMQ_URL is required for RabbitMQ")
    return settings
