from datetime import timedelta

import pytest

from app.exceptions import PersistenceError
from app.models import CurrentWeather, DailyForecast, DailyWeather, HourlyWeather, Location, WeatherSync
from app.schemas.persistence import WeatherUpsertRequest
from app.schemas.sync import SyncFailureRequest
from app.services import persistence_service
from tests.factories import build_daily, build_daily_forecast, build_hourly_day, build_sync, build_upsert_payload, kyiv_today


def _counts(db_session):
    return {
        "locations": db_session.query(Location).count(),
        "current_weather": db_session.query(CurrentWeather).count(),
        "daily_weather": db_session.query(DailyWeather).count(),
        "hourly_weather": db_session.query(HourlyWeather).count(),
        "weather_syncs": db_session.query(WeatherSync).count(),
    }


def _upsert(db_session, **kwargs):
    payload = WeatherUpsertRequest(**build_upsert_payload(**kwargs))
    return persistence_service.upsert_weather(db_session, payload)


def test_upsert_first_insert_creates_location_current_daily_hourly_and_sync(db_session):
    response = _upsert(db_session)

    assert response.location.name == "Ivano-Frankivsk"
    assert response.current.temperature is not None
    assert len(response.daily) == 1
    assert len(response.hourly) == 24
    assert response.latest_success_sync.status == "success"
    assert response.latest_attempt_sync.status == "success"

    assert _counts(db_session) == {
        "locations": 1,
        "current_weather": 1,
        "daily_weather": 1,
        "hourly_weather": 24,
        "weather_syncs": 1,
    }


def test_repeated_upsert_reuses_location_no_duplicate(db_session):
    _upsert(db_session)
    _upsert(db_session, location={"name": "Ivano-Frankivsk (renamed)"})

    assert db_session.query(Location).count() == 1
    # find-or-create on (lat, lon) also refreshes display fields like name in place
    assert db_session.query(Location).one().name == "Ivano-Frankivsk (renamed)"


def test_repeated_upsert_updates_current_weather_in_place(db_session):
    _upsert(db_session, current={"temperature": 20.0})
    _upsert(db_session, current={"temperature": 21.5})

    assert db_session.query(CurrentWeather).count() == 1
    assert db_session.query(CurrentWeather).one().temperature == 21.5


def test_repeated_upsert_same_date_upserts_daily_no_duplicate(db_session):
    today = kyiv_today()
    _upsert(db_session, daily=[build_daily(today, temperature_max=25.0)])
    _upsert(db_session, daily=[build_daily(today, temperature_max=28.0)])

    assert db_session.query(DailyWeather).count() == 1
    assert db_session.query(DailyWeather).one().temperature_max == 28.0


def test_repeated_upsert_same_hour_upserts_hourly_no_duplicate(db_session):
    _upsert(db_session, hourly=build_hourly_day())
    _upsert(db_session, hourly=build_hourly_day())

    assert db_session.query(HourlyWeather).count() == 24


def test_upsert_preserves_historical_dates_across_repeated_syncs(db_session):
    """Repeated syncs across different days must accumulate daily rows, never overwrite each
    other -- the guarantee docs/architecture.md §8 documents for daily_weather."""
    today = kyiv_today()
    for offset in range(11):
        day = today.fromordinal(today.toordinal() - offset)
        _upsert(db_session, daily=[build_daily(day, temperature_max=float(20 + offset))], hourly=[])

    assert db_session.query(DailyWeather).count() == 11


def test_upsert_daily_forecast_creates_rows(db_session):
    today = kyiv_today()
    forecast = [build_daily_forecast(today + timedelta(days=offset)) for offset in range(1, 4)]
    _upsert(db_session, daily_forecast=forecast)

    assert db_session.query(DailyForecast).count() == 3


def test_upsert_daily_forecast_replaces_rather_than_accumulates(db_session):
    """Unlike daily_weather, a forecast for a given date is expected to be superseded, not
    preserved -- a later, more accurate prediction fully replaces the earlier one."""
    target_date = kyiv_today() + timedelta(days=5)
    _upsert(db_session, daily_forecast=[build_daily_forecast(target_date, temperature_max=22.0)])
    _upsert(db_session, daily_forecast=[build_daily_forecast(target_date, temperature_max=27.5)])

    assert db_session.query(DailyForecast).count() == 1
    assert db_session.query(DailyForecast).one().temperature_max == 27.5


def test_upsert_daily_forecast_does_not_affect_daily_weather(db_session):
    """Observed and forecast rows are separate tables with separate accumulation rules --
    upserting one must never touch the other."""
    today = kyiv_today()
    _upsert(
        db_session,
        daily=[build_daily(today)],
        daily_forecast=[build_daily_forecast(today + timedelta(days=1))],
    )

    assert db_session.query(DailyWeather).count() == 1
    assert db_session.query(DailyForecast).count() == 1


