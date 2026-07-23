from datetime import timedelta

from app.schemas.persistence import WeatherUpsertRequest
from app.services import chart_service, persistence_service
from tests.factories import build_daily, build_upsert_payload, kyiv_today


def _upsert(db_session, **kwargs):
    payload = WeatherUpsertRequest(**build_upsert_payload(**kwargs))
    return persistence_service.upsert_weather(db_session, payload)


def test_chart_data_is_ordered_ascending_by_date(db_session):
    today = kyiv_today()
    for offset in range(5):
        day = today - timedelta(days=offset)
        _upsert(db_session, daily=[build_daily(day)], hourly=[])

    result = chart_service.get_chart_data(db_session, today - timedelta(days=4), today)

    dates = [p.date for p in result.temperature]
    assert dates == sorted(dates)
    assert dates[0] == today - timedelta(days=4)
    assert dates[-1] == today


def test_chart_data_spans_more_than_ten_days(db_session):
    """The core acceptance criterion: charts must not be hardcoded to 10 days."""
    today = kyiv_today()
    for offset in range(35):
        day = today - timedelta(days=offset)
        _upsert(db_session, daily=[build_daily(day)], hourly=[])

    result = chart_service.get_chart_data(db_session, None, None)

    assert result.period.available_days == 35
    assert len(result.temperature) == 35
    assert len(result.humidity) == 35
    assert len(result.precipitation) == 35
    assert len(result.wind) == 35


def test_chart_data_points_carry_the_right_metrics(db_session):
    today = kyiv_today()
    _upsert(
        db_session,
        daily=[build_daily(today, temperature_max=25.0, temperature_min=15.0, precipitation_sum=4.2, wind_speed_max=18.0)],
        hourly=[],
    )

    result = chart_service.get_chart_data(db_session, today, today)

    assert result.temperature[0].maximum == 25.0
    assert result.temperature[0].minimum == 15.0
    assert result.precipitation[0].total == 4.2
    assert result.wind[0].maximum == 18.0


def test_chart_data_empty_range_returns_empty_series(db_session):
    result = chart_service.get_chart_data(db_session, None, None)

    assert result.period.available_days == 0
    assert result.temperature == []
    assert result.humidity == []
