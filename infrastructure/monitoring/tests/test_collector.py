"""Failure-oriented tests of the standalone cloud collector contract."""

import importlib.util
import json
from pathlib import Path
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = (
    ROOT / "infrastructure/ansible/oilscope/platform/roles/application_monitoring/files/collect.py"
)
spec = importlib.util.spec_from_file_location("collector", SCRIPT)
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


def test_missing_instrument_is_not_fresh():
    with pytest.raises(ValueError, match="Missing instrument"):
        collector.freshness([], 1000)


def test_freshness_uses_oldest_latest_observation():
    rows = [
        {"instrument_code": code, "fetched_at": f"2026-01-01T0{index}:00:00+00:00"}
        for index, code in enumerate(sorted(collector.EXPECTED_INSTRUMENTS))
    ]
    now = collector.dt.datetime(2026, 1, 1, 3, tzinfo=collector.dt.timezone.utc).timestamp()
    assert collector.freshness(rows, now) == 10800


def test_outbox_failure_is_not_reported_as_empty():
    with patch.object(
        collector,
        "request_json",
        return_value=(200, {"status": "ok", "outbox": {"error": "unavailable"}}),
    ):
        result = collector.collect({"role": "fetcher"})
    assert result["CollectionFailed"] == 1
    assert "OutboxPending" not in result


def test_empty_outbox_null_age_is_zero():
    health = {"status": "ok", "outbox": {"pending_count": 0, "oldest_pending_seconds": None}}
    with patch.object(collector, "request_json", return_value=(200, health)):
        result = collector.collect({"role": "fetcher"})
    assert result == {
        "CollectionFailed": 0,
        "HealthFailed": 0,
        "OutboxPending": 0,
        "OutboxOldestSeconds": 0,
    }


def test_unhealthy_fetcher_still_reports_durable_backlog():
    health = {"status": "degraded", "outbox": {"pending_count": 9, "oldest_pending_seconds": 90}}
    with patch.object(collector, "request_json", return_value=(503, health)):
        result = collector.collect({"role": "fetcher"})
    assert result["HealthFailed"] == 1
    assert result["OutboxPending"] == 9


def test_redis_persistence_failure_and_memory():
    info = (
        "used_memory:90\r\nmaxmemory:100\r\naof_enabled:1\r\n"
        "aof_last_write_status:err\r\naof_last_bgrewrite_status:ok\r\n"
        "rdb_last_bgsave_status:ok\r\n"
    )
    assert collector.redis_metrics(info) == {"RedisMemoryPercent": 90, "RedisPersistenceFailed": 1}
    with pytest.raises(ValueError):
        collector.redis_metrics(info.replace("maxmemory:100", "maxmemory:0"))


def test_broker_retry_and_dead_queues_are_counted():
    rows = [
        {"name": name, "messages_ready": ready, "messages_unacknowledged": unacked}
        for name, ready, unacked in [
            ("prices", 4, 2),
            ("prices.retry", 3, 1),
            ("prices.dead", 2, 1),
        ]
    ]
    assert collector.queue_metrics(rows, "prices") == {
        "RabbitReady": 7,
        "RabbitUnacked": 3,
        "RabbitDead": 3,
    }
    with pytest.raises(ValueError, match="topology"):
        collector.queue_metrics(rows[:1], "prices")


def test_transport_contract_matches_terraform_metrics():
    catalog = json.loads((ROOT / "infrastructure/terraform/monitoring-metrics.json").read_text())
    metrics = dict.fromkeys(catalog, 1)
    config = {
        "namespace": "oilscope-test/Application",
        "name_prefix": "oilscope",
        "vm_key": "history",
        "project_id": "project",
        "instance_id": "123",
        "zone": "europe-west1-b",
        "environment": "test",
    }
    emf = collector.emf(config, metrics, 1234)
    assert emf["_aws"]["Timestamp"] == 1234000
    assert emf["_aws"]["CloudWatchMetrics"][0]["Dimensions"] == [["VMKey"]]
    assert {m["Name"]: m["Unit"] for m in emf["_aws"]["CloudWatchMetrics"][0]["Metrics"]} == {
        name: definition["unit"] for name, definition in catalog.items()
    }
    payload = collector.gcp_payload(config, metrics, 1234)
    assert len(payload["timeSeries"]) == len(catalog)
    assert all(
        point["resource"]["labels"]["instance_id"] == "123" for point in payload["timeSeries"]
    )


def test_missing_docker_is_visible():
    with patch.object(collector, "command", side_effect=FileNotFoundError):
        result = collector.collect({"role": "ui"})
    assert result == {"CollectionFailed": 1, "HealthFailed": 1}
