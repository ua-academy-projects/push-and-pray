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

    backend_port: int = 8000
    backend_cors_origins: str = "http://localhost:5173"

    @property
    def cors_origins_list(self) -> list[str]:
        return [origin.strip() for origin in self.backend_cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
