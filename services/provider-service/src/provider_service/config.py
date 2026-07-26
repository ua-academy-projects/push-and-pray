"""Environment-backed Provider configuration."""

from functools import lru_cache
from pathlib import Path

from pydantic import AnyHttpUrl, Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

SERVICE_ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


class Settings(BaseSettings):
    """Provider dependency settings."""

    model_config = SettingsConfigDict(
        env_file=SERVICE_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    abuseipdb_base_url: AnyHttpUrl = AnyHttpUrl("https://api.abuseipdb.com")
    abuseipdb_api_key: SecretStr = Field(min_length=1)
    abuseipdb_connect_timeout_seconds: float = Field(default=5.0, gt=0, le=60)
    abuseipdb_read_timeout_seconds: float = Field(default=10.0, gt=0, le=60)
    abuseipdb_write_timeout_seconds: float = Field(default=5.0, gt=0, le=60)
    abuseipdb_pool_timeout_seconds: float = Field(default=5.0, gt=0, le=60)
    abuseipdb_operation_timeout_seconds: float = Field(default=20.0, gt=0, le=120)
    blacklist_polling_enabled: bool = False
    blacklist_poll_interval_seconds: int = Field(default=21600, ge=60)
    blacklist_confidence_minimum: int = Field(default=90, ge=0, le=100)
    blacklist_outbox_path: Path = Path("var/provider-blacklist-outbox.sqlite3")
    rabbitmq_host: str = Field(default="127.0.0.1", min_length=1)
    rabbitmq_port: int = Field(default=5672, ge=1, le=65535)
    rabbitmq_virtual_host: str = Field(default="/", min_length=1)
    rabbitmq_username: str = Field(default="guest", min_length=1)
    rabbitmq_password: SecretStr = Field(default=SecretStr("guest"), min_length=1)
    rabbitmq_exchange_name: str = Field(default="aegis.blacklist", min_length=1)
    rabbitmq_routing_key: str = Field(
        default="blacklist.snapshot.complete", min_length=1
    )
    rabbitmq_connection_timeout_seconds: float = Field(default=10.0, gt=0, le=120)
    rabbitmq_publish_timeout_seconds: float = Field(default=10.0, gt=0, le=120)
    rabbitmq_publish_retry_initial_seconds: int = Field(default=30, ge=1, le=3600)
    rabbitmq_publish_retry_maximum_seconds: int = Field(default=900, ge=1, le=21600)

    @field_validator("abuseipdb_base_url")
    @classmethod
    def require_https_abuseipdb_url(cls, value: AnyHttpUrl) -> AnyHttpUrl:
        if value.scheme != "https":
            raise ValueError("ABUSEIPDB_BASE_URL must use HTTPS.")
        return value

    @model_validator(mode="after")
    def validate_worker_configuration(self) -> Settings:
        if (
            self.rabbitmq_publish_retry_maximum_seconds
            < self.rabbitmq_publish_retry_initial_seconds
        ):
            raise ValueError(
                "RabbitMQ publish retry maximum must not be below initial."
            )
        return self


@lru_cache
def get_settings() -> Settings:
    """Return process-wide Provider settings."""
    return Settings()
