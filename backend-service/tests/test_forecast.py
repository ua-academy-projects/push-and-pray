import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import app as backend


class ConnectionContext:
    def __init__(self):
        self.connection = object()

    def __enter__(self):
        return self.connection

    def __exit__(
        self,
        exception_type,
        exception,
        traceback,
    ):
        return False


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
                for hour in range(
                    backend.FORECAST_HOURS
                )
            ],
            "temperature_2m": [
                10 + hour / 10
                for hour in range(
                    backend.FORECAST_HOURS
                )
            ],
        },
        "hourly_units": {
            "time": "unixtime",
            "temperature_2m": "°C",
        },
        "source": "test-provider",
        "generated_at": (
            "2026-07-24T09:00:00+00:00"
        ),
    }


def make_cached_forecast():
    forecast = make_provider_forecast()

    return {
        **forecast,
        "last_success_at": (
            "2026-07-24T09:00:00+00:00"
        ),
        "stale": False,
        "storage": "database",
    }


class ForecastApiTests(unittest.TestCase):
    def test_client_forecast_reads_database_only(self):
        cached_forecast = make_cached_forecast()

        with (
            patch.object(
                backend,
                "get_forecast_from_database",
                return_value=cached_forecast,
            ) as database_read,
            patch.object(
                backend,
                "fetch_forecast_from_provider",
            ) as provider_request,
        ):
            response = backend.app.test_client().get(
                "/api/forecast"
            )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.get_json()["storage"],
            "database",
        )
        self.assertEqual(
            len(
                response.get_json()[
                    "hourly"
                ]["time"]
            ),
            backend.FORECAST_HOURS,
        )
        database_read.assert_called_once_with()
        provider_request.assert_not_called()

    def test_missing_forecast_returns_waiting_state(self):
        with patch.object(
            backend,
            "get_forecast_from_database",
            return_value=None,
        ):
            response = backend.app.test_client().get(
                "/api/forecast"
            )

        self.assertEqual(response.status_code, 404)
        self.assertIn(
            "готується",
            response.get_json()["error"],
        )


class ForecastRefreshTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(
            2026,
            7,
            24,
            9,
            tzinfo=timezone.utc,
        )

    def test_refresh_within_24_hours_skips_provider(self):
        recent_success = (
            self.now -
            timedelta(hours=23, minutes=59)
        )

        with (
            patch.object(
                backend,
                "get_connection",
                return_value=ConnectionContext(),
            ),
            patch.object(
                backend,
                "acquire_forecast_refresh_lock",
                return_value=True,
            ),
            patch.object(
                backend,
                "get_forecast_last_success_at",
                return_value=recent_success,
            ),
            patch.object(
                backend,
                "fetch_forecast_from_provider",
            ) as provider_request,
        ):
            result = backend.refresh_forecast_if_due(
                now=self.now
            )

        self.assertFalse(result["updated"])
        self.assertEqual(
            result["reason"],
            "forecast_is_fresh",
        )
        provider_request.assert_not_called()

    def test_refresh_after_24_hours_updates_forecast(self):
        previous_success = (
            self.now -
            timedelta(hours=24)
        )
        provider_forecast = make_provider_forecast()

        with (
            patch.object(
                backend,
                "get_connection",
                return_value=ConnectionContext(),
            ),
            patch.object(
                backend,
                "acquire_forecast_refresh_lock",
                return_value=True,
            ),
            patch.object(
                backend,
                "get_forecast_last_success_at",
                return_value=previous_success,
            ),
            patch.object(
                backend,
                "fetch_forecast_from_provider",
                return_value=provider_forecast,
            ) as provider_request,
            patch.object(
                backend,
                "save_forecast",
                return_value={
                    "batch_id": "test-batch",
                    "last_success_at": (
                        self.now.isoformat()
                    ),
                    "point_count": 24,
                },
            ) as database_write,
        ):
            result = backend.refresh_forecast_if_due(
                now=self.now
            )

        self.assertTrue(result["updated"])
        provider_request.assert_called_once_with()
        database_write.assert_called_once()

    def test_provider_error_keeps_previous_forecast(self):
        previous_success = (
            self.now -
            timedelta(hours=25)
        )

        with (
            patch.object(
                backend,
                "get_connection",
                return_value=ConnectionContext(),
            ),
            patch.object(
                backend,
                "acquire_forecast_refresh_lock",
                return_value=True,
            ),
            patch.object(
                backend,
                "get_forecast_last_success_at",
                return_value=previous_success,
            ),
            patch.object(
                backend,
                "fetch_forecast_from_provider",
                side_effect=backend.ProviderServiceError(
                    "Provider unavailable."
                ),
            ),
            patch.object(
                backend,
                "save_forecast",
            ) as database_write,
        ):
            with self.assertRaises(
                backend.ProviderServiceError
            ):
                backend.refresh_forecast_if_due(
                    now=self.now
                )

        database_write.assert_not_called()

    def test_concurrent_refresh_skips_provider(self):
        with (
            patch.object(
                backend,
                "get_connection",
                return_value=ConnectionContext(),
            ),
            patch.object(
                backend,
                "acquire_forecast_refresh_lock",
                return_value=False,
            ),
            patch.object(
                backend,
                "fetch_forecast_from_provider",
            ) as provider_request,
        ):
            result = backend.refresh_forecast_if_due(
                now=self.now
            )

        self.assertEqual(
            result["reason"],
            "refresh_in_progress",
        )
        provider_request.assert_not_called()

    def test_points_are_sorted_unique_and_hourly(self):
        forecast = make_provider_forecast()
        forecast["hourly"]["time"].reverse()
        forecast[
            "hourly"
        ]["temperature_2m"].reverse()

        points = backend.normalize_forecast_points(
            forecast
        )

        timestamps = [
            point["forecast_at"]
            for point in points
        ]

        self.assertEqual(
            timestamps,
            sorted(timestamps),
        )
        self.assertEqual(
            len(set(timestamps)),
            backend.FORECAST_HOURS,
        )

        for previous, current in zip(
            timestamps,
            timestamps[1:],
        ):
            self.assertEqual(
                current - previous,
                timedelta(hours=1),
            )


if __name__ == "__main__":
    unittest.main()
