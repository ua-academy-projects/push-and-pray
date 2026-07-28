import json

import pytest
from pydantic import ValidationError

from app.broker.consumer import handle_sync_failure_message, handle_weather_sync_message
from app.exceptions import PersistenceError
from tests.factories import build_upsert_payload


def test_handle_weather_sync_message_upserts_from_a_queue_body(db_session):
    body = json.dumps(build_upsert_payload(daily_forecast=[{
        "weather_date": "2026-07-29",
        "weather_code": 1,
        "temperature_min": 15.0,
        "temperature_max": 25.0,
        "apparent_temperature_min": 14.0,
        "apparent_temperature_max": 26.0,
        "precipitation_probability_max": 20.0,
    }])).encode()

    handle_weather_sync_message(body, db_session)

    from app.models import CurrentWeather, DailyForecast

    assert db_session.query(CurrentWeather).count() == 1
    assert db_session.query(DailyForecast).count() == 1


def test_handle_weather_sync_message_rejects_invalid_body_without_touching_db(db_session):
    body = json.dumps({"location": {"name": "Ivano-Frankivsk"}}).encode()

    with pytest.raises(ValidationError):
        handle_weather_sync_message(body, db_session)

    from app.models import CurrentWeather

    assert db_session.query(CurrentWeather).count() == 0


def test_handle_weather_sync_message_rollback_preserves_prior_data_on_failure(db_session):
    good_body = json.dumps(build_upsert_payload(current={"temperature": 31.5})).encode()
    handle_weather_sync_message(good_body, db_session)

    same_time = "2026-07-20T05:00:00+00:00"
    broken_hourly_row = {
        "weather_time": same_time,
        "temperature": 1.0,
        "apparent_temperature": 1.0,
        "humidity": 50.0,
        "precipitation_probability": 0.0,
        "precipitation": 0.0,
        "weather_code": 1,
        "cloud_cover": 0.0,
        "visibility": 10000.0,
        "wind_speed": 1.0,
        "wind_direction": 1.0,
    }
    broken_body = json.dumps(
        build_upsert_payload(
            current={"temperature": 999.0},
            hourly=[broken_hourly_row, {**broken_hourly_row, "temperature": 2.0}],
        )
    ).encode()

    with pytest.raises(PersistenceError):
        handle_weather_sync_message(broken_body, db_session)

    from app.models import CurrentWeather

    db_session.expire_all()
    assert db_session.query(CurrentWeather).one().temperature == 31.5


def test_handle_sync_failure_message_records_failure_without_touching_existing_data(db_session):
    good_body = json.dumps(build_upsert_payload(current={"temperature": 20.0})).encode()
    handle_weather_sync_message(good_body, db_session)

    failure_body = json.dumps(
        {
            "location": {
                "name": "Ivano-Frankivsk",
                "country": "Ukraine",
                "latitude": 48.9226,
                "longitude": 24.7111,
                "timezone": "Europe/Kyiv",
            },
            "trigger_type": "scheduler",
            "started_at": "2026-07-20T10:00:00+00:00",
            "completed_at": "2026-07-20T10:00:10+00:00",
            "error_message": "Open-Meteo request timed out after 10s",
            "open_meteo_status_code": None,
            "open_meteo_duration_ms": 10000,
        }
    ).encode()

    handle_sync_failure_message(failure_body, db_session)

    from app.models import CurrentWeather, WeatherSync

    db_session.expire_all()
    assert db_session.query(CurrentWeather).one().temperature == 20.0  # untouched
    assert db_session.query(WeatherSync).count() == 2  # the earlier success + this failure
