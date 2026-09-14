from __future__ import annotations

from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://oil_tracker:change-me@localhost:5432/oil_tracker"

    rabbitmq_url: str
    rabbitmq_ca_file: str
    rabbitmq_queue: str
    rabbitmq_max_attempts: int = Field(gt=0)
    rabbitmq_timeout_seconds: float = Field(gt=0)
    rabbitmq_reconnect_seconds: float = Field(gt=0)

    log_level: str = "INFO"

    @field_validator("rabbitmq_url")
    @classmethod
    def require_tls(cls, value: str) -> str:
        if not value.startswith("amqps://"):
            raise ValueError("RabbitMQ requires amqps")
        return value

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
