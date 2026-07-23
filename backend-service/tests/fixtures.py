from app.config import Settings


def make_settings(**overrides) -> Settings:
    base = dict(
        open_meteo_base_url="https://api.open-meteo.com/v1/forecast",
        history_service_base_url="http://history-service.test",
        http_timeout_seconds=5.0,
        weather_location_name="Ivano-Frankivsk",
        weather_country="Ukraine",
        weather_latitude=48.9226,
        weather_longitude=24.7111,
        weather_timezone="Europe/Kyiv",
        weather_sync_enabled=True,
        weather_sync_interval_minutes=60,
        weather_sync_on_startup=True,
        weather_sync_startup_freshness_minutes=60,
        weather_data_max_age_minutes=90,
    )
    base.update(overrides)
    return Settings(**base)


def build_open_meteo_response(hours: int = 24, days: int = 11) -> dict:
    """Shaped like a real Open-Meteo response for timezone=Europe/Kyiv: local civil
    timestamps with NO utc offset suffix (e.g. '2026-07-20T00:00'), which is exactly the
    quirk app/normalization/open_meteo_normalizer.py has to handle correctly."""
    hourly_time = [f"2026-07-20T{h:02d}:00" for h in range(hours)]
    daily_time = [f"2026-07-{20 - d:02d}" for d in range(days)]

    return {
        "latitude": 48.9226,
        "longitude": 24.7111,
        "timezone": "Europe/Kyiv",
        "current": {
            "time": "2026-07-20T14:00",
            "temperature_2m": 24.5,
            "apparent_temperature": 25.1,
            "relative_humidity_2m": 61,
            "precipitation": 0.0,
            "weather_code": 1,
            "cloud_cover": 20,
            "wind_speed_10m": 8.5,
            "wind_direction_10m": 220,
            "surface_pressure": 1008.0,
            "is_day": 1,
        },
        "hourly": {
            "time": hourly_time,
            "temperature_2m": [20.0 + i * 0.1 for i in range(hours)],
            "apparent_temperature": [19.5 + i * 0.1 for i in range(hours)],
            "relative_humidity_2m": [55 for _ in range(hours)],
            "precipitation_probability": [5 for _ in range(hours)],
            "precipitation": [0.0 for _ in range(hours)],
            "weather_code": [1 for _ in range(hours)],
            "cloud_cover": [10 for _ in range(hours)],
            "visibility": [10000.0 for _ in range(hours)],
            "wind_speed_10m": [5.0 for _ in range(hours)],
            "wind_direction_10m": [180 for _ in range(hours)],
        },
        "daily": {
            "time": daily_time,
            "weather_code": [1 for _ in range(days)],
            "temperature_2m_max": [25.0 for _ in range(days)],
            "temperature_2m_min": [15.0 for _ in range(days)],
            "apparent_temperature_max": [26.0 for _ in range(days)],
            "apparent_temperature_min": [14.0 for _ in range(days)],
            "sunrise": [f"2026-07-{20 - d:02d}T05:00" for d in range(days)],
            "sunset": [f"2026-07-{20 - d:02d}T21:00" for d in range(days)],
            "precipitation_sum": [0.0 for _ in range(days)],
            "rain_sum": [0.0 for _ in range(days)],
            "snowfall_sum": [0.0 for _ in range(days)],
            "precipitation_hours": [0.0 for _ in range(days)],
            "wind_speed_10m_max": [10.0 for _ in range(days)],
            "wind_gusts_10m_max": [15.0 for _ in range(days)],
        },
    }
