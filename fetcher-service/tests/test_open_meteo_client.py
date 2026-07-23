import httpx
import pytest
import respx

from app.clients.open_meteo_client import fetch_forecast
from app.exceptions import OpenMeteoConnectionError, OpenMeteoResponseError, OpenMeteoTimeoutError
from tests.fixtures import build_open_meteo_response, make_settings

BASE_URL = "https://api.open-meteo.com/v1/forecast"


@respx.mock
async def test_fetch_forecast_success_returns_data_and_call_metadata():
    route = respx.get(BASE_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))

    result = await fetch_forecast(make_settings())

    assert route.called
    assert result.status_code == 200
    assert result.data["current"]["temperature_2m"] == 24.5
    assert result.duration_ms >= 0
    assert result.request_url.startswith(BASE_URL)


@respx.mock
async def test_fetch_forecast_sends_correct_query_parameters():
    route = respx.get(BASE_URL).mock(return_value=httpx.Response(200, json=build_open_meteo_response()))

    settings = make_settings(weather_latitude=48.9226, weather_longitude=24.7111, weather_timezone="Europe/Kyiv")
    await fetch_forecast(settings)

    request = route.calls.last.request
    params = dict(httpx.QueryParams(request.url.query))
    assert params["latitude"] == "48.9226"
    assert params["longitude"] == "24.7111"
    assert params["timezone"] == "Europe/Kyiv"
    assert params["past_days"] == "10"
    assert params["forecast_days"] == "10"
    assert "temperature_2m" in params["current"]
    assert "temperature_2m" in params["hourly"]
    assert "temperature_2m_max" in params["daily"]
    assert "precipitation_probability_max" in params["daily"]


@respx.mock
async def test_fetch_forecast_timeout_raises_typed_error_with_metadata():
    respx.get(BASE_URL).mock(side_effect=httpx.TimeoutException("timed out"))

    with pytest.raises(OpenMeteoTimeoutError) as exc_info:
        await fetch_forecast(make_settings())

    assert exc_info.value.status_code is None
    assert exc_info.value.duration_ms is not None
    assert exc_info.value.request_url is not None


@respx.mock
async def test_fetch_forecast_connection_error_raises_typed_error():
    respx.get(BASE_URL).mock(side_effect=httpx.ConnectError("connection refused"))

    with pytest.raises(OpenMeteoConnectionError):
        await fetch_forecast(make_settings())


@respx.mock
async def test_fetch_forecast_non_2xx_raises_typed_error_with_status_code():
    respx.get(BASE_URL).mock(return_value=httpx.Response(503, text="Service Unavailable"))

    with pytest.raises(OpenMeteoResponseError) as exc_info:
        await fetch_forecast(make_settings())

    assert exc_info.value.status_code == 503
    assert exc_info.value.duration_ms is not None


@respx.mock
async def test_fetch_forecast_invalid_json_raises_typed_error():
    respx.get(BASE_URL).mock(return_value=httpx.Response(200, content=b"not json", headers={"content-type": "application/json"}))

    with pytest.raises(OpenMeteoResponseError) as exc_info:
        await fetch_forecast(make_settings())

    assert exc_info.value.status_code == 200
