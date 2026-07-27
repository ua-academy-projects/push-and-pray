from pathlib import Path
from uuid import UUID, uuid4

import pytest
from httpx2 import AsyncClient
from redis.exceptions import ConnectionError as RedisConnectionError
from ui_service.main import app
from ui_service.theme.repository import RedisThemeRepository, ThemeRepositoryError
from ui_service.theme.service import DEFAULT_THEME, InvalidThemeError, ThemeService

from .conftest import FakeThemeRepository


class FakeRedis:
    def __init__(self) -> None:
        self.value: str | None = None
        self.set_calls: list[tuple[str, str, int]] = []
        self.expire_calls: list[tuple[str, int]] = []
        self.delete_calls: list[str] = []
        self.fail = False

    async def get(self, key: str) -> str | None:
        if self.fail:
            raise RedisConnectionError("unavailable")
        return self.value

    async def set(self, key: str, value: str, *, ex: int) -> None:
        if self.fail:
            raise RedisConnectionError("unavailable")
        self.value = value
        self.set_calls.append((key, value, ex))

    async def expire(self, key: str, ttl: int) -> None:
        if self.fail:
            raise RedisConnectionError("unavailable")
        self.expire_calls.append((key, ttl))

    async def delete(self, key: str) -> None:
        if self.fail:
            raise RedisConnectionError("unavailable")
        self.value = None
        self.delete_calls.append(key)

    async def ping(self) -> bool:
        if self.fail:
            raise RedisConnectionError("unavailable")
        return True

    async def aclose(self) -> None:
        return None


@pytest.mark.anyio
async def test_redis_repository_uses_exact_key_and_refreshes_ttl() -> None:
    redis = FakeRedis()
    repository = RedisThemeRepository(redis, ttl_seconds=600)  # type: ignore[arg-type]
    session_id = str(uuid4())

    await repository.set_theme(session_id, "light")
    restored = await repository.get_theme(session_id)

    assert restored == "light"
    key, value, ttl = redis.set_calls[0]
    assert key == f"theme:{session_id}"
    assert value == "light"
    assert ttl == 600
    assert redis.expire_calls == [(key, 600)]


@pytest.mark.anyio
async def test_redis_repository_uses_configured_prefix() -> None:
    redis = FakeRedis()
    repository = RedisThemeRepository(
        redis,
        prefix="aegis:theme",
        ttl_seconds=600,  # type: ignore[arg-type]
    )
    session_id = str(uuid4())

    await repository.set_theme(session_id, "light")

    assert redis.set_calls[0][0] == f"aegis:theme:{session_id}"


def test_redis_repository_rejects_empty_prefix() -> None:
    with pytest.raises(ValueError, match="prefix"):
        RedisThemeRepository(
            FakeRedis(),
            prefix="::",
            ttl_seconds=600,  # type: ignore[arg-type]
        )


@pytest.mark.anyio
async def test_unknown_redis_value_falls_back_to_dark() -> None:
    redis = FakeRedis()
    redis.value = "sepia"
    repository = RedisThemeRepository(redis, ttl_seconds=600)  # type: ignore[arg-type]

    assert await repository.get_theme(str(uuid4())) == "dark"


@pytest.mark.anyio
async def test_missing_redis_value_falls_back_to_dark() -> None:
    repository = RedisThemeRepository(
        FakeRedis(),
        ttl_seconds=600,  # type: ignore[arg-type]
    )

    assert await repository.get_theme(str(uuid4())) == "dark"


@pytest.mark.anyio
async def test_delete_theme_uses_exact_key() -> None:
    redis = FakeRedis()
    repository = RedisThemeRepository(redis, ttl_seconds=600)  # type: ignore[arg-type]
    session_id = str(uuid4())
    await repository.set_theme(session_id, "light")

    await repository.delete_theme(session_id)

    assert redis.delete_calls == [f"theme:{session_id}"]
    assert redis.value is None


@pytest.mark.anyio
@pytest.mark.parametrize("operation", ["get", "set", "delete"])
async def test_repository_maps_redis_failures_to_application_error(
    operation: str,
) -> None:
    redis = FakeRedis()
    redis.fail = True
    repository = RedisThemeRepository(redis, ttl_seconds=600)  # type: ignore[arg-type]

    with pytest.raises(ThemeRepositoryError, match="Theme storage is unavailable"):
        if operation == "get":
            await repository.get_theme(str(uuid4()))
        elif operation == "set":
            await repository.set_theme(str(uuid4()), "light")
        else:
            await repository.delete_theme(str(uuid4()))


@pytest.mark.anyio
async def test_service_returns_default_when_state_is_missing() -> None:
    repository = FakeThemeRepository()
    session_id = str(uuid4())

    assert await ThemeService(repository).load_theme(session_id) == "dark"


