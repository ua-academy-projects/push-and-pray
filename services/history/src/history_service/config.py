from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://oil_tracker:change-me@localhost:5432/oil_tracker"
    rabbitmq_url: str = "amqp://oil_tracker:change-me@localhost:5672/oil_tracker"
    rabbitmq_exchange: str = "oil.price.events"
    rabbitmq_queue: str = "history.price-observations"
    rabbitmq_routing_key: str = "prices.observed"
    log_level: str = "INFO"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
