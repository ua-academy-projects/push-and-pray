from datetime import UTC, datetime
from typing import Any
from unittest.mock import Mock

import pytest
from history_service.blacklist_read import get_blacklist_read_service
from history_service.provider_client import get_provider_client
from history_service.schemas import (
    BlacklistAnalyticsResponse,
    BlacklistAnalyticsSnapshot,
    BlacklistCountryCount,
    BlacklistCountryDistribution,
    BlacklistEntryResponse,
    BlacklistIpVersionCount,
    BlacklistLastError,
    BlacklistPage,
    BlacklistScoreBucket,
    BlacklistSnapshotChurn,
    BlacklistSnapshotList,
    BlacklistSnapshotSummary,
    BlacklistStatusResponse,
    BlacklistTurnoverResponse,
)
from httpx2 import AsyncClient

REQUEST_ID = "6f5aa064-43e8-4dbb-a544-d60b68af5cbd"
NOW = datetime(2026, 7, 22, 12, 0, tzinfo=UTC)


def summary() -> BlacklistSnapshotSummary:
    return BlacklistSnapshotSummary(
        snapshot_id=42,
        provider="AbuseIPDB",
        provider_generated_at=NOW,
        fetched_at=NOW,
        confidence_minimum=90,
        requested_limit=1000,
        returned_count=1,
    )


def page() -> BlacklistPage:
    return BlacklistPage(
        snapshot=summary(),
        items=[
            BlacklistEntryResponse(
                ip_address="8.8.8.8",
                ip_version=4,
                abuse_confidence_score=100,
                country_code="US",
                last_reported_at=NOW,
            )
        ],
        limit=100,
        offset=0,
        total=1,
    )


def analytics() -> BlacklistAnalyticsResponse:
    return BlacklistAnalyticsResponse(
        latest_snapshot=BlacklistAnalyticsSnapshot(
            snapshot_id=42,
            provider_generated_at=NOW,
            confidence_minimum=90,
            requested_limit=1000,
            returned_count=1000,
            result_limit_reached=True,
        ),
        score_distribution=[BlacklistScoreBucket(minimum=100, maximum=100, count=1000)],
        top_countries=BlacklistCountryDistribution(
            items=[BlacklistCountryCount(country_code="US", count=600)],
            unknown_count=100,
            other_count=300,
        ),
        ip_versions=[
            BlacklistIpVersionCount(ip_version=4, count=900),
            BlacklistIpVersionCount(ip_version=6, count=100),
        ],
        snapshot_churn=[
            BlacklistSnapshotChurn(
                current_snapshot_id=42,
                previous_snapshot_id=41,
                added=20,
                removed=10,
                retained=980,
            )
        ],
    )


@pytest.mark.anyio
async def test_blacklist_read_endpoints_never_call_provider(
    client: AsyncClient, override_dependency: Any
) -> None:
    service = Mock()
    service.status.return_value = BlacklistStatusResponse(
        state="ready",
        sync_in_progress=False,
        latest_snapshot_id=42,
        latest_provider_generated_at=NOW,
        latest_fetched_at=NOW,
        data_stale=False,
    )
    service.latest.return_value = page()
    service.snapshots.return_value = BlacklistSnapshotList(
        items=[summary()], limit=20, offset=0, total=1
    )
    service.snapshot.return_value = page()
    service.analytics.return_value = analytics()
    provider = Mock()
    override_dependency(get_blacklist_read_service, service)
    override_dependency(get_provider_client, provider)

    responses = [
        await client.get(
            "/api/v1/blacklist/status", headers={"X-Request-ID": REQUEST_ID}
        ),
        await client.get("/api/v1/blacklist", headers={"X-Request-ID": REQUEST_ID}),
        await client.get(
            "/api/v1/blacklist/snapshots", headers={"X-Request-ID": REQUEST_ID}
        ),
        await client.get(
            "/api/v1/blacklist/snapshots/42",
            headers={"X-Request-ID": REQUEST_ID},
        ),
        await client.get(
            "/api/v1/blacklist/analytics?pair_limit=10",
            headers={"X-Request-ID": REQUEST_ID},
        ),
    ]

    assert [response.status_code for response in responses] == [200] * 5
    assert all(response.headers["X-Request-ID"] == REQUEST_ID for response in responses)
    provider.check.assert_not_called()
    provider.get_blacklist.assert_not_called()
    service.analytics.assert_called_once()


@pytest.mark.anyio
async def test_blacklist_empty_and_missing_snapshot_return_safe_404(
    client: AsyncClient, override_dependency: Any
) -> None:
    service = Mock()
    service.latest.return_value = None
    service.snapshot.return_value = None
    override_dependency(get_blacklist_read_service, service)

    latest = await client.get("/api/v1/blacklist", headers={"X-Request-ID": REQUEST_ID})
    missing = await client.get(
        "/api/v1/blacklist/snapshots/999", headers={"X-Request-ID": REQUEST_ID}
    )

    assert latest.status_code == 404
    assert missing.status_code == 404
    assert latest.json()["error"]["code"] == "BLACKLIST_SNAPSHOT_NOT_FOUND"
    assert missing.json()["error"]["request_id"] == REQUEST_ID


@pytest.mark.anyio
@pytest.mark.parametrize(
    "query",
    [
        "limit=0",
        "limit=101",
        "offset=-1",
        "ip_version=5",
        "minimum_score=-1",
        "minimum_score=101",
        "country_code=us",
        "country_code=USA",
    ],
)
async def test_blacklist_entry_query_validation(
    client: AsyncClient, query: str
) -> None:
    response = await client.get(f"/api/v1/blacklist?{query}")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "INVALID_REQUEST"


