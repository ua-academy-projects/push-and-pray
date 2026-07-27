import pytest
from pydantic import ValidationError
from ui_service.config import SERVICE_ENV_FILE, Settings


def test_ui_env_file_is_absolute_and_service_local() -> None:
    assert SERVICE_ENV_FILE.is_absolute()
    assert SERVICE_ENV_FILE == Settings.model_config["env_file"]
    assert SERVICE_ENV_FILE.parent.name == "ui-service"


def test_default_theme_cookie_name_is_stable() -> None:
    assert Settings(_env_file=None).ui_session_cookie_name == "theme_session"


def test_ui_targets_history_service() -> None:
    settings = Settings(
        history_service_url="http://history.test",
        history_connect_timeout_seconds=1,
        history_read_timeout_seconds=2,
        history_write_timeout_seconds=3,
        history_pool_timeout_seconds=4,
        history_operation_timeout_seconds=5,
    )

    assert str(settings.history_service_url) == "http://history.test/"
    assert settings.history_connect_timeout_seconds == 1
    assert settings.history_read_timeout_seconds == 2
    assert settings.history_write_timeout_seconds == 3
    assert settings.history_pool_timeout_seconds == 4
    assert settings.history_operation_timeout_seconds == 5


def test_ui_accepts_redis_configuration_without_exposing_password() -> None:
    settings = Settings(
        redis_host="redis.test",
        redis_port=6380,
        redis_db=2,
        redis_username="ui",
        redis_password="not-a-real-secret",
        redis_theme_prefix="ui-theme",
        redis_theme_ttl_seconds=600,
        redis_connection_timeout_seconds=2,
        ui_session_cookie_name="ui_session",
        ui_session_cookie_secure=True,
    )

    assert settings.redis_host == "redis.test"
    assert settings.redis_port == 6380
    assert settings.redis_db == 2
    assert settings.redis_password is not None
    assert settings.redis_password.get_secret_value() == "not-a-real-secret"
    assert "not-a-real-secret" not in repr(settings)
    assert settings.redis_theme_prefix == "ui-theme"
    assert settings.redis_theme_ttl_seconds == 600
    assert settings.ui_session_cookie_secure is True


def test_redis_theme_prefix_is_normalized() -> None:
    assert Settings(
        _env_file=None, redis_theme_prefix=" aegis:theme: "
    ).redis_theme_prefix == ("aegis:theme")


def test_empty_redis_theme_prefix_is_rejected() -> None:
    with pytest.raises(ValidationError):
        Settings(_env_file=None, redis_theme_prefix="::")
