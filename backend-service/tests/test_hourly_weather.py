import importlib.util
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[2]

spec = importlib.util.spec_from_file_location("backend_app_hourly", ROOT / "backend-service" / "app.py")
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class ApiContractTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 7, 24, 9, tzinfo=timezone.utc)
        self.client = backend.app.test_client()

    def test_history_accepts_only_24_or_168(self):
        for invalid in ("0", "48", "abc", "169"):
            response = self.client.get(f"/api/history?hours={invalid}")
            self.assertEqual(response.status_code, 400)
            self.assertIn("error", response.get_json())

    def test_health_endpoint_returns_ok_on_db_success(self):
        with patch.object(backend, "get_connection") as mock_conn:
            response = self.client.get("/health")
            self.assertEqual(response.status_code, 200)
            self.assertEqual(response.get_json()["status"], "ok")

    def test_weather_endpoint_returns_current_conditions(self):
        mock_row = {
            "weather_at": self.now,
            "temperature": 18.5,
            "relative_humidity": 65.0,
            "wind_speed": 5.0,
            "temperature_unit": "°C",
            "humidity_unit": "%",
            "wind_speed_unit": "km/h",
            "fetched_at": self.now,
        }

        with patch.object(backend, "get_connection") as mock_conn:
            mock_cursor = MagicMock()
            mock_cursor.fetchone.return_value = mock_row
            mock_conn.return_value.__enter__.return_value.cursor.return_value.__enter__.return_value = mock_cursor

            response = self.client.get("/api/weather")
            self.assertEqual(response.status_code, 200)
            data = response.get_json()
            self.assertEqual(data["current"]["temperature_2m"], 18.5)

    def test_history_endpoint_returns_historical_points(self):
        with patch.object(backend, "get_history_from_database", return_value=[]):
            response = self.client.get("/api/history?hours=24")
            self.assertEqual(response.status_code, 200)
            data = response.get_json()
            self.assertEqual(data["hours"], 24)
            self.assertEqual(data["count"], 0)


if __name__ == "__main__":
    unittest.main()
