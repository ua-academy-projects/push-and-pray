from app.models import CurrentWeather, DailyWeather, HourlyWeather, Location, WeatherSync
from tests.factories import build_daily, build_hourly_day, build_sync, build_upsert_payload, kyiv_today


def _counts(db_session):
    return {
        "locations": db_session.query(Location).count(),
        "current_weather": db_session.query(CurrentWeather).count(),
        "daily_weather": db_session.query(DailyWeather).count(),
        "hourly_weather": db_session.query(HourlyWeather).count(),
        "weather_syncs": db_session.query(WeatherSync).count(),
    }


def test_put_weather_first_insert_creates_location_current_daily_hourly_and_sync(client, db_session):
    payload = build_upsert_payload()

    response = client.put("/internal/weather", json=payload)

    assert response.status_code == 200
    body = response.json()
    assert body["location"]["name"] == "Ivano-Frankivsk"
    assert body["current"]["temperature"] == payload["current"]["temperature"]
    assert len(body["daily"]) == 1
    assert len(body["hourly"]) == 24
    assert body["latest_success_sync"]["status"] == "success"
    assert body["latest_attempt_sync"]["status"] == "success"

    counts = _counts(db_session)
    assert counts == {
        "locations": 1,
        "current_weather": 1,
        "daily_weather": 1,
        "hourly_weather": 24,
        "weather_syncs": 1,
    }


def test_repeated_put_reuses_location_no_duplicate(client, db_session):
    client.put("/internal/weather", json=build_upsert_payload()).raise_for_status()
    client.put("/internal/weather", json=build_upsert_payload(location={"name": "Ivano-Frankivsk (renamed)"})).raise_for_status()

    assert db_session.query(Location).count() == 1
    location = db_session.query(Location).one()
    # find-or-create on (lat, lon) also refreshes display fields like name in place
    assert location.name == "Ivano-Frankivsk (renamed)"


def test_repeated_put_updates_current_weather_in_place(client, db_session):
    client.put("/internal/weather", json=build_upsert_payload(current={"temperature": 20.0})).raise_for_status()
    client.put("/internal/weather", json=build_upsert_payload(current={"temperature": 21.5})).raise_for_status()

    assert db_session.query(CurrentWeather).count() == 1
    row = db_session.query(CurrentWeather).one()
    assert row.temperature == 21.5


def test_repeated_put_same_date_upserts_daily_no_duplicate(client, db_session):
    today = kyiv_today()
    client.put("/internal/weather", json=build_upsert_payload(daily=[build_daily(today, temperature_max=25.0)])).raise_for_status()
    client.put("/internal/weather", json=build_upsert_payload(daily=[build_daily(today, temperature_max=28.0)])).raise_for_status()

    assert db_session.query(DailyWeather).count() == 1
    row = db_session.query(DailyWeather).one()
    assert row.temperature_max == 28.0


def test_repeated_put_same_hour_upserts_hourly_no_duplicate(client, db_session):
    client.put("/internal/weather", json=build_upsert_payload(hourly=build_hourly_day())).raise_for_status()
    client.put("/internal/weather", json=build_upsert_payload(hourly=build_hourly_day())).raise_for_status()

    assert db_session.query(HourlyWeather).count() == 24


def test_put_weather_records_open_meteo_call_metadata_on_success(client, db_session):
    payload = build_upsert_payload(
        sync=build_sync(open_meteo_request_url="https://api.open-meteo.com/v1/forecast?x=1", open_meteo_status_code=200, open_meteo_duration_ms=417)
    )
    client.put("/internal/weather", json=payload).raise_for_status()

    sync = db_session.query(WeatherSync).one()
    assert sync.status == "success"
    assert sync.open_meteo_request_url == "https://api.open-meteo.com/v1/forecast?x=1"
    assert sync.open_meteo_status_code == 200
    assert sync.open_meteo_duration_ms == 417
    assert sync.records_received == 1 + 1 + 24  # current + 1 daily row + 24 hourly rows


