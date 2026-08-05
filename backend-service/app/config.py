from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration loaded from environment variables."""

    database_url: str
    rabbitmq_url: str

    database_connect_timeout_seconds: int = Field(
        default=5,
        ge=1,
        le=60,
    )

    rabbitmq_connection_timeout_seconds: float = Field(
        default=10.0,
        gt=0,
        le=120,
    )

    rabbitmq_exchange: str = "airaware.measurements"
    rabbitmq_queue: str = "airaware.measurements.persist"
    rabbitmq_routing_key: str = "measurement.created"
    rabbitmq_dead_letter_exchange: str = (
        "airaware.measurements.dead-letter"
    )
    rabbitmq_dead_letter_queue: str = (
        "airaware.measurements.dead-letter"
    )
    rabbitmq_consumer_enabled: bool = True
    rabbitmq_retry_delay_seconds: float = 5.0

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    """Create and cache one Settings instance."""

    return Settings()