@pytest.mark.parametrize("theme", ["dark", "light"])
def test_service_validates_allowed_themes(theme: str) -> None:
    assert ThemeService(FakeThemeRepository()).validate_theme(theme) == theme


def test_service_rejects_unknown_theme() -> None:
    with pytest.raises(InvalidThemeError, match="dark.*light"):
        ThemeService(FakeThemeRepository()).validate_theme("sepia")


def test_service_exposes_dark_as_default() -> None:
    assert DEFAULT_THEME == "dark"
    assert ThemeService(FakeThemeRepository()).default_theme == "dark"


@pytest.mark.anyio
async def test_service_saves_validated_theme() -> None:
    repository = FakeThemeRepository()
    session_id = str(uuid4())

    assert await ThemeService(repository).save_theme(session_id, "light") == "light"
    assert repository.values[session_id] == "light"


@pytest.mark.anyio
async def test_service_rejects_invalid_theme_without_saving() -> None:
    repository = FakeThemeRepository()

    with pytest.raises(InvalidThemeError):
        await ThemeService(repository).save_theme(str(uuid4()), "sepia")

    assert repository.values == {}


@pytest.mark.anyio
async def test_service_returns_default_when_repository_load_fails() -> None:
    redis = FakeRedis()
    redis.fail = True
    repository = RedisThemeRepository(redis, ttl_seconds=600)  # type: ignore[arg-type]

    assert await ThemeService(repository).load_theme(str(uuid4())) == "dark"


@pytest.mark.anyio
async def test_service_does_not_expose_repository_save_failure() -> None:
    redis = FakeRedis()
    redis.fail = True
    repository = RedisThemeRepository(redis, ttl_seconds=600)  # type: ignore[arg-type]

    assert await ThemeService(repository).save_theme(str(uuid4()), "light") == "light"


@pytest.mark.anyio
async def test_missing_cookie_creates_an_opaque_session_id(
    client: AsyncClient,
) -> None:
    assert "theme_session" not in client.cookies

    response = await client.get("/")
    session_id = client.cookies["theme_session"]

    assert len(session_id) == 36
    assert "HttpOnly" in response.headers["set-cookie"]
    assert UUID(session_id).version == 4
    assert "dark" not in response.headers["set-cookie"].lower()
    assert "light" not in response.headers["set-cookie"].lower()


@pytest.mark.anyio
async def test_https_session_cookie_is_secure(client: AsyncClient) -> None:
    response = await client.get("https://test/theme")

    assert "Secure" in response.headers["set-cookie"]


@pytest.mark.anyio
async def test_invalid_session_cookie_is_replaced_with_uuid4(
    client: AsyncClient,
) -> None:
    client.cookies.set("theme_session", "not-a-session-id")

    response = await client.get("/theme")
    replacement = UUID(response.cookies["theme_session"])

    assert replacement.version == 4


def test_session_generation_does_not_use_network_fingerprints() -> None:
    source = (
        Path(__file__).parents[1] / "src" / "ui_service" / "theme" / "http.py"
    ).read_text(encoding="utf-8")

    assert "client.host" not in source
    assert "user-agent" not in source.lower()


@pytest.mark.anyio
async def test_theme_persists_across_requests(
    client: AsyncClient, theme_repository: FakeThemeRepository
) -> None:
    initial = await client.get("/")
    session_id = client.cookies["theme_session"]
    assert '<html lang="en" data-theme="dark">' in initial.text

    changed = await client.post(
        "/theme",
        data={"theme": "light"},
        headers={"Referer": "http://test/blacklist?page=2"},
        follow_redirects=False,
    )
    restored = await client.get("/")
    refreshed = await client.get("/")

    assert changed.status_code == 303
    assert changed.headers["location"] == "/blacklist?page=2"
    assert theme_repository.values[session_id] == "light"
    assert '<html lang="en" data-theme="light">' in restored.text
    assert '<html lang="en" data-theme="light">' in refreshed.text
    assert client.cookies["theme_session"] == session_id


@pytest.mark.anyio
async def test_browser_sessions_have_independent_themes(
    client: AsyncClient, theme_repository: FakeThemeRepository
) -> None:
    await client.get("/")
    first_session = client.cookies["theme_session"]
    await client.post("/theme", data={"theme": "light"})

    client.cookies.clear()
    second = await client.get("/")
    second_session = client.cookies["theme_session"]

    assert first_session != second_session
    assert theme_repository.values[first_session] == "light"
    assert '<html lang="en" data-theme="dark">' in second.text


