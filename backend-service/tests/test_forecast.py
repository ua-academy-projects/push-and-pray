import importlib.util
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]

spec = importlib.util.spec_from_file_location("backend_app_forecast", ROOT / "backend-service" / "app.py")
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


def make_provider_forecast():
    start_timestamp = 1_700_000_000

    return {
        "query": backend.CITY_NAME,
        "forecast_hours": backend.FORECAST_HOURS,
        "location": {
            "name": backend.CITY_NAME,
            "country": backend.COUNTRY_NAME,
            "latitude": backend.LATITUDE,
            "longitude": backend.LONGITUDE,
            "timezone": backend.WEATHER_TIMEZONE,
        },
        "hourly": {
            "time": [
                start_timestamp + hour * 3600
                for hour in range(backend.FORECAST_HOURS)
            ],
            "temperature_2m": [
                10 + hour / 10
                for hour in range(backend.FORECAST_HOURS)
            ],
        },
        "hourly_units": {
            "time": "unixtime",
            "temperature_2m": "°C",
        },
        "source": "test-provider",
        "generated_at": "2026-07-24T09:00:00+00:00",
    }


class ForecastApiTests(unittest.TestCase):
    def test_client_forecast_reads_database_only(self):
        cached_forecast = make_provider_forecast()

        with patch.object(
            backend,
            "get_forecast_from_database",
            return_value=cached_forecast,
        ) as database_read:
            response = backend.app.test_client().get("/api/forecast")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            len(response.get_json()["hourly"]["time"]),
            backend.FORECAST_HOURS,
        )
        database_read.assert_called_once_with()

    def test_missing_forecast_returns_waiting_state(self):
        with patch.object(
            backend,
            "get_forecast_from_database",
            return_value=None,
        ):
            response = backend.app.test_client().get("/api/forecast")

        self.assertEqual(response.status_code, 404)
        self.assertIn("готується", response.get_json()["error"])

    def test_forecast_normalization_returns_sorted_unique_points(self):
        forecast = make_provider_forecast()
        forecast["hourly"]["time"].reverse()
        forecast["hourly"]["temperature_2m"].reverse()

        points = backend.normalize_forecast_points(forecast)
        timestamps = [point["forecast_at"] for point in points]

        self.assertEqual(timestamps, sorted(timestamps))
        self.assertEqual(len(set(timestamps)), backend.FORECAST_HOURS)


if __name__ == "__main__":
    unittest.main()
