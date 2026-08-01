import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class ArchitectureContractTests(unittest.TestCase):
    def setUp(self):
        self.backend = (ROOT / "backend-service" / "app.py").read_text(encoding="utf-8")
        self.provider = (ROOT / "provider-service" / "app.py").read_text(encoding="utf-8")
        self.provider_requirements = (
            ROOT / "provider-service" / "requirements.txt"
        ).read_text(encoding="utf-8")
        compose_root = ROOT / "infrastructure" / "compose"
        self.database_compose = (
            compose_root / "database-service.yml"
        ).read_text(encoding="utf-8")
        self.backend_compose = (
            compose_root / "backend-service.yml"
        ).read_text(encoding="utf-8")
        self.provider_compose = (
            compose_root / "provider-service.yml"
        ).read_text(encoding="utf-8")
        self.ui_compose = (
            compose_root / "ui-service.yml"
        ).read_text(encoding="utf-8")

    def test_compose_exposes_required_local_ports(self):
        self.assertIn('"5432:5432"', self.database_compose)
        self.assertIn('"6379:6379"', self.database_compose)
        self.assertIn('"5672:5672"', self.database_compose)
        self.assertIn('"15672:15672"', self.database_compose)
        self.assertIn('"5001:5001"', self.backend_compose)
        self.assertIn('"5002:5002"', self.provider_compose)
        self.assertIn('"5000:5000"', self.ui_compose)

    def test_provider_has_no_database_access_or_sql(self):
        combined = f"{self.provider}\n{self.provider_requirements}".lower()
        for forbidden in (
            "psycopg",
            "database_url",
            "select ",
            "insert into",
            "update weather_",
            "delete from",
        ):
            self.assertNotIn(forbidden, combined)

    def test_postgres_volume_name_is_preserved(self):
        self.assertIn(
            "name: database-service_postgres_data",
            self.database_compose,
        )

    def test_provider_routes_are_present(self):
        for route in (
            '/health',
            '/weather/current',
            '/weather/forecast',
            '/weather/history',
        ):
            self.assertIn(route, self.provider)

    def test_backend_contains_rabbitmq_consumer(self):
        self.assertIn("start_rabbitmq_consumer", self.backend)
        self.assertIn("process_rabbitmq_message", self.backend)

    def test_history_service_directory_is_absent(self):
        self.assertFalse((ROOT / "history-service").exists())


if __name__ == "__main__":
    unittest.main()
