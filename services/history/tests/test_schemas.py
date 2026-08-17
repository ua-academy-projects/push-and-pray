from datetime import UTC, datetime
from decimal import Decimal

import pytest
from pydantic import ValidationError

from history_service.schemas import ObservationBatch, ObservationCreate, ObservationEvent


def valid_observation() -> dict:
    return {
        "instrument_code": "WTI_USD_BBL",
        "instrument_name": "WTI Crude Oil Spot Price",
        "category": "crude_oil",
        "price": Decimal("68.42"),
        "currency": "USD",
        "unit": "USD per barrel",
        "source": "OilPriceAPI",
        "source_series_id": "WTI_USD",
        "source_period": "2026-07-27",
        "source_observed_at": datetime(2026, 7, 27, 5, 59, tzinfo=UTC),
        "scheduled_for": datetime(2026, 7, 27, 6, tzinfo=UTC),
        "fetched_at": datetime(2026, 7, 27, 6, 0, 2, tzinfo=UTC),
        "source_url": "https://api.oilpriceapi.com/v1/prices/latest",
        "raw_data": {"code": "WTI_USD", "price": "68.42"},
    }


def test_valid_observation_batch() -> None:
    batch = ObservationBatch(observations=[valid_observation()])
    assert batch.observations[0].price == Decimal("68.42")


def test_valid_versioned_event() -> None:
    event = ObservationEvent(schema_version=1, observations=[valid_observation()])
    assert event.schema_version == 1


def test_unknown_schema_version_is_rejected() -> None:
    with pytest.raises(ValidationError):
        ObservationEvent(schema_version=2, observations=[valid_observation()])


def test_timestamp_must_be_timezone_aware() -> None:
    payload = valid_observation()
    payload["scheduled_for"] = datetime(2026, 7, 22, 6)
    with pytest.raises(ValidationError):
        ObservationCreate.model_validate(payload)


def test_source_timestamp_must_be_timezone_aware() -> None:
    payload = valid_observation()
    payload["source_observed_at"] = datetime(2026, 7, 21, 20, 30)
    with pytest.raises(ValidationError):
        ObservationCreate.model_validate(payload)


def test_price_must_be_positive() -> None:
    payload = valid_observation()
    payload["price"] = 0
    with pytest.raises(ValidationError):
        ObservationCreate.model_validate(payload)