def test_upsert_computes_average_temperature_from_hourly_data(db_session):
    """Builds hourly rows with an explicit `+03:00` offset -- matching exactly what the real
    Fetcher's normalizer produces (a `ZoneInfo("Europe/Kyiv")`-aware datetime, `.isoformat()`'d)
    -- rather than the shared `build_hourly_day` fixture, which converts to UTC for its
    original purpose (exercising the old UTC-range query) and would make exact-average
    assertions here fragile without actually being wrong for what it originally tests."""
    today = kyiv_today()
    hourly = [
        {
            "weather_time": f"{today.isoformat()}T{h:02d}:00:00+03:00",
            "temperature": 10.0 + h,
            "apparent_temperature": 9.0 + h,
            "humidity": 50.0,
            "precipitation_probability": 0.0,
            "precipitation": 0.0,
            "weather_code": 1,
            "cloud_cover": 20.0,
            "visibility": 10000.0,
            "wind_speed": 5.0,
            "wind_direction": 180.0,
        }
        for h in range(24)
    ]
    _upsert(db_session, daily=[build_daily(today)], hourly=hourly)

    row = db_session.query(DailyWeather).filter_by(weather_date=today).one()
    expected_avg_temp = sum(10.0 + h for h in range(24)) / 24
    assert row.average_temperature == pytest.approx(expected_avg_temp)
    assert row.average_temperature_method == "hourly"
    assert row.average_humidity == pytest.approx(50.0)
    assert row.average_wind_speed == pytest.approx(5.0)
    assert row.average_cloud_cover == pytest.approx(20.0)


def test_upsert_falls_back_to_min_max_average_when_no_hourly_data(db_session):
    today = kyiv_today()
    _upsert(db_session, daily=[build_daily(today, temperature_min=10.0, temperature_max=20.0)], hourly=[])

    row = db_session.query(DailyWeather).filter_by(weather_date=today).one()
    assert row.average_temperature == 15.0
    assert row.average_temperature_method == "min_max_fallback"
    # no fallback source exists for these -- stay NULL, never a fabricated value
    assert row.average_humidity is None
    assert row.average_wind_speed is None
    assert row.average_cloud_cover is None


def test_upsert_records_open_meteo_call_metadata_on_success(db_session):
    _upsert(
        db_session,
        sync=build_sync(
            open_meteo_request_url="https://api.open-meteo.com/v1/forecast?x=1",
            open_meteo_status_code=200,
            open_meteo_duration_ms=417,
        ),
    )

    sync = db_session.query(WeatherSync).one()
    assert sync.status == "success"
    assert sync.open_meteo_request_url == "https://api.open-meteo.com/v1/forecast?x=1"
    assert sync.open_meteo_status_code == 200
    assert sync.open_meteo_duration_ms == 417
    assert sync.records_received == 1 + 1 + 24  # current + 1 daily row + 24 hourly rows


def test_record_sync_failure_does_not_touch_weather_tables(db_session):
    payload = SyncFailureRequest(
        location={"name": "Ivano-Frankivsk", "country": "Ukraine", "latitude": 48.9226, "longitude": 24.7111, "timezone": "Europe/Kyiv"},
        trigger_type="scheduler",
        started_at="2026-07-20T10:00:00+00:00",
        completed_at="2026-07-20T10:00:10+00:00",
        error_message="Open-Meteo request timed out after 10s",
        open_meteo_request_url="https://api.open-meteo.com/v1/forecast?x=1",
        open_meteo_status_code=None,
        open_meteo_duration_ms=10000,
    )

    sync = persistence_service.record_sync_failure(db_session, payload)

    assert sync.status == "failed"
    assert sync.error_message == "Open-Meteo request timed out after 10s"
    assert sync.open_meteo_status_code is None
    assert sync.open_meteo_duration_ms == 10000

    counts = _counts(db_session)
    assert counts["current_weather"] == 0
    assert counts["daily_weather"] == 0
    assert counts["hourly_weather"] == 0
    assert counts["weather_syncs"] == 1
    assert counts["locations"] == 1  # find-or-create still runs, so the failure can be attributed to a location


def test_record_sync_failure_does_not_require_prior_location(db_session):
    """The very first sync attempt ever can fail before any location exists -- must not crash."""
    assert db_session.query(Location).count() == 0

    payload = SyncFailureRequest(
        location={"name": "Ivano-Frankivsk", "country": "Ukraine", "latitude": 48.9226, "longitude": 24.7111, "timezone": "Europe/Kyiv"},
        trigger_type="startup",
        started_at="2026-07-20T09:00:00+00:00",
        completed_at=None,
        error_message="Connection refused",
    )

    persistence_service.record_sync_failure(db_session, payload)

    assert db_session.query(Location).count() == 1


def test_upsert_rollback_preserves_prior_data_on_failure(db_session):
    _upsert(db_session, current={"temperature": 31.5})

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
    # Two rows sharing the same (location_id, weather_time) key in one request -> Postgres
    # rejects it mid-statement ("ON CONFLICT DO UPDATE command cannot affect row a second
    # time"), which must roll back the whole transaction, not just the hourly writes.
    with pytest.raises(PersistenceError):
        _upsert(
            db_session,
            current={"temperature": 999.0},
            hourly=[broken_hourly_row, {**broken_hourly_row, "temperature": 2.0}],
        )

    db_session.expire_all()  # upsert_weather already rolled back; this just drops stale identity-map state
    current = db_session.query(CurrentWeather).one()
    assert current.temperature == 31.5  # untouched by the failed attempt

    # the failed attempt must not have left a dangling sync row either -- it never got that far
    assert db_session.query(WeatherSync).count() == 1
    assert db_session.query(WeatherSync).one().status == "success"


def test_get_latest_with_empty_database_returns_no_data_shape(db_session):
    from app.services.weather_query_service import build_latest_response

    response = build_latest_response(db_session)

    assert response.location is None
    assert response.current is None
    assert response.daily == []
    assert response.hourly == []
    assert response.latest_success_sync is None
