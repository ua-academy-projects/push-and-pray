from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Backend Service configuration, sourced entirely from environment variables."""

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False, extra="ignore")

    # No default -- unlike the rest of this config, DB credentials should never silently
    # fall back to a guessable local value (matches the History Service's original stance).
    database_url: str
    database_echo: bool = False
    database_pool_size: int = 5
    database_max_overflow: int = 10

    # Used exclusively by POST /api/sync/trigger (app/clients/fetcher_client.py) -- the one
    # deliberate exception to "Backend never calls Fetcher." Not used to poll or manage the
    # Fetcher generally. See docs/architecture.md §4.
    fetcher_service_base_url: str = "http://localhost:8002"
    http_timeout_seconds: float = 10.0

    weather_data_max_age_minutes: int = 90

    # --- RabbitMQ (async consumption of completed/failed syncs from the Fetcher) ---
    # Consumed by app/worker.py (a separate process from the API), not by the FastAPI app
    # itself -- see app/broker/consumer.py. The queue/exchange names must match the Fetcher's
    # RabbitMQPublisher exactly, since whichever side connects first declares them.
    rabbitmq_url: str = "amqp://guest:guest@localhost:5672/"
    rabbitmq_sync_queue: str = "weather.sync"
    rabbitmq_sync_failure_queue: str = "weather.sync_failure"
    rabbitmq_dead_letter_exchange: str = "weather.dlx"
    rabbitmq_prefetch_count: int = 10

    # --- Redis (UI session state, Sky Ivano's Redis integration) ---
    # Session storage only -- never business/weather data. See docs/architecture.md.
    redis_url: str = "redis://localhost:6379/0"
    redis_session_ttl_seconds: int = 60 * 60 * 24 * 30  # 30 days, refreshed on every read/write

    backend_port: int = 8000
    backend_cors_origins: str = "http://localhost:5173"

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.backend_cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
