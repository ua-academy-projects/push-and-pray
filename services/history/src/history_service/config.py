from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://oil_tracker:change-me@localhost:5432/oil_tracker"

    # The queue is either PGMQ inside that same database or an AMQP broker
    # beside it. Both consumers ship in the image; the deployment picks one.
    queue_backend: Literal["pgmq", "amqp"] = "pgmq"

    pgmq_queue: str = "price_observations"
    pgmq_visibility_timeout_seconds: int = 60
    pgmq_poll_interval_seconds: float = 1.0
    pgmq_max_attempts: int = 5

    amqp_url: str = "amqp://oil_tracker:change-me@localhost:5672/oil_tracker"
    amqp_exchange: str = "oil.price.events"
    amqp_queue: str = "history.price-observations"
    amqp_routing_key: str = "prices.observed"
    amqp_max_attempts: int = 5
    amqp_prefetch_count: int = 1
    amqp_retry_delay_seconds: float = 1.0
    amqp_reconnect_delay_seconds: float = 5.0

    log_level: str = "INFO"

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
