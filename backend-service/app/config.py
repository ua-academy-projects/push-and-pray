from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Backend Service configuration, sourced entirely from environment variables."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    open_meteo_base_url: str = "https://api.open-meteo.com/v1/forecast"
    history_service_base_url: str = "http://localhost:8001"
    http_timeout_seconds: float = 10.0

    weather_location_name: str = "Ivano-Frankivsk"
    weather_country: str = "Ukraine"
    weather_latitude: float = 48.9226
    weather_longitude: float = 24.7111
    weather_timezone: str = "Europe/Kyiv"

    weather_sync_enabled: bool = True
    weather_sync_interval_minutes: int = 60
    weather_sync_on_startup: bool = True
    weather_sync_startup_freshness_minutes: int = 60
    weather_data_max_age_minutes: int = 90

    backend_port: int = 8000
    backend_cors_origins: str = "http://localhost:5173"

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.backend_cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
