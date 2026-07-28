import importlib.util
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock

for mod in ["pika", "requests", "flask"]:
    if mod not in sys.modules:
        try:
            __import__(mod)
        except ImportError:
            mock = MagicMock()
            if mod == "flask":
                mock.Flask = lambda name: MagicMock()
                mock.jsonify = lambda d: d
            sys.modules[mod] = mock

ROOT = Path(__file__).resolve().parents[1]

spec = importlib.util.spec_from_file_location("provider_app", ROOT / "provider-service" / "app.py")
provider_app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provider_app)

normalize_weather = provider_app.normalize_weather
normalize_forecast = provider_app.normalize_forecast


class ProviderAlgorithmTests(unittest.TestCase):
    def test_normalize_weather_returns_structured_dict(self):
        raw = {
            "current": {
                "time": "2026-07-28T14:00",
                "temperature_2m": 22.5,
                "relative_humidity_2m": 55,
                "wind_speed_10m": 12.0,
            },
            "current_units": {
                "temperature_2m": "°C",
                "relative_humidity_2m": "%",
                "wind_speed_10m": "km/h",
            },
        }

        result = normalize_weather(raw, 48.6348, 24.5694, "Europe/Kyiv")

        self.assertIn("current", result)
        self.assertEqual(result["current"]["temperature_2m"], 22.5)
        self.assertEqual(result["source"], "open-meteo")

    def test_normalize_forecast_extracts_hourly_points(self):
        raw = {
            "hourly": {
                "time": [1785236400, 1785240000],
                "temperature_2m": [20.0, 21.0],
            },
            "hourly_units": {
                "temperature_2m": "°C",
            },
        }

        result = normalize_forecast(raw, 48.6348, 24.5694, "Europe/Kyiv")

        self.assertIn("hourly", result)
        self.assertEqual(len(result["hourly"]["time"]), 2)


if __name__ == "__main__":
    unittest.main()
