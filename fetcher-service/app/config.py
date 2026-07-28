from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Weather Fetcher Service configuration, sourced entirely from environment variables."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    open_meteo_base_url: str = "https://api.open-meteo.com/v1/forecast"
    backend_internal_base_url: str = "http://localhost:8000"
    http_timeout_seconds: float = 10.0

    # --- RabbitMQ (async push of completed/failed syncs to the Backend) ---
    # This is the only way a sync result reaches the Backend now -- see
    # app/clients/rabbitmq_publisher.py. backend_internal_base_url above is kept only for the
    # one remaining read, GET /api/sync-status, used by the startup freshness check.
    rabbitmq_url: str = "amqp://guest:guest@localhost:5672/"
    rabbitmq_sync_queue: str = "weather.sync"
    rabbitmq_sync_failure_queue: str = "weather.sync_failure"
    rabbitmq_dead_letter_exchange: str = "weather.dlx"

    weather_location_name: str = "Ivano-Frankivsk"
    weather_country: str = "Ukraine"
    weather_latitude: float = 48.9226
    weather_longitude: float = 24.7111
    weather_timezone: str = "Europe/Kyiv"

    weather_past_days: int = 10
    weather_forecast_days: int = 10

    weather_sync_enabled: bool = True
    weather_sync_interval_minutes: int = 60
    weather_sync_on_startup: bool = True
    weather_sync_startup_freshness_minutes: int = 60

    fetcher_port: int = 8002


@lru_cache
def get_settings() -> Settings:
    return Settings()
