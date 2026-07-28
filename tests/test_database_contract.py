import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class DatabaseContractTests(unittest.TestCase):
    def setUp(self):
        self.migration = (
            ROOT / "backend-service" / "migrations" / "001_unified_hourly_weather.sql"
        ).read_text(encoding="utf-8")
        self.backend = (ROOT / "backend-service" / "app.py").read_text(
            encoding="utf-8"
        )

    def test_required_hourly_columns_exist(self):
        for column in (
            "location_key",
            "weather_at TIMESTAMPTZ",
            "temperature",
            "relative_humidity",
            "wind_speed",
            "temperature_unit",
            "humidity_unit",
            "wind_speed_unit",
            "provider",
            "data_kind",
            "source_generated_at TIMESTAMPTZ",
            "fetched_at TIMESTAMPTZ",
        ):
            self.assertIn(column, self.migration)

    def test_location_and_hour_are_unique(self):
        self.assertRegex(
            self.migration,
            re.compile(
                r"PRIMARY KEY\s*\(\s*location_key,\s*weather_at\s*\)",
                re.IGNORECASE,
            ),
        )

    def test_hourly_writes_are_upserts(self):
        self.assertIn("ON CONFLICT (location_key, weather_at)", self.backend)
        self.assertIn("DO UPDATE SET", self.backend)

    def test_legacy_jsonb_storage_is_not_created(self):
        self.assertNotIn("response_data JSONB", self.migration)
        self.assertNotIn("CREATE TABLE IF NOT EXISTS weather_requests", self.migration)

    def test_migration_is_started_by_backend(self):
        self.assertIn("create_tables()", self.backend)
        self.assertIn("001_unified_hourly_weather.sql", self.backend)


if __name__ == "__main__":
    unittest.main()
