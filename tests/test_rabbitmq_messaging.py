import importlib.util
import json
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]

# Load backend app in isolation via importlib.util
spec_backend = importlib.util.spec_from_file_location("backend_app_mq", ROOT / "backend-service" / "app.py")
backend = importlib.util.module_from_spec(spec_backend)
spec_backend.loader.exec_module(backend)

# Load provider app in isolation via importlib.util
spec_provider = importlib.util.spec_from_file_location("provider_app_mq", ROOT / "provider-service" / "app.py")
provider = importlib.util.module_from_spec(spec_provider)
spec_provider.loader.exec_module(provider)


class RabbitMQMessagingContractTests(unittest.TestCase):
    def test_provider_and_backend_rabbitmq_config(self):
        self.assertTrue(hasattr(provider, "publish_to_rabbitmq"))
        self.assertTrue(hasattr(backend, "start_rabbitmq_consumer"))
        self.assertTrue(hasattr(backend, "process_rabbitmq_message"))


class RabbitMQConsumerAckNackTests(unittest.TestCase):
    def setUp(self):
        self.ch = MagicMock()
        self.method = MagicMock()
        self.method.delivery_tag = 42
        self.properties = MagicMock()

    def valid_payload(self):
        return json.dumps({
            "type": "forecast",
            "data": {
                "hourly": {
                    "time": [1785236400 + i * 3600 for i in range(24)],
                    "temperature_2m": [20.0] * 24,
                },
                "source": "test",
            },
        }).encode("utf-8")

    def test_successful_processing_calls_basic_ack(self):
        payload = self.valid_payload()

        with patch.object(backend, "get_connection") as mock_conn:
            mock_conn.return_value.__enter__.return_value = MagicMock()
            backend.process_rabbitmq_message(self.ch, self.method, self.properties, payload)

        self.ch.basic_ack.assert_called_once_with(delivery_tag=42)
        self.ch.basic_nack.assert_not_called()

    def test_database_error_calls_basic_nack_requeue_true(self):
        payload = self.valid_payload()

        with patch.object(backend, "get_connection", side_effect=Exception("Database connection timeout")):
            backend.process_rabbitmq_message(self.ch, self.method, self.properties, payload)

        self.ch.basic_nack.assert_called_once_with(delivery_tag=42, requeue=True)
        self.ch.basic_ack.assert_not_called()

    def test_invalid_message_calls_basic_nack_requeue_false(self):
        invalid_json = b"NOT_VALID_JSON_STRING"

        backend.process_rabbitmq_message(self.ch, self.method, self.properties, invalid_json)

        self.ch.basic_nack.assert_called_once_with(delivery_tag=42, requeue=False)
        self.ch.basic_ack.assert_not_called()

    def test_no_basic_ack_after_basic_nack(self):
        invalid_payload = json.dumps({"type": "unknown_type", "data": {}}).encode("utf-8")

        backend.process_rabbitmq_message(self.ch, self.method, self.properties, invalid_payload)

        self.ch.basic_nack.assert_called_once_with(delivery_tag=42, requeue=False)
        self.ch.basic_ack.assert_not_called()


if __name__ == "__main__":
    unittest.main()
