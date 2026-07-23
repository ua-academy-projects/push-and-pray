from datetime import date, timedelta

from app.schemas.persistence import WeatherUpsertRequest
from app.services import persistence_service, statistics_service
from tests.factories import build_daily, build_hourly_day, build_upsert_payload, kyiv_today


def _upsert(db_session, **kwargs):
    payload = WeatherUpsertRequest(**build_upsert_payload(**kwargs))
    return persistence_service.upsert_weather(db_session, payload)


def test_get_daily_statistics_returns_computed_fields(db_session):
    today = kyiv_today()
    _upsert(
        db_session,
        daily=[build_daily(today, weather_code=61, temperature_max=22.0, temperature_min=12.0)],
        hourly=build_hourly_day(today),
    )

    result = statistics_service.get_daily_statistics(db_session, today)

    assert result is not None
    assert result.date == today
    assert result.average_temperature_method == "hourly"  # hourly rows were provided
    assert result.minimum_temperature == 12.0
    assert result.maximum_temperature == 22.0
    assert result.dominant_weather_condition == "rain"


def test_get_daily_statistics_missing_date_returns_none(db_session):
    assert statistics_service.get_daily_statistics(db_session, date(2020, 1, 1)) is None


def test_get_period_statistics_uses_all_matching_dates_not_capped_at_ten(db_session):
    today = kyiv_today()
    for offset in range(15):
        day = today - timedelta(days=offset)
        _upsert(db_session, daily=[build_daily(day)], hourly=[])

    result = statistics_service.get_period_statistics(db_session, today - timedelta(days=14), today)

    assert result.available_days == 15


def test_get_period_statistics_counts_conditions_and_extremes(db_session):
    today = kyiv_today()
    base_day = today - timedelta(days=3)
    _upsert(db_session, daily=[build_daily(base_day, weather_code=0, temperature_max=30.0, temperature_min=20.0)], hourly=[])
    _upsert(db_session, daily=[build_daily(base_day + timedelta(days=1), weather_code=3, temperature_max=18.0, temperature_min=8.0)], hourly=[])
    _upsert(db_session, daily=[build_daily(base_day + timedelta(days=2), weather_code=61, temperature_max=15.0, temperature_min=5.0)], hourly=[])
    _upsert(db_session, daily=[build_daily(base_day + timedelta(days=3), weather_code=71, temperature_max=1.0, temperature_min=-5.0)], hourly=[])

    result = statistics_service.get_period_statistics(db_session, base_day, today)

    assert result.clear_days == 1
    assert result.cloudy_days == 1
    assert result.rainy_days == 1
    assert result.snowy_days == 1
    assert result.warmest_day == base_day  # highest temperature_max (30.0)
    assert result.coldest_day == base_day + timedelta(days=3)  # lowest temperature_min (-5.0)
    assert result.highest_temperature == 30.0
    assert result.lowest_temperature == -5.0


def test_get_period_statistics_empty_range_is_not_an_error(db_session):
    result = statistics_service.get_period_statistics(db_session, date(2020, 1, 1), date(2020, 1, 5))

    assert result.available_days == 0
    assert result.average_temperature is None
    assert result.warmest_day is None
    assert result.rainy_days == 0


def test_get_all_time_statistics_spans_every_stored_date(db_session):
    today = kyiv_today()
    for offset in range(40):
        day = today - timedelta(days=offset)
        _upsert(db_session, daily=[build_daily(day)], hourly=[])

    result = statistics_service.get_all_time_statistics(db_session)

    assert result.available_days == 40
