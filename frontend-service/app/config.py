from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Frontend Service configuration."""

    backend_service_url: str

    http_timeout_seconds: float = Field(
        default=10.0,
        gt=0,
        le=120,
    )

    session_ttl_seconds: int = Field(
        default=86400,
        gt=0,
        le=2_592_000,
    )

    flask_secret_key: str = Field(
        min_length=16,
    )

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )


@lru_cache
def get_settings() -> Settings:
    return Settings()