@pytest.mark.anyio
async def test_invalid_theme_is_rejected(client: AsyncClient) -> None:
    response = await client.post(
        "/theme",
        data={"theme": "sepia"},
        follow_redirects=False,
    )

    assert response.status_code == 400


@pytest.mark.anyio
async def test_missing_theme_is_rejected_with_400(client: AsyncClient) -> None:
    response = await client.post("/theme", data={}, follow_redirects=False)

    assert response.status_code == 400


@pytest.mark.anyio
async def test_get_theme_returns_current_theme(client: AsyncClient) -> None:
    first = await client.get("/theme")
    await client.post("/theme", data={"theme": "light"})
    restored = await client.get("/theme")

    assert first.json() == {"theme": "dark"}
    assert restored.json() == {"theme": "light"}


@pytest.mark.anyio
async def test_missing_cookie_on_get_theme_creates_uuid4_session(
    client: AsyncClient,
) -> None:
    assert "theme_session" not in client.cookies

    response = await client.get("/theme")

    assert response.json() == {"theme": "dark"}
    assert UUID(client.cookies["theme_session"]).version == 4


@pytest.mark.anyio
async def test_dark_to_light_to_dark_regression(client: AsyncClient) -> None:
    assert (await client.get("/theme")).json() == {"theme": "dark"}

    light = await client.post("/theme", data={"theme": "light"}, follow_redirects=False)
    assert light.status_code == 303
    assert (await client.get("/theme")).json() == {"theme": "light"}

    dark = await client.post("/theme", data={"theme": "dark"}, follow_redirects=False)
    assert dark.status_code == 303
    assert (await client.get("/theme")).json() == {"theme": "dark"}


@pytest.mark.anyio
async def test_redis_unavailable_does_not_break_theme_endpoints(
    client: AsyncClient,
) -> None:
    redis = FakeRedis()
    redis.fail = True
    repository = RedisThemeRepository(redis, ttl_seconds=600)  # type: ignore[arg-type]
    app.state.theme_service = ThemeService(repository)

    loaded = await client.get("/theme")
    saved = await client.post("/theme", data={"theme": "light"}, follow_redirects=False)
    rendered = await client.get("/")

    assert loaded.status_code == 200
    assert loaded.json() == {"theme": "dark"}
    assert saved.status_code == 303
    assert '<html lang="en" data-theme="dark">' in rendered.text
    assert "unavailable" not in loaded.text.lower()


@pytest.mark.anyio
async def test_post_theme_rejects_external_referer_redirect(
    client: AsyncClient,
) -> None:
    response = await client.post(
        "/theme",
        data={"theme": "light"},
        headers={"Referer": "https://attacker.example/phishing"},
        follow_redirects=False,
    )

    assert response.status_code == 303
    assert response.headers["location"] == "/"


@pytest.mark.anyio
async def test_toggle_icon_and_accessible_label_follow_current_theme(
    client: AsyncClient,
) -> None:
    dark_page = await client.get("/")

    assert '<span aria-hidden="true">🌙</span>' in dark_page.text
    assert 'aria-label="Switch to light theme"' in dark_page.text
    assert 'name="theme" value="light"' in dark_page.text

    await client.post(
        "/theme",
        data={"theme": "light"},
        headers={"Referer": "http://test/"},
        follow_redirects=False,
    )
    light_page = await client.get("/")

    assert '<span aria-hidden="true">☀</span>' in light_page.text
    assert 'aria-label="Switch to dark theme"' in light_page.text
    assert 'name="theme" value="dark"' in light_page.text


@pytest.mark.anyio
@pytest.mark.parametrize(
    ("method", "path", "data"),
    [
        ("GET", "/", None),
        ("GET", "/blacklist", None),
        ("POST", "/", {"ip_address": "", "max_age_days": "30"}),
    ],
)
async def test_every_rendered_page_receives_theme(
    client: AsyncClient,
    method: str,
    path: str,
    data: dict[str, str] | None,
) -> None:
    await client.get("/")
    await client.post("/theme", data={"theme": "light"})

    response = await client.request(method, path, data=data)

    assert response.status_code == 200
    assert '<html lang="en" data-theme="light">' in response.text


def test_jinja_rendering_uses_one_theme_injection_path() -> None:
    routes_source = (
        Path(__file__).parents[1] / "src" / "ui_service" / "routes.py"
    ).read_text(encoding="utf-8")
    templates_directory = Path(__file__).parents[1] / "src" / "ui_service" / "templates"

    assert routes_source.count("templates.TemplateResponse(") == 1
    for template in templates_directory.glob("*.html"):
        source = template.read_text(encoding="utf-8")
        if not template.name.startswith("_"):
            assert '<html lang="en" data-theme="{{ theme }}">' in source
        assert "redis" not in source.lower()
