from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file="../.env", extra="ignore")

    backend_host: str = "127.0.0.1"
    backend_port: int = 8000
    ui_origin: str = "http://127.0.0.1:3000"
    history_service_url: str = "http://127.0.0.1:8081"
    history_service_token: str = "change-me"
    coingecko_base_url: str = "https://api.coingecko.com/api/v3"
    coingecko_api_key: str = ""
    frankfurter_base_url: str = "https://api.frankfurter.dev/v2"
    collector_enabled: bool = True
    collector_interval_seconds: int = 300
    log_level: str = "INFO"


@lru_cache
def get_settings() -> Settings:
    return Settings()
