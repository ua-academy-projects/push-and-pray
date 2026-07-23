import copy

import pytest

from app.exceptions import OpenMeteoDataError
from app.normalization.open_meteo_normalizer import normalize_open_meteo_response
from tests.fixtures import build_open_meteo_response, make_settings


def test_normalize_produces_correct_internal_shape():
    data = build_open_meteo_response(hours=24, days=11)

    normalized = normalize_open_meteo_response(data, make_settings())

    assert normalized.location.name == "Ivano-Frankivsk"
    assert normalized.location.latitude == 48.9226
    assert normalized.current.temperature == 24.5
    assert normalized.current.is_day is True
    assert len(normalized.hourly) == 24
    assert len(normalized.daily) == 11
    assert normalized.source == "Open-Meteo"


def test_normalize_interprets_naive_timestamps_as_configured_timezone():
    """Open-Meteo returns '2026-07-20T14:00' with NO utc offset when timezone=Europe/Kyiv is
    requested -- normalization must attach that timezone, not UTC or the server's local tz."""
    data = build_open_meteo_response()

    normalized = normalize_open_meteo_response(data, make_settings())

    assert normalized.current.observed_at.tzinfo is not None
    assert str(normalized.current.observed_at.tzinfo) == "Europe/Kyiv"
    assert normalized.current.observed_at.hour == 14


def test_normalize_missing_top_level_block_raises():
    data = build_open_meteo_response()
    del data["hourly"]

    with pytest.raises(OpenMeteoDataError):
        normalize_open_meteo_response(data, make_settings())


def test_normalize_missing_required_field_raises():
    data = build_open_meteo_response()
    del data["current"]["temperature_2m"]

    with pytest.raises(OpenMeteoDataError):
        normalize_open_meteo_response(data, make_settings())


def test_normalize_inconsistent_hourly_array_lengths_raises():
    data = build_open_meteo_response(hours=24)
    data["hourly"]["temperature_2m"] = data["hourly"]["temperature_2m"][:23]  # one short

    with pytest.raises(OpenMeteoDataError):
        normalize_open_meteo_response(data, make_settings())


def test_normalize_inconsistent_daily_array_lengths_raises():
    data = build_open_meteo_response(days=11)
    data["daily"]["sunrise"] = data["daily"]["sunrise"][:5]

    with pytest.raises(OpenMeteoDataError):
        normalize_open_meteo_response(data, make_settings())


def test_normalize_empty_hourly_data_raises():
    data = build_open_meteo_response(hours=0)

    with pytest.raises(OpenMeteoDataError):
        normalize_open_meteo_response(data, make_settings())


def test_normalize_invalid_timestamp_raises():
    data = build_open_meteo_response()
    data["current"]["time"] = "not-a-timestamp"

    with pytest.raises(OpenMeteoDataError):
        normalize_open_meteo_response(data, make_settings())


def test_normalize_does_not_mutate_input():
    data = build_open_meteo_response()
    original = copy.deepcopy(data)

    normalize_open_meteo_response(data, make_settings())

    assert data == original
