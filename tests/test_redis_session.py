import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class RedisSessionTests(unittest.TestCase):
    def setUp(self):
        self.ui_app_code = (ROOT / "ui-service" / "app.py").read_text(encoding="utf-8")
        self.script_code = (ROOT / "ui-service" / "static" / "script.js").read_text(encoding="utf-8")

    def test_session_cookie_and_redis_endpoints_in_ui_app(self):
        self.assertIn("SESSION_COOKIE_NAME", self.ui_app_code)
        self.assertIn("REDIS_URL", self.ui_app_code)
        self.assertIn('@app.get("/api/session")', self.ui_app_code)
        self.assertIn('@app.post("/api/session")', self.ui_app_code)

    def test_script_fetches_and_saves_session_state(self):
        self.assertIn("fetchSessionState", self.script_code)
        self.assertIn("saveSessionState", self.script_code)
        self.assertIn("/api/session", self.script_code)

if __name__ == "__main__":
    unittest.main()
