from uuid import UUID

import pytest
from fastapi import Request
from httpx2 import AsyncClient
from ui_service.routes import unexpected_exception_handler
from ui_service.schemas import BlacklistLastError

from .conftest import FakeApplicationClient, FakeThemeRepository

API_SECRET = "TEST_ABUSEIPDB_SECRET_DO_NOT_LOG"


@pytest.mark.anyio
async def test_unexpected_error_response_hides_secret_and_correlates_request(
    caplog,
) -> None:
    request_id = "6f5aa064-43e8-4dbb-a544-d60b68af5cbd"
    request = Request(
        {
            "type": "http",
            "method": "GET",
            "path": "/",
            "headers": [(b"x-request-id", request_id.encode())],
        }
    )

    response = await unexpected_exception_handler(
        request, RuntimeError(f"Cookie={API_SECRET}")
    )

    assert response.status_code == 500
    assert response.headers["X-Request-ID"] == request_id
    assert API_SECRET not in bytes(response.body).decode()
    assert API_SECRET not in caplog.text


@pytest.mark.anyio
async def test_readiness_reflects_application_state(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    request_id = "6f5aa064-43e8-4dbb-a544-d60b68af5cbd"
    ready = await client.get("/health/ready", headers={"X-Request-ID": request_id})
    application_client.ready_error = "History is unavailable"
    unavailable = await client.get("/health/ready")

    assert ready.status_code == 200
    assert ready.json() == {"status": "ready"}
    assert ready.headers["X-Request-ID"] == request_id
    assert unavailable.status_code == 503
    assert unavailable.json() == {"status": "not ready"}


@pytest.mark.anyio
async def test_readiness_reports_redis_failure(
    client: AsyncClient, theme_repository: FakeThemeRepository
) -> None:
    theme_repository.ping_error = True

    response = await client.get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {"status": "not ready"}


@pytest.mark.anyio
async def test_main_page_displays_form_and_recent_history(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    response = await client.get("/")

    assert response.status_code == 200
    assert 'name="ip_address"' in response.text
    assert 'name="max_age_days"' in response.text
    assert "Recent history" in response.text
    assert "8.8.8.8" in response.text
    assert UUID(response.headers["X-Request-ID"])
    assert application_client.history_request_id == response.headers["X-Request-ID"]


@pytest.mark.anyio
async def test_submit_displays_normalized_result_and_refreshes_history(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    request_id = "6f5aa064-43e8-4dbb-a544-d60b68af5cbd"
    response = await client.post(
        "/",
        data={
            "ip_address": "2606:4700:4700::1111",
            "max_age_days": "90",
        },
        headers={"X-Request-ID": request_id},
    )

    assert response.status_code == 200
    assert "Current normalized result" in response.text
    assert "2606:4700:4700::1111" in response.text
    assert "12%" in response.text
    assert application_client.check_request == {
        "ip_address": "2606:4700:4700::1111",
        "max_age_days": 90,
        "request_id": request_id,
    }
    assert application_client.history_request_id == request_id
    assert response.headers["X-Request-ID"] == request_id


@pytest.mark.anyio
async def test_application_validation_error_is_readable_and_preserves_input(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.check_error = "The supplied IP address is not globally routable."

    response = await client.post(
        "/",
        data={"ip_address": "192.168.1.25", "max_age_days": "60"},
    )

    assert response.status_code == 200
    assert "The supplied IP address is not globally routable." in response.text
    assert 'value="192.168.1.25"' in response.text
    assert 'value="60"' in response.text


@pytest.mark.anyio
async def test_local_form_error_preserves_values_without_check_call(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    response = await client.post(
        "/",
        data={"ip_address": "8.8.8.8", "max_age_days": "not-a-number"},
    )

    assert response.status_code == 200
    assert "Max age must be a whole number between 1 and 365." in response.text
    assert 'value="8.8.8.8"' in response.text
    assert 'value="not-a-number"' in response.text
    assert application_client.check_request is None


@pytest.mark.anyio
async def test_dependency_error_is_readable_and_preserves_input(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.check_error = (
        "Application service is unavailable. Please try again."
    )

    response = await client.post(
        "/",
        data={"ip_address": "8.8.4.4", "max_age_days": "30"},
    )

    assert response.status_code == 200
    assert "Application service is unavailable. Please try again." in response.text
    assert 'value="8.8.4.4"' in response.text


@pytest.mark.anyio
async def test_history_dependency_error_keeps_page_usable(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.history_error = "Recent history is temporarily unavailable."

    response = await client.get("/")

    assert response.status_code == 200
    assert "Recent history is temporarily unavailable." in response.text
    assert 'name="ip_address"' in response.text


@pytest.mark.anyio
async def test_blacklist_page_displays_ready_snapshot_with_ipv4_and_ipv6(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    request_id = "6f5aa064-43e8-4dbb-a544-d60b68af5cbd"
    response = await client.get("/blacklist", headers={"X-Request-ID": request_id})

    assert response.status_code == 200
    assert "The latest blacklist snapshot is ready." in response.text
    assert "2026-07-22 12:00:00+00:00" in response.text
    assert "2026-07-22 12:00:02+00:00" in response.text
    assert "8.8.8.8" in response.text
    assert "IPv4" in response.text
    assert "2606:4700:4700::1111" in response.text
    assert "IPv6" in response.text
    assert "4 of 5" in response.text
    assert response.headers["X-Request-ID"] == request_id
    assert application_client.blacklist_status_request_id == request_id
    assert application_client.blacklist_request == {
        "limit": 100,
        "offset": 0,
        "request_id": request_id,
    }
    assert application_client.blacklist_analytics_request == {
        "pair_limit": 10,
        "request_id": request_id,
    }
    assert application_client.blacklist_turnover_request is not None
    assert application_client.blacklist_turnover_request["interval"] == "day"


@pytest.mark.anyio
async def test_blacklist_page_displays_empty_state_without_loading_entries(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.blacklist_status_result = (
        application_client.blacklist_status_result.model_copy(
            update={
                "state": "empty",
                "latest_snapshot_id": None,
                "latest_provider_generated_at": None,
                "latest_fetched_at": None,
                "last_success_at": None,
            }
        )
    )

    response = await client.get("/blacklist")

    assert response.status_code == 200
    assert "No successful blacklist snapshot is available yet." in response.text
    assert "Blacklist entries" not in response.text
    assert application_client.blacklist_request is None
    assert application_client.blacklist_analytics_request is None
    assert application_client.blacklist_turnover_request is None


@pytest.mark.anyio
async def test_blacklist_page_displays_stale_state_and_valid_data(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.blacklist_status_result = (
        application_client.blacklist_status_result.model_copy(
            update={"state": "stale", "data_stale": True}
        )
    )

    response = await client.get("/blacklist")

    assert "The displayed blacklist snapshot is stale." in response.text
    assert "8.8.8.8" in response.text


@pytest.mark.anyio
async def test_blacklist_page_displays_degraded_state_and_valid_data(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.blacklist_status_result = (
        application_client.blacklist_status_result.model_copy(
            update={
                "state": "degraded",
                "last_error": BlacklistLastError(
                    code="PROVIDER_SERVICE_UNAVAILABLE",
                    message="The latest synchronization attempt failed.",
                ),
            }
        )
    )

    response = await client.get("/blacklist")

    assert "The latest synchronization failed." in response.text
    assert "The latest synchronization attempt failed." in response.text
    assert "8.8.8.8" in response.text


@pytest.mark.anyio
async def test_blacklist_page_displays_history_unavailable_error(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.blacklist_status_error = (
        "Application service is unavailable. Please try again."
    )

    response = await client.get("/blacklist")

    assert response.status_code == 200
    assert "Application service is unavailable. Please try again." in response.text
    assert "Blacklist entries" not in response.text


@pytest.mark.anyio
async def test_blacklist_page_paginates_latest_snapshot(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.blacklist_page = application_client.blacklist_page.model_copy(
        update={"total": 250}
    )

    first = await client.get("/blacklist?page=1")
    second = await client.get("/blacklist?page=2")

    assert 'href="/blacklist?page=2"' in first.text
    assert 'href="/blacklist?page=1"' in second.text
    assert 'href="/blacklist?page=3"' in second.text
    assert application_client.blacklist_request is not None
    assert application_client.blacklist_request["offset"] == 100


@pytest.mark.anyio
async def test_blacklist_page_escapes_history_content(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.blacklist_page.snapshot.provider = "<script>alert(1)</script>"

    response = await client.get("/blacklist")

    assert "<script>alert(1)</script>" not in response.text
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in response.text


@pytest.mark.anyio
async def test_blacklist_poll_status_returns_only_change_detection_fields(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    request_id = "6f5aa064-43e8-4dbb-a544-d60b68af5cbd"

    response = await client.get(
        "/blacklist/status", headers={"X-Request-ID": request_id}
    )

    assert response.status_code == 200
    assert response.json() == {
        "state": "ready",
        "latest_snapshot_id": 42,
        "data_stale": False,
    }
    assert response.headers["X-Request-ID"] == request_id
    assert application_client.blacklist_status_request_id == request_id
    assert application_client.blacklist_request is None
    assert application_client.blacklist_analytics_request is None


@pytest.mark.anyio
async def test_blacklist_poll_status_hides_history_failure_details(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.blacklist_status_error = "secret internal dependency detail"

    response = await client.get("/blacklist/status")

    assert response.status_code == 503
    assert response.json() == {"error": "Blacklist status is temporarily unavailable."}
    assert "secret" not in response.text
    assert UUID(response.headers["X-Request-ID"])


@pytest.mark.anyio
async def test_blacklist_page_loads_same_origin_polling_script(
    client: AsyncClient,
) -> None:
    page = await client.get("/blacklist")
    script = await client.get("/static/blacklist.js")

    assert '<script src="/static/blacklist.js"></script>' in page.text
    assert 'statusUrl: "/blacklist/status"' in page.text
    assert "currentSnapshotId: 42" in page.text
    assert script.status_code == 200
    assert "POLL_INTERVAL_MS = 30000" in script.text


@pytest.mark.anyio
async def test_blacklist_dashboard_is_server_rendered_and_accessible(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    response = await client.get("/blacklist")

    assert response.status_code == 200
    assert '<h2 id="analytics-heading">Snapshot analytics</h2>' in response.text
    assert 'aria-label="Latest snapshot analytics summary"' in response.text
    assert 'aria-label="Abuse confidence score distribution"' in response.text
    assert 'aria-label="Top country distribution"' in response.text
    assert 'aria-label="IP version composition"' in response.text
    assert 'aria-label="Recent snapshot change charts"' in response.text
    assert "View score data table" in response.text
    assert "View country data table" in response.text
    assert "View IP version data table" in response.text
    assert "Changes between recent accepted snapshot pairs" in response.text
    assert '<h3 id="turnover-chart-heading">Snapshot turnover</h3>' in response.text
    assert (
        '<h3 id="address-change-chart-heading">Added and removed IP addresses</h3>'
        in response.text
    )
    assert 'aria-label="Turnover chart range"' in response.text
    assert 'aria-current="page">30 days</a>' in response.text
    assert "Blacklist turnover data for the selected 30-day range" in response.text
    assert "50.0%" in response.text
    assert 'data-turnover-chart="line"' in response.text
    assert 'data-turnover-chart="bars"' in response.text
    assert "Retained entries" in response.text
    assert "Confidence threshold" in response.text
    assert "Unknown" in response.text
    assert "Other" in response.text
    assert "The 2-entry result limit was reached." in response.text
    assert "8.8.8.8" in response.text
    assert '<script src="/static/blacklist.js"></script>' in response.text
    assert "blacklist/analytics" not in response.text


@pytest.mark.anyio
async def test_blacklist_analytics_failure_preserves_entry_table(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.blacklist_analytics_error = (
        "internal analytics dependency detail"
    )

    response = await client.get("/blacklist")

    assert response.status_code == 200
    assert "Snapshot analytics are temporarily unavailable." in response.text
    assert "internal analytics dependency detail" not in response.text
    assert "Blacklist entries" in response.text
    assert "8.8.8.8" in response.text


@pytest.mark.anyio
async def test_turnover_failure_preserves_dashboard_and_snapshot_analytics(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.blacklist_turnover_error = "internal turnover dependency detail"

    response = await client.get("/blacklist")

    assert response.status_code == 200
    assert "Turnover history is temporarily unavailable." in response.text
    assert "internal turnover dependency detail" not in response.text
    assert "Snapshot analytics" in response.text
    assert "Blacklist entries" in response.text
    assert "8.8.8.8" in response.text


@pytest.mark.anyio
async def test_turnover_range_controls_request_supported_bounded_range(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    response = await client.get("/blacklist?range_days=90")

    assert response.status_code == 200
    assert 'aria-current="page">90 days</a>' in response.text
    request = application_client.blacklist_turnover_request
    assert request is not None
    assert request["interval"] == "day"
    assert (request["to"] - request["from"]).days == 90


@pytest.mark.anyio
async def test_invalid_turnover_range_is_rejected(client: AsyncClient) -> None:
    response = await client.get("/blacklist?range_days=14")

    assert response.status_code == 422


@pytest.mark.anyio
async def test_blacklist_dashboard_one_snapshot_has_useful_churn_empty_state(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    application_client.blacklist_analytics_result = (
        application_client.blacklist_analytics_result.model_copy(
            update={"snapshot_churn": []}
        )
    )

    response = await client.get("/blacklist")

    assert "Snapshot analytics" in response.text
    assert "Retained entries" in response.text
    assert (
        "Snapshot change history will appear after a second accepted snapshot."
        in response.text
    )
    assert "Blacklist entries" in response.text


@pytest.mark.anyio
async def test_blacklist_dashboard_escapes_analytics_content(
    client: AsyncClient, application_client: FakeApplicationClient
) -> None:
    sentinel = "<script>alert('analytics')</script>"
    application_client.blacklist_analytics_result.top_countries.items[
        0
    ].country_code = sentinel

    response = await client.get("/blacklist")

    assert sentinel not in response.text
    assert "&lt;script&gt;alert" in response.text


@pytest.mark.anyio
async def test_blacklist_dashboard_css_is_local_and_responsive(
    client: AsyncClient,
) -> None:
    page = await client.get("/blacklist")
    stylesheet = await client.get("/static/blacklist.css")

    assert '<link rel="stylesheet" href="/static/blacklist.css">' in page.text
    assert stylesheet.status_code == 200
    assert stylesheet.headers["content-type"].startswith("text/css")
    assert "@media (max-width: 44rem)" in stylesheet.text
    assert ".chart-grid" in stylesheet.text
    assert ".turnover-chart-grid" in stylesheet.text
    assert ".turnover-line" in stylesheet.text
