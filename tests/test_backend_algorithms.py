import importlib.util
import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import MagicMock

for mod in ["pika", "psycopg", "psycopg.rows", "redis", "apscheduler", "flask"]:
    if mod not in sys.modules:
        try:
            __import__(mod)
        except ImportError:
            mock = MagicMock()
            if mod == "psycopg.rows":
                mock.dict_row = MagicMock()
            elif mod == "flask":
                mock.Flask = lambda name: MagicMock()
                mock.jsonify = lambda d: d
            sys.modules[mod] = mock

ROOT = Path(__file__).resolve().parents[1]

spec = importlib.util.spec_from_file_location("backend_app", ROOT / "backend-service" / "app.py")
backend_app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend_app)

floor_to_hour = backend_app.floor_to_hour
parse_datetime = backend_app.parse_datetime
normalize_forecast_points = backend_app.normalize_forecast_points
normalize_history_points = backend_app.normalize_history_points
ProviderServiceError = backend_app.ProviderServiceError


class BackendAlgorithmTests(unittest.TestCase):
    def setUp(self):
        self.start = datetime(2026, 7, 24, 0, tzinfo=timezone.utc)

    def provider_forecast_payload(self, times):
        return {
            "hourly": {
                "time": [int(value.timestamp()) for value in times],
                "temperature_2m": [10.0 + index for index in range(len(times))],
            },
            "source": "test",
        }

    def provider_history_payload(self, times):
        return {
            "hourly": {
                "time": [int(value.timestamp()) for value in times],
                "temperature_2m": [10.0 + index for index in range(len(times))],
                "relative_humidity_2m": [60 + index for index in range(len(times))],
                "wind_speed_10m": [4.0 + index for index in range(len(times))],
            },
            "source": "test",
        }

    def test_floor_to_hour_truncates_minutes_and_seconds(self):
        dt = datetime(2026, 7, 28, 14, 35, 20, tzinfo=timezone.utc)
        floored = floor_to_hour(dt)
        self.assertEqual(floored, datetime(2026, 7, 28, 14, 0, 0, tzinfo=timezone.utc))

    def test_parse_datetime_normalizes_iso_string(self):
        parsed = parse_datetime("2026-07-28T14:00:00Z")
        self.assertEqual(parsed, datetime(2026, 7, 28, 14, 0, 0, tzinfo=timezone.utc))

    def test_forecast_normalization_returns_24_sorted_points(self):
        times = [self.start + timedelta(hours=index) for index in range(24)]
        payload = self.provider_forecast_payload(list(reversed(times)))

        points = normalize_forecast_points(payload)

        actual = [point["forecast_at"] for point in points]
        self.assertEqual(actual, times)
        self.assertEqual(len(points), 24)

    def test_history_normalization_drops_incomplete_rows(self):
        past_time = datetime(2026, 7, 20, 10, 0, tzinfo=timezone.utc)
        payload = self.provider_history_payload([past_time])

        points = normalize_history_points(payload)

        self.assertEqual(len(points), 1)
        self.assertEqual(points[0]["weather_at"], past_time)


if __name__ == "__main__":
    unittest.main()
