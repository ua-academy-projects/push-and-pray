from copy import deepcopy
from datetime import UTC, datetime
from typing import Any

import pytest
from history_service.schemas import BlacklistSnapshotMessage
from pydantic import ValidationError

DELIVERY_ID = "662ecba0-8918-433d-bc75-b14de17851f1"
CORRELATION_ID = "6f5aa064-43e8-4dbb-a544-d60b68af5cbd"
NOW = datetime(2026, 7, 23, 9, 0, tzinfo=UTC)


def message() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "message_type": "blacklist.snapshot.complete",
        "delivery_id": DELIVERY_ID,
        "correlation_id": CORRELATION_ID,
        "producer": "aegis-provider-service",
        "provider": "AbuseIPDB",
        "created_at": NOW.isoformat(),
        "snapshot": {
            "provider": "AbuseIPDB",
            "generated_at": NOW.isoformat(),
            "fetched_at": NOW.isoformat(),
            "request": {"confidence_minimum": 90, "limit": 1000},
            "rate_limit": {"limit": 5, "remaining": 4},
            "items": [
                {
                    "ip_address": "2001:4860:4860::8888",
                    "ip_version": 6,
                    "abuse_confidence_score": 100,
                    "country_code": "US",
                    "last_reported_at": NOW.isoformat(),
                }
            ],
        },
    }


def test_valid_complete_snapshot_message_parses() -> None:
    parsed = BlacklistSnapshotMessage.model_validate(message())

    assert str(parsed.delivery_id) == DELIVERY_ID
    assert str(parsed.correlation_id) == CORRELATION_ID
    assert parsed.snapshot.items[0].ip_address == "2001:4860:4860::8888"


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("schema_version", 2),
        ("message_type", "blacklist.snapshot.partial"),
        ("correlation_id", "not-a-uuid"),
    ],
)
def test_invalid_envelope_value_is_rejected(field: str, value: object) -> None:
    payload = message()
    payload[field] = value

    with pytest.raises(ValidationError):
        BlacklistSnapshotMessage.model_validate(payload)


def test_naive_created_at_is_rejected() -> None:
    payload = message()
    payload["created_at"] = "2026-07-23T09:00:00"

    with pytest.raises(ValidationError, match="timezone"):
        BlacklistSnapshotMessage.model_validate(payload)


@pytest.mark.parametrize("snapshot", [None, {}, {"provider": "AbuseIPDB"}])
def test_malformed_snapshot_is_rejected(snapshot: object) -> None:
    payload = deepcopy(message())
    payload["snapshot"] = snapshot

    with pytest.raises(ValidationError):
        BlacklistSnapshotMessage.model_validate(payload)


def test_missing_snapshot_is_rejected() -> None:
    payload = message()
    del payload["snapshot"]

    with pytest.raises(ValidationError):
        BlacklistSnapshotMessage.model_validate(payload)
