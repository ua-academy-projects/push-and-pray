from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    open_meteo_air_quality_url: str
    backend_service_url: str

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