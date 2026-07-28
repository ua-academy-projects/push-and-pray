import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class UiDataFlowTests(unittest.TestCase):
    def setUp(self):
        self.script = (ROOT / "ui-service" / "static" / "script.js").read_text(
            encoding="utf-8"
        )
        self.ui_app = (ROOT / "ui-service" / "app.py").read_text(
            encoding="utf-8"
        )
        self.html = (ROOT / "ui-service" / "templates" / "index.html").read_text(
            encoding="utf-8"
        )

    def test_browser_code_has_no_external_weather_url(self):
        lowered = self.script.lower()
        self.assertNotIn("open-meteo", lowered)
        self.assertNotIn("openweathermap", lowered)

    def test_browser_uses_only_relative_ui_api_routes(self):
        for route in ("/api/weather", "/api/forecast", "/api/history"):
            self.assertIn(route, self.script)
            self.assertIn(route, self.ui_app)

    def test_ui_proxy_has_only_backend_dependency(self):
        self.assertIn("BACKEND_URL", self.ui_app)
        self.assertNotIn("PROVIDER_URL", self.ui_app)
        self.assertNotIn("DATABASE_URL", self.ui_app)

    def test_chart_and_table_share_history_points(self):
        self.assertIn("getHistoryPoints", self.script)
        self.assertIn("renderHistoryTable", self.script)

    def test_reusable_chart_renderer_is_present(self):
        self.assertIn("function renderChart(", self.script)
        self.assertGreaterEqual(self.script.count("renderChart("), 2)

    def test_history_switch_and_custom_tooltips_exist(self):
        self.assertIn('data-hours="24"', self.html)
        self.assertIn('data-hours="168"', self.html)
        self.assertIn("chart-container", self.html)


if __name__ == "__main__":
    unittest.main()