@pytest.mark.anyio
@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1"])
async def test_blacklist_snapshot_list_query_validation(
    client: AsyncClient, query: str
) -> None:
    response = await client.get(f"/api/v1/blacklist/snapshots?{query}")
    assert response.status_code == 422


@pytest.mark.anyio
@pytest.mark.parametrize("pair_limit", [0, 31])
async def test_blacklist_analytics_pair_limit_is_bounded(
    client: AsyncClient, pair_limit: int
) -> None:
    response = await client.get(f"/api/v1/blacklist/analytics?pair_limit={pair_limit}")
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "INVALID_REQUEST"


@pytest.mark.anyio
@pytest.mark.parametrize(
    "query",
    [
        "from=2026-07-22T00:00:00Z&to=2026-07-23T00:00:00Z&interval=quarter",
        "from=2026-07-22T00:00:00Z&to=2027-07-24T00:00:00Z&interval=day",
        "from=2026-07-23T00:00:00Z&to=2026-07-22T00:00:00Z&interval=day",
        "from=2026-07-22T00:00:00&to=2026-07-23T00:00:00Z&interval=day",
    ],
)
async def test_blacklist_turnover_query_validation(
    client: AsyncClient, query: str
) -> None:
    response = await client.get(f"/api/v1/blacklist/analytics/turnover?{query}")

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "INVALID_REQUEST"


@pytest.mark.anyio
async def test_blacklist_turnover_endpoint_uses_explicit_nulls(
    client: AsyncClient, override_dependency: Any
) -> None:
    service = Mock()
    service.turnover.return_value = BlacklistTurnoverResponse.model_validate(
        {
            "from": "2026-07-22T00:00:00Z",
            "to": "2026-07-22T02:00:00Z",
            "interval": "hour",
            "points": [
                {
                    "period_start": "2026-07-22T00:00:00Z",
                    "turnover_percent": None,
                    "added_count": None,
                    "removed_count": None,
                    "snapshot_id": None,
                }
            ],
        }
    )
    override_dependency(get_blacklist_read_service, service)

    response = await client.get(
        "/api/v1/blacklist/analytics/turnover"
        "?from=2026-07-22T00:00:00Z"
        "&to=2026-07-22T02:00:00Z"
        "&interval=hour"
    )

    assert response.status_code == 200
    assert response.json()["points"][0] == {
        "period_start": "2026-07-22T00:00:00Z",
        "turnover_percent": None,
        "added_count": None,
        "removed_count": None,
        "snapshot_id": None,
    }
    service.turnover.assert_called_once()


@pytest.mark.anyio
async def test_blacklist_turnover_all_mode_returns_adaptive_metadata(
    client: AsyncClient, override_dependency: Any
) -> None:
    service = Mock()
    service.turnover.return_value = BlacklistTurnoverResponse.model_validate(
        {
            "from": "2026-01-02T08:00:00Z",
            "to": "2026-07-22T12:00:00Z",
            "interval": "month",
            "requested_period": "all",
            "effective_start": "2026-01-02T08:00:00Z",
            "effective_end": "2026-07-22T12:00:00Z",
            "granularity": "month",
            "bucket_count": 0,
            "points": [],
        }
    )
    override_dependency(get_blacklist_read_service, service)

    response = await client.get(
        "/api/v1/blacklist/analytics/turnover?period=all&interval=auto"
    )

    assert response.status_code == 200
    assert response.json() == {
        "from": "2026-01-02T08:00:00Z",
        "to": "2026-07-22T12:00:00Z",
        "interval": "month",
        "requested_period": "all",
        "effective_start": "2026-01-02T08:00:00Z",
        "effective_end": "2026-07-22T12:00:00Z",
        "granularity": "month",
        "bucket_count": 0,
        "points": [],
    }
    query = service.turnover.call_args.args[1]
    assert query.period == "all"
    assert query.interval == "auto"


@pytest.mark.anyio
async def test_blacklist_analytics_contract_has_stable_ordered_fields(
    client: AsyncClient, override_dependency: Any
) -> None:
    service = Mock()
    service.analytics.return_value = analytics()
    override_dependency(get_blacklist_read_service, service)

    response = await client.get(
        "/api/v1/blacklist/analytics?pair_limit=3",
        headers={"X-Request-ID": REQUEST_ID},
    )

    assert response.status_code == 200
    assert response.headers["X-Request-ID"] == REQUEST_ID
    body = response.json()
    assert body["latest_snapshot"]["result_limit_reached"] is True
    assert body["top_countries"] == {
        "items": [{"country_code": "US", "count": 600}],
        "unknown_count": 100,
        "other_count": 300,
    }
    assert body["ip_versions"] == [
        {"ip_version": 4, "count": 900},
        {"ip_version": 6, "count": 100},
    ]
    assert body["snapshot_churn"][0]["current_snapshot_id"] == 42
    service.analytics.assert_called_once()


def test_status_error_model_contains_only_safe_summary() -> None:
    result = BlacklistStatusResponse(
        state="degraded",
        sync_in_progress=False,
        latest_snapshot_id=42,
        latest_provider_generated_at=NOW,
        latest_fetched_at=NOW,
        data_stale=False,
        last_error=BlacklistLastError(
            code="UPSTREAM_TIMEOUT",
            message="The latest synchronization attempt failed.",
        ),
    )
    assert result.model_dump()["last_error"] == {
        "code": "UPSTREAM_TIMEOUT",
        "message": "The latest synchronization attempt failed.",
    }
    assert result.polling_owner == "provider"
