import json
import logging
from datetime import UTC, datetime
from decimal import Decimal

import pytest

from app.main import JsonFormatter, observation_payload
from app.config import Settings
from app.models import Rate


class Publisher:
    def __init__(self, error: Exception | None = None):
        self.error = error
        self.messages = []

    async def publish(self, observation, request_id, idempotency_key):
        if self.error:
            raise self.error
        self.messages.append((observation, request_id, idempotency_key))


def rate() -> Rate:
    timestamp = datetime(2026, 7, 20, 8, 0, tzinfo=UTC)
    return Rate(
        instrument_id="crypto:bitcoin:usd",
        kind="crypto",
        base="BTC",
        quote="USD",
        name="Bitcoin",
        price=Decimal("64226.1234"),
        source="coingecko",
        source_timestamp=timestamp,
        requested_at=timestamp,
        sparkline_7d=[Decimal("1"), Decimal("2")],
    )


def test_observation_event_excludes_ui_only_sparkline():
    observation, idempotency_key = observation_payload(rate(), "request-id")
    assert observation["request_id"] == "request-id"
    assert "sparkline_7d" not in observation
    assert idempotency_key.startswith("coingecko:crypto:bitcoin:usd:")


def test_api_fetcher_settings_have_no_database_or_history_url():
    settings = Settings()
    assert not hasattr(settings, "database_url")
    assert not hasattr(settings, "backend_service_url")


def test_json_formatter_keeps_structured_log_fields():
    record = logging.LogRecord("rateboard", logging.INFO, __file__, 1, "completed", (), None)
    record.rateboard_fields = {"event": "collector_cycle", "request_id": "request-id", "queued": 2}

    payload = json.loads(JsonFormatter().format(record))

    assert payload["service"] == "api-fetcher"
    assert payload["level"] == "info"
    assert payload["event"] == "collector_cycle"
    assert payload["request_id"] == "request-id"
    assert payload["queued"] == 2
