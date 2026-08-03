from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file="../.env", extra="ignore")

    api_fetcher_host: str = "127.0.0.1"
    api_fetcher_port: int = 8000
    internal_api_token: str = "change-me"
    rabbitmq_enabled: bool = True
    rabbitmq_url: str = "amqp://guest:guest@127.0.0.1:5672/"
    rabbitmq_events_exchange: str = "rates.events"
    rabbitmq_observations_queue: str = "rates.observations"
    rabbitmq_observation_routing_key: str = "observation.collected"
    rabbitmq_commands_exchange: str = "rates.commands"
    rabbitmq_commands_queue: str = "rates.fetch.commands"
    rabbitmq_command_routing_key: str = "backfill.requested"
    coingecko_base_url: str = "https://api.coingecko.com/api/v3"
    coingecko_api_key: str = ""
    frankfurter_base_url: str = "https://api.frankfurter.dev/v2"
    collector_enabled: bool = True
    collector_interval_seconds: int = 300
    log_level: str = "INFO"


@lru_cache
def get_settings() -> Settings:
    return Settings()
