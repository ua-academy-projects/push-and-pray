from app.config import Settings, get_settings


def make_settings(**overrides) -> Settings:
    """The Backend no longer calls Open-Meteo (Stage 2) -- this only needs the fields that
    still exist on app.config.Settings."""
    base = dict(
        database_url=get_settings().database_url,
        fetcher_service_base_url="http://fetcher-service.test",
        http_timeout_seconds=5.0,
        weather_data_max_age_minutes=90,
    )
    base.update(overrides)
    return Settings(**base)
