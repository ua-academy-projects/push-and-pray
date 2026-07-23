from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """History Service configuration, sourced entirely from environment variables."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    database_url: str
    database_echo: bool = False
    database_pool_size: int = 5
    database_max_overflow: int = 10
    history_service_port: int = 8001


@lru_cache
def get_settings() -> Settings:
    return Settings()
