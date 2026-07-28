import importlib.util
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]

spec = importlib.util.spec_from_file_location("provider_app_test", ROOT / "provider-service" / "app.py")
provider = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provider)


def external_payload(times):
    return {
        "latitude": 48.63,
        "longitude": 24.56,
        "timezone": "GMT",
        "hourly": {
            "time": [int(value.timestamp()) for value in times],
            "temperature_2m": [12.0] * len(times),
            "relative_humidity_2m": [70] * len(times),
            "wind_speed_10m": [5.0] * len(times),
        },
        "hourly_units": {
            "time": "unixtime",
            "temperature_2m": "°C",
            "relative_humidity_2m": "%",
            "wind_speed_10m": "km/h",
        },
    }


class ProviderEndpointTests(unittest.TestCase):
    def setUp(self):
        self.start = datetime(2026, 7, 24, 0, tzinfo=timezone.utc)

    def response_for(self, payload):
        response = Mock()
        response.ok = True
        response.raise_for_status.return_value = None
        response.json.return_value = payload
        return response

    def test_forecast_requests_and_returns_exactly_24_hours(self):
        times = [self.start + timedelta(hours=index) for index in range(24)]

        with patch.object(
            provider.requests,
            "get",
            return_value=self.response_for(external_payload(times)),
        ) as external_request:
            response = provider.app.test_client().get(
                "/weather/forecast",
                query_string={
                    "latitude": 48.6348,
                    "longitude": 24.5694,
                    "timezone": "Europe/Kyiv",
                },
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.get_json()["hourly"]["time"]), 24)

    def test_invalid_parameters_return_400(self):
        response = provider.app.test_client().get(
            "/weather/forecast?latitude=x&longitude=24&timezone=UTC"
        )
        self.assertEqual(response.status_code, 400)


if __name__ == "__main__":
    unittest.main()
