from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

KYIV = ZoneInfo("Europe/Kyiv")

IVANO_FRANKIVSK = {
    "name": "Ivano-Frankivsk",
    "country": "Ukraine",
    "latitude": 48.9226,
    "longitude": 24.7111,
    "timezone": "Europe/Kyiv",
}


def kyiv_today():
    return datetime.now(KYIV).date()


def build_current(**overrides):
    base = {
        "observed_at": datetime.now(timezone.utc).isoformat(),
        "temperature": 24.5,
        "apparent_temperature": 25.1,
        "humidity": 61.0,
        "precipitation": 0.0,
        "weather_code": 1,
        "cloud_cover": 20.0,
        "wind_speed": 8.5,
        "wind_direction": 220.0,
        "surface_pressure": 1008.0,
        "is_day": True,
    }
    base.update(overrides)
    return base


def build_daily(day=None, **overrides):
    day = day or kyiv_today()
    base = {
        "weather_date": day.isoformat(),
        "weather_code": 1,
        "temperature_max": 25.0,
        "temperature_min": 15.0,
        "apparent_temperature_max": 26.0,
        "apparent_temperature_min": 14.0,
        "sunrise": datetime.now(timezone.utc).isoformat(),
        "sunset": datetime.now(timezone.utc).isoformat(),
        "precipitation_sum": 0.0,
        "rain_sum": 0.0,
        "snowfall_sum": 0.0,
        "precipitation_hours": 0.0,
        "wind_speed_max": 10.0,
        "wind_gusts_max": 15.0,
    }
    base.update(overrides)
    return base


def build_hourly_day(day=None):
    """24 hourly rows spanning one Europe/Kyiv calendar day, correctly converted to UTC instants."""
    day = day or kyiv_today()
    rows = []
    for h in range(24):
        t = datetime.combine(day, datetime.min.time(), tzinfo=KYIV) + timedelta(hours=h)
        rows.append(
            {
                "weather_time": t.astimezone(timezone.utc).isoformat(),
                "temperature": 20.0 + h * 0.1,
                "apparent_temperature": 19.5 + h * 0.1,
                "humidity": 55.0,
                "precipitation_probability": 5.0,
                "precipitation": 0.0,
                "weather_code": 1,
                "cloud_cover": 10.0,
                "visibility": 10000.0,
                "wind_speed": 5.0,
                "wind_direction": 180.0,
            }
        )
    return rows


def build_daily_forecast(day=None, **overrides):
    day = day or (kyiv_today() + timedelta(days=1))
    base = {
        "weather_date": day.isoformat(),
        "weather_code": 1,
        "temperature_min": 15.0,
        "temperature_max": 25.0,
        "apparent_temperature_min": 14.0,
        "apparent_temperature_max": 26.0,
        "precipitation_probability_max": 20.0,
    }
    base.update(overrides)
    return base


def build_sync(**overrides):
    base = {
        "trigger_type": "internal_endpoint",
        "started_at": datetime.now(timezone.utc).isoformat(),
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "open_meteo_request_url": "https://api.open-meteo.com/v1/forecast?latitude=48.9226&longitude=24.7111",
        "open_meteo_status_code": 200,
        "open_meteo_duration_ms": 250,
    }
    base.update(overrides)
    return base


def build_upsert_payload(
    *, location=None, current=None, daily=None, daily_forecast=None, hourly=None, sync=None, source="Open-Meteo"
):
    return {
        "location": {**IVANO_FRANKIVSK, **(location or {})},
        "current": build_current(**(current or {})),
        "daily": daily if daily is not None else [build_daily()],
        "daily_forecast": daily_forecast if daily_forecast is not None else [],
        "hourly": hourly if hourly is not None else build_hourly_day(),
        "source": source,
        "sync": build_sync(**(sync or {})),
    }