def test_sync_failure_endpoint_records_failure_with_partial_metadata(client, db_session):
    payload = {
        "location": {"name": "Ivano-Frankivsk", "country": "Ukraine", "latitude": 48.9226, "longitude": 24.7111, "timezone": "Europe/Kyiv"},
        "trigger_type": "scheduler",
        "started_at": "2026-07-20T10:00:00+00:00",
        "completed_at": "2026-07-20T10:00:10+00:00",
        "error_message": "Open-Meteo request timed out after 10s",
        "open_meteo_request_url": "https://api.open-meteo.com/v1/forecast?x=1",
        "open_meteo_status_code": None,
        "open_meteo_duration_ms": 10000,
    }

    response = client.post("/internal/syncs/failure", json=payload)

    assert response.status_code == 201
    body = response.json()
    assert body["status"] == "failed"
    assert body["error_message"] == "Open-Meteo request timed out after 10s"
    assert body["open_meteo_status_code"] is None
    assert body["open_meteo_duration_ms"] == 10000

    # a failure never touches the weather tables
    counts = _counts(db_session)
    assert counts["current_weather"] == 0
    assert counts["daily_weather"] == 0
    assert counts["hourly_weather"] == 0
    assert counts["weather_syncs"] == 1
    assert counts["locations"] == 1  # find-or-create still runs, so the failure can be attributed to a location


def test_sync_failure_does_not_require_prior_location(client, db_session):
    """The very first sync attempt ever can fail before any location exists -- must not 500."""
    assert db_session.query(Location).count() == 0

    payload = {
        "location": {"name": "Ivano-Frankivsk", "country": "Ukraine", "latitude": 48.9226, "longitude": 24.7111, "timezone": "Europe/Kyiv"},
        "trigger_type": "startup",
        "started_at": "2026-07-20T09:00:00+00:00",
        "completed_at": None,
        "error_message": "Connection refused",
    }

    response = client.post("/internal/syncs/failure", json=payload)

    assert response.status_code == 201
    assert db_session.query(Location).count() == 1


def test_put_weather_rollback_preserves_prior_data_on_failure(client, db_session):
    good_payload = build_upsert_payload(current={"temperature": 31.5})
    client.put("/internal/weather", json=good_payload).raise_for_status()

    same_time = "2026-07-20T05:00:00+00:00"
    broken_hourly_row = {
        "weather_time": same_time,
        "temperature": 1.0,
        "apparent_temperature": 1.0,
        "humidity": 50.0,
        "precipitation_probability": 0.0,
        "precipitation": 0.0,
        "weather_code": 1,
        "cloud_cover": 0.0,
        "visibility": 10000.0,
        "wind_speed": 1.0,
        "wind_direction": 1.0,
    }
    # Two rows sharing the same (location_id, weather_time) key in one request -> Postgres
    # rejects it mid-statement ("ON CONFLICT DO UPDATE command cannot affect row a second
    # time"), which must roll back the whole transaction, not just the hourly writes.
    broken_payload = build_upsert_payload(
        current={"temperature": 999.0},
        hourly=[broken_hourly_row, {**broken_hourly_row, "temperature": 2.0}],
    )

    response = client.put("/internal/weather", json=broken_payload)

    assert response.status_code == 500
    assert "detail" in response.json()
    assert "999" not in response.text  # no leaked internals/values from the failed attempt

    current = db_session.query(CurrentWeather).one()
    assert current.temperature == 31.5  # untouched by the failed attempt

    # the failed attempt must not have left a dangling sync row either -- it never got that far
    assert db_session.query(WeatherSync).count() == 1
    assert db_session.query(WeatherSync).one().status == "success"


def test_history_returns_newest_first_with_default_days(client, db_session):
    today = kyiv_today()
    for offset in range(11):
        day = today.fromordinal(today.toordinal() - offset)
        client.put(
            "/internal/weather",
            json=build_upsert_payload(daily=[build_daily(day, temperature_max=float(20 + offset))], hourly=[]),
        ).raise_for_status()

    response = client.get("/internal/weather/history")

    assert response.status_code == 200
    body = response.json()
    assert len(body["daily"]) == 11
    dates = [row["weather_date"] for row in body["daily"]]
    assert dates == sorted(dates, reverse=True)
    assert dates[0] == today.isoformat()


def test_history_days_parameter_out_of_range_is_rejected(client):
    assert client.get("/internal/weather/history", params={"days": 0}).status_code == 422
    assert client.get("/internal/weather/history", params={"days": 999}).status_code == 422
    assert client.get("/internal/weather/history", params={"days": 10}).status_code == 200


def test_get_latest_with_empty_database_returns_no_data_shape(client):
    response = client.get("/internal/weather/latest")

    assert response.status_code == 200
    body = response.json()
    assert body["location"] is None
    assert body["current"] is None
    assert body["daily"] == []
    assert body["hourly"] == []
    assert body["latest_success_sync"] is None


def test_health_reports_ok_when_database_is_reachable(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "connected"}
