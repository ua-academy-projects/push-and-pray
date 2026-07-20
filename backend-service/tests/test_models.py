from datetime import UTC, datetime
from decimal import Decimal

from app.models import Rate


def test_decimals_are_serialized_as_strings():
    rate = Rate(
        instrument_id="fiat:USD:UAH", kind="fiat", base="USD", quote="UAH", name="USD/UAH",
        price=Decimal("41.123400"), source="frankfurter", source_timestamp=datetime.now(UTC), requested_at=datetime.now(UTC),
    )
    assert rate.model_dump(mode="json")["price"] == "41.123400"
