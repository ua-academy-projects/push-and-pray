from datetime import date, datetime, timezone

import pytest
from sqlalchemy.exc import IntegrityError

from app.models import CurrentWeather, DailyForecast, DailyWeather, HourlyWeather, Location, SyncStatus, TriggerType, WeatherSync

IVANO_FRANKIVSK = dict(
    name="Ivano-Frankivsk",
    country="Ukraine",
    latitude=48.9226,
    longitude=24.7111,
    timezone="Europe/Kyiv",
)


def _now():
    return datetime.now(timezone.utc)


def make_location(session, **overrides):
    location = Location(**{**IVANO_FRANKIVSK, **overrides})
    session.add(location)
    session.commit()
    session.refresh(location)
    return location


def test_location_can_be_created_and_queried(db_session):
    location = make_location(db_session)

    fetched = db_session.query(Location).filter_by(id=location.id).one()

    assert fetched.name == "Ivano-Frankivsk"
    assert fetched.country == "Ukraine"
    assert fetched.latitude == pytest.approx(48.9226)
    assert fetched.longitude == pytest.approx(24.7111)
    assert fetched.timezone == "Europe/Kyiv"
    assert fetched.created_at is not None
    assert fetched.updated_at is not None


def test_location_unique_on_lat_lon_rejects_duplicate(db_session):
    make_location(db_session)

    duplicate = Location(**{**IVANO_FRANKIVSK, "name": "Ivano-Frankivsk (duplicate)"})
    db_session.add(duplicate)

    with pytest.raises(IntegrityError):
        db_session.commit()


def test_current_weather_unique_on_location_rejects_second_row(db_session):
    location = make_location(db_session)
    common = dict(
        location_id=location.id,
        observed_at=_now(),
        temperature=20.0,
        apparent_temperature=19.5,
        humidity=55.0,
        precipitation=0.0,
        weather_code=1,
        cloud_cover=10.0,
        wind_speed=5.0,
        wind_direction=180.0,
        surface_pressure=1010.0,
        is_day=True,
        source="Open-Meteo",
        synchronized_at=_now(),
    )

    db_session.add(CurrentWeather(**common))
    db_session.commit()

    db_session.add(CurrentWeather(**common))
    with pytest.raises(IntegrityError):
        db_session.commit()


def test_daily_weather_unique_on_location_and_date_rejects_duplicate(db_session):
    location = make_location(db_session)
    common = dict(
        location_id=location.id,
        weather_date=date(2026, 7, 20),
        weather_code=1,
        temperature_max=25.0,
        temperature_min=15.0,
        apparent_temperature_max=26.0,
        apparent_temperature_min=14.0,
        sunrise=_now(),
        sunset=_now(),
        precipitation_sum=0.0,
        rain_sum=0.0,
        snowfall_sum=0.0,
        precipitation_hours=0.0,
        wind_speed_max=10.0,
        wind_gusts_max=15.0,
        average_temperature=20.0,
        average_temperature_method="min_max_fallback",
        average_apparent_temperature=20.0,
        source="Open-Meteo",
        synchronized_at=_now(),
    )

    db_session.add(DailyWeather(**common))
    db_session.commit()

    db_session.add(DailyWeather(**common))
    with pytest.raises(IntegrityError):
        db_session.commit()


def test_daily_weather_allows_same_location_different_dates(db_session):
    location = make_location(db_session)
    base = dict(
        location_id=location.id,
        weather_code=1,
        temperature_max=25.0,
        temperature_min=15.0,
        apparent_temperature_max=26.0,
        apparent_temperature_min=14.0,
        sunrise=_now(),
        sunset=_now(),
        precipitation_sum=0.0,
        rain_sum=0.0,
        snowfall_sum=0.0,
        precipitation_hours=0.0,
        wind_speed_max=10.0,
        wind_gusts_max=15.0,
        average_temperature=20.0,
        average_temperature_method="min_max_fallback",
        average_apparent_temperature=20.0,
        source="Open-Meteo",
        synchronized_at=_now(),
    )

    db_session.add(DailyWeather(weather_date=date(2026, 7, 19), **base))
    db_session.add(DailyWeather(weather_date=date(2026, 7, 20), **base))
    db_session.commit()

    assert db_session.query(DailyWeather).filter_by(location_id=location.id).count() == 2


def test_daily_forecast_unique_on_location_and_date_rejects_duplicate(db_session):
    location = make_location(db_session)
    common = dict(
        location_id=location.id,
        weather_date=date(2026, 7, 25),
        weather_code=1,
        temperature_min=15.0,
        temperature_max=25.0,
        apparent_temperature_min=14.0,
        apparent_temperature_max=26.0,
        precipitation_probability_max=20.0,
        source="Open-Meteo",
        synchronized_at=_now(),
    )

    db_session.add(DailyForecast(**common))
    db_session.commit()

    db_session.add(DailyForecast(**common))
    with pytest.raises(IntegrityError):
        db_session.commit()


def test_hourly_weather_unique_on_location_and_time_rejects_duplicate(db_session):
    location = make_location(db_session)
    common = dict(
        location_id=location.id,
        weather_time=datetime(2026, 7, 20, 12, 0, tzinfo=timezone.utc),
        temperature=22.0,
        apparent_temperature=21.5,
        humidity=50.0,
        precipitation_probability=10.0,
        precipitation=0.0,
        weather_code=1,
        cloud_cover=5.0,
        visibility=10000.0,
        wind_speed=4.0,
        wind_direction=200.0,
        synchronized_at=_now(),
    )

    db_session.add(HourlyWeather(**common))
    db_session.commit()

    db_session.add(HourlyWeather(**common))
    with pytest.raises(IntegrityError):
        db_session.commit()


def test_weather_sync_stores_lowercase_enum_values(db_session):
    location = make_location(db_session)

    sync = WeatherSync(
        location_id=location.id,
        started_at=_now(),
        completed_at=_now(),
        status=SyncStatus.SUCCESS,
        source="Open-Meteo",
        trigger_type=TriggerType.SCHEDULER,
        open_meteo_request_url="https://api.open-meteo.com/v1/forecast?latitude=48.9226&longitude=24.7111",
        open_meteo_status_code=200,
        open_meteo_duration_ms=350,
        records_received=1,
        daily_records_received=11,
        hourly_records_received=24,
    )
    db_session.add(sync)
    db_session.commit()

    raw_status, raw_trigger = db_session.execute(
        db_session.query(WeatherSync.status, WeatherSync.trigger_type).filter_by(id=sync.id).statement
    ).one()

    assert raw_status == SyncStatus.SUCCESS
    assert raw_trigger == TriggerType.SCHEDULER

    # The whole point of using values_callable: the column must contain the lowercase
    # *value* ("success"), not the Python enum member name ("SUCCESS"), because the
    # spec's allowed statuses are lowercase strings.
    stored_value = db_session.connection().exec_driver_sql(
        "SELECT status, trigger_type FROM weather_syncs WHERE id = %s", (sync.id,)
    ).one()
    assert stored_value.status == "success"
    assert stored_value.trigger_type == "scheduler"


def test_weather_sync_allows_multiple_attempts_for_same_location(db_session):
    location = make_location(db_session)

    for _ in range(3):
        db_session.add(
            WeatherSync(
                location_id=location.id,
                started_at=_now(),
                status=SyncStatus.FAILED,
                source="Open-Meteo",
                trigger_type=TriggerType.INTERNAL_ENDPOINT,
                error_message="Open-Meteo timed out",
            )
        )
    db_session.commit()

    assert db_session.query(WeatherSync).filter_by(location_id=location.id).count() == 3
