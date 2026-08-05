from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    open_meteo_air_quality_url: str
    backend_service_url: str
    rabbitmq_url: str

    rabbitmq_exchange: str = "airaware.measurements"
    rabbitmq_queue: str = "airaware.measurements.persist"
    rabbitmq_routing_key: str = "measurement.created"
    rabbitmq_dead_letter_exchange: str = (
        "airaware.measurements.dead-letter"
    )
    rabbitmq_dead_letter_queue: str = (
        "airaware.measurements.dead-letter"
    )

    rabbitmq_connection_timeout_seconds: float = Field(
        default=10.0,
        gt=0,
        le=120,
    )

    rabbitmq_blocked_connection_timeout_seconds: float = Field(
        default=15.0,
        gt=0,
        le=300,
    )

    rabbitmq_connection_attempts: int = Field(
        default=3,
        ge=1,
        le=10,
    )

    rabbitmq_retry_delay_seconds: float = Field(
        default=2.0,
        ge=0,
        le=60,
    )

    http_timeout_seconds: float = Field(
        default=15.0,
        gt=0,
        le=120,
    )

    fetch_minute_of_hour: int = Field(
        default=5,
        ge=0,
        le=59,
    )

    fetch_on_startup: bool = True
    scheduler_enabled: bool = True

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
