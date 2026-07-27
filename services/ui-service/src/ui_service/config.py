"""Environment-backed UI configuration."""

from functools import lru_cache
from pathlib import Path

from pydantic import AnyHttpUrl, Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

SERVICE_ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


class Settings(BaseSettings):
    """UI dependency settings."""

    model_config = SettingsConfigDict(
        env_file=SERVICE_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    history_service_url: AnyHttpUrl = AnyHttpUrl("http://127.0.0.1:8002")
    history_connect_timeout_seconds: float = Field(default=3.0, gt=0, le=60)
    history_read_timeout_seconds: float = Field(default=5.0, gt=0, le=60)
    history_write_timeout_seconds: float = Field(default=5.0, gt=0, le=60)
    history_pool_timeout_seconds: float = Field(default=3.0, gt=0, le=60)
    history_operation_timeout_seconds: float = Field(default=10.0, gt=0, le=120)
    redis_host: str = Field(default="127.0.0.1", min_length=1)
    redis_port: int = Field(default=6379, ge=1, le=65535)
    redis_db: int = Field(default=0, ge=0)
    redis_username: str | None = None
    redis_password: SecretStr | None = None
    redis_theme_prefix: str = Field(default="theme", min_length=1, max_length=128)
    redis_theme_ttl_seconds: int = Field(default=2_592_000, ge=60)
    redis_connection_timeout_seconds: float = Field(default=3.0, gt=0, le=60)
    ui_session_cookie_name: str = Field(default="theme_session", min_length=1)
    ui_session_cookie_secure: bool = False

    @field_validator("redis_username", "redis_password", mode="before")
    @classmethod
    def empty_redis_credentials_are_unset(cls, value: object) -> object:
        return None if value == "" else value

    @field_validator("redis_theme_prefix")
    @classmethod
    def normalize_redis_theme_prefix(cls, value: str) -> str:
        normalized = value.strip().strip(":")
        if not normalized:
            raise ValueError("Redis theme prefix must not be empty.")
        return normalized


@lru_cache
def get_settings() -> Settings:
    """Return process-wide UI settings."""
    return Settings()
