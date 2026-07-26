import pytest
from history_service.config import SERVICE_ENV_FILE, Settings


def test_database_url_escapes_credentials_and_targets_mariadb() -> None:
    settings = Settings(
        _env_file=None,
        mariadb_database="aegis_history",
        mariadb_user="history@service",
        mariadb_password="secret:/value",
    )

    url = settings.database_url()

    assert url.drivername == "mariadb+pymysql"
    assert url.database == "aegis_history"
    assert url.render_as_string(hide_password=True).startswith(
        "mariadb+pymysql://history%40service:***@"
    )
    assert settings.mariadb_password.get_secret_value() == "secret:/value"
    assert "secret:/value" not in repr(settings)


def test_history_env_file_is_absolute_and_service_local() -> None:
    assert SERVICE_ENV_FILE.is_absolute()
    assert SERVICE_ENV_FILE == Settings.model_config["env_file"]
    assert SERVICE_ENV_FILE.parent.name == "history-service"


def test_provider_configuration_is_separate_from_database_credentials() -> None:
    settings = Settings(
        mariadb_database="aegis_history",
        mariadb_user="history",
        mariadb_password="secret",
        provider_service_url="http://provider.test",
        provider_connect_timeout_seconds=1,
        provider_read_timeout_seconds=2,
        provider_write_timeout_seconds=3,
        provider_pool_timeout_seconds=4,
    )

    assert str(settings.provider_service_url) == "http://provider.test/"
    assert settings.provider_connect_timeout_seconds == 1
    assert settings.provider_read_timeout_seconds == 2
    assert settings.provider_write_timeout_seconds == 3
    assert settings.provider_pool_timeout_seconds == 4


def test_history_keeps_only_read_side_blacklist_configuration() -> None:
    settings = Settings(
        _env_file=None,
        mariadb_database="aegis_history",
        mariadb_user="history",
        mariadb_password="secret",
    )

    assert settings.blacklist_stale_after_seconds == 43200
    assert not hasattr(settings, "blacklist_scheduler_enabled")
    assert not hasattr(settings, "blacklist_sync_interval_seconds")
    assert not hasattr(settings, "provider_ingestion_token")


def test_startup_does_not_require_obsolete_ingestion_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("PROVIDER_INGESTION_TOKEN", raising=False)

    settings = Settings(
        _env_file=None,
        mariadb_database="aegis_history",
        mariadb_user="history",
        mariadb_password="secret",
    )

    assert not hasattr(settings, "provider_ingestion_token")


def test_rabbitmq_settings_load_from_environment(monkeypatch) -> None:
    monkeypatch.setenv("RABBITMQ_HOST", "rabbitmq.internal")
    monkeypatch.setenv("RABBITMQ_PORT", "5673")
    monkeypatch.setenv("RABBITMQ_VIRTUAL_HOST", "aegis")
    monkeypatch.setenv("RABBITMQ_USERNAME", "history")
    monkeypatch.setenv("RABBITMQ_PASSWORD", "consumer-secret")
    monkeypatch.setenv("RABBITMQ_EXCHANGE_NAME", "snapshots")
    monkeypatch.setenv("RABBITMQ_QUEUE_NAME", "history-snapshots")
    monkeypatch.setenv("RABBITMQ_ROUTING_KEY", "snapshots.complete")
    monkeypatch.setenv("RABBITMQ_PREFETCH_COUNT", "3")
    monkeypatch.setenv("RABBITMQ_CONNECTION_TIMEOUT_SECONDS", "7")

    settings = Settings(
        _env_file=None,
        mariadb_database="aegis_history",
        mariadb_user="history",
        mariadb_password="database-secret",
    )

    assert settings.rabbitmq_host == "rabbitmq.internal"
    assert settings.rabbitmq_port == 5673
    assert settings.rabbitmq_virtual_host == "aegis"
    assert settings.rabbitmq_username == "history"
    assert settings.rabbitmq_exchange_name == "snapshots"
    assert settings.rabbitmq_queue_name == "history-snapshots"
    assert settings.rabbitmq_routing_key == "snapshots.complete"
    assert settings.rabbitmq_prefetch_count == 3
    assert settings.rabbitmq_connection_timeout_seconds == 7
    assert settings.rabbitmq_password.get_secret_value() == "consumer-secret"
    assert "consumer-secret" not in repr(settings)
    assert "consumer-secret" not in str(settings.model_dump(mode="json"))
