import importlib.util
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]

spec = importlib.util.spec_from_file_location("ui_app_test", ROOT / "ui-service" / "app.py")
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)


class UiProxyTests(unittest.TestCase):
    def response(self):
        response = Mock()
        response.status_code = 200
        response.json.return_value = {"ok": True}
        return response

    def test_history_query_is_forwarded_to_backend(self):
        with patch.object(ui.requests, "get", return_value=self.response()) as backend:
            response = ui.app.test_client().get("/api/history?hours=168")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(backend.call_args.kwargs["params"].get("hours"), "168")
        self.assertTrue(backend.call_args.args[0].endswith("/api/history"))

    def test_forecast_uses_backend_route(self):
        with patch.object(ui.requests, "get", return_value=self.response()) as backend:
            response = ui.app.test_client().get("/api/forecast")

        self.assertEqual(response.status_code, 200)
        self.assertTrue(backend.call_args.args[0].endswith("/api/forecast"))


if __name__ == "__main__":
    unittest.main()
