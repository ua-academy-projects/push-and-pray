"""Environment-backed configuration for the History service."""

from functools import lru_cache
from pathlib import Path

from pydantic import AnyHttpUrl, Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy import URL

SERVICE_ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


class Settings(BaseSettings):
    """MariaDB connection settings."""

    model_config = SettingsConfigDict(
        env_file=SERVICE_ENV_FILE,
        env_file_encoding="utf-8",
        extra="ignore",
    )

    mariadb_host: str = "127.0.0.1"
    mariadb_port: int = Field(default=3306, ge=1, le=65535)
    mariadb_database: str
    mariadb_user: str
    mariadb_password: SecretStr
    rabbitmq_host: str = Field(default="127.0.0.1", min_length=1)
    rabbitmq_port: int = Field(default=5672, ge=1, le=65535)
    rabbitmq_virtual_host: str = Field(default="/", min_length=1)
    rabbitmq_username: str = Field(default="guest", min_length=1)
    rabbitmq_password: SecretStr = Field(default=SecretStr("guest"), min_length=1)
    rabbitmq_exchange_name: str = Field(default="aegis.blacklist", min_length=1)
    rabbitmq_queue_name: str = Field(
        default="aegis.history.blacklist.snapshots", min_length=1
    )
    rabbitmq_retry_exchange_name: str = Field(
        default="aegis.blacklist.retry", min_length=1
    )
    rabbitmq_dead_letter_exchange_name: str = Field(
        default="aegis.blacklist.dead", min_length=1
    )
    rabbitmq_dead_letter_queue_name: str = Field(
        default="aegis.history.blacklist.snapshots.dead", min_length=1
    )
    rabbitmq_routing_key: str = Field(
        default="blacklist.snapshot.complete", min_length=1
    )
    rabbitmq_prefetch_count: int = Field(default=1, ge=1, le=1000)
    rabbitmq_connection_timeout_seconds: float = Field(default=10.0, gt=0, le=120)
    rabbitmq_publish_timeout_seconds: float = Field(default=10.0, gt=0, le=120)
    rabbitmq_shutdown_timeout_seconds: float = Field(default=30.0, gt=0, le=300)
    provider_service_url: AnyHttpUrl = AnyHttpUrl("http://127.0.0.1:8001")
    provider_connect_timeout_seconds: float = Field(default=5.0, gt=0, le=60)
    provider_read_timeout_seconds: float = Field(default=10.0, gt=0, le=60)
    provider_write_timeout_seconds: float = Field(default=5.0, gt=0, le=60)
    provider_pool_timeout_seconds: float = Field(default=5.0, gt=0, le=60)
    blacklist_stale_after_seconds: int = Field(default=43200, ge=60)

    def database_url(self) -> URL:
        """Build a safely escaped MariaDB connection URL."""
        return URL.create(
            drivername="mariadb+pymysql",
            username=self.mariadb_user,
            password=self.mariadb_password.get_secret_value(),
            host=self.mariadb_host,
            port=self.mariadb_port,
            database=self.mariadb_database,
            query={"charset": "utf8mb4"},
        )


@lru_cache
def get_settings() -> Settings:
    """Return the process-wide settings instance."""
    return Settings()
