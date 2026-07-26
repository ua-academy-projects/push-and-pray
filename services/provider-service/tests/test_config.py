import pytest
from provider_service.config import SERVICE_ENV_FILE, Settings
from pydantic import ValidationError


def test_api_key_is_required_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("ABUSEIPDB_API_KEY", raising=False)

    with pytest.raises(ValidationError):
        Settings(_env_file=None)

    monkeypatch.setenv("ABUSEIPDB_API_KEY", "environment-secret")
    settings = Settings(_env_file=None)

    assert settings.abuseipdb_api_key.get_secret_value() == "environment-secret"
    assert "environment-secret" not in repr(settings)


def test_abuseipdb_base_url_must_use_https() -> None:
    with pytest.raises(ValidationError, match="must use HTTPS"):
        Settings(
            _env_file=None,
            abuseipdb_api_key="test-key",
            abuseipdb_base_url="http://api.abuseipdb.test",
        )


def test_provider_env_file_is_absolute_and_service_local() -> None:
    assert SERVICE_ENV_FILE.is_absolute()
    assert SERVICE_ENV_FILE == Settings.model_config["env_file"]
    assert SERVICE_ENV_FILE.parent.name == "provider-service"


def test_blacklist_worker_is_disabled_by_default() -> None:
    settings = Settings(_env_file=None, abuseipdb_api_key="test-key")

    assert settings.blacklist_polling_enabled is False
    assert settings.blacklist_poll_interval_seconds == 21600
    assert settings.blacklist_confidence_minimum == 90


def test_enabled_worker_does_not_require_obsolete_history_http_settings(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    for name in (
        "HISTORY_SERVICE_URL",
        "HISTORY_INGESTION_TOKEN",
        "HISTORY_CONNECT_TIMEOUT_SECONDS",
        "HISTORY_READ_TIMEOUT_SECONDS",
        "HISTORY_WRITE_TIMEOUT_SECONDS",
        "HISTORY_POOL_TIMEOUT_SECONDS",
        "HISTORY_OPERATION_TIMEOUT_SECONDS",
        "HISTORY_DELIVERY_RETRY_INITIAL_SECONDS",
        "HISTORY_DELIVERY_RETRY_MAXIMUM_SECONDS",
    ):
        monkeypatch.delenv(name, raising=False)

    settings = Settings(
        _env_file=None,
        abuseipdb_api_key="test-key",
        blacklist_polling_enabled=True,
    )

    assert settings.blacklist_polling_enabled is True
    assert not hasattr(settings, "history_service_url")
    assert not hasattr(settings, "history_ingestion_token")
    assert settings.rabbitmq_publish_retry_initial_seconds == 30
    assert settings.rabbitmq_publish_retry_maximum_seconds == 900


def test_rabbitmq_settings_load_from_environment(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("RABBITMQ_HOST", "rabbitmq.internal")
    monkeypatch.setenv("RABBITMQ_PORT", "5673")
    monkeypatch.setenv("RABBITMQ_VIRTUAL_HOST", "aegis")
    monkeypatch.setenv("RABBITMQ_USERNAME", "provider")
    monkeypatch.setenv("RABBITMQ_PASSWORD", "publisher-secret")
    monkeypatch.setenv("RABBITMQ_EXCHANGE_NAME", "snapshots")
    monkeypatch.setenv("RABBITMQ_ROUTING_KEY", "snapshots.complete")
    monkeypatch.setenv("RABBITMQ_CONNECTION_TIMEOUT_SECONDS", "7")
    monkeypatch.setenv("RABBITMQ_PUBLISH_TIMEOUT_SECONDS", "8")

    settings = Settings(_env_file=None, abuseipdb_api_key="test-key")

    assert settings.rabbitmq_host == "rabbitmq.internal"
    assert settings.rabbitmq_port == 5673
    assert settings.rabbitmq_virtual_host == "aegis"
    assert settings.rabbitmq_username == "provider"
    assert settings.rabbitmq_exchange_name == "snapshots"
    assert settings.rabbitmq_routing_key == "snapshots.complete"
    assert settings.rabbitmq_connection_timeout_seconds == 7
    assert settings.rabbitmq_publish_timeout_seconds == 8
    assert settings.rabbitmq_password.get_secret_value() == "publisher-secret"
    assert "publisher-secret" not in repr(settings)
    assert "publisher-secret" not in str(settings.model_dump(mode="json"))
