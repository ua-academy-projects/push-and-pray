# UI Service

The UI service renders the manual-check and blacklist pages with Jinja2.
Browsers communicate with UI, and UI communicates only with History Service's
application API.

Runtime boundaries:

```text
Browser -> UI -> History
Browser cookie -> UI -> Redis
```

Redis stores only an expiring `light` or `dark` value under the anonymous
browser session key. The browser cookie contains only a random session ID;
theme preferences are never stored in MariaDB. `ThemeService` owns preference
behavior and accesses Redis exclusively through the UI-local `ThemeRepository`
interface.

## Configuration

Create the service-local file from the repository root:

```bash
cp services/ui-service/.env.example services/ui-service/.env
```

The UI loads that file explicitly regardless of the current working directory:

```dotenv
HISTORY_SERVICE_URL=http://127.0.0.1:8002
HISTORY_CONNECT_TIMEOUT_SECONDS=3
HISTORY_READ_TIMEOUT_SECONDS=5
HISTORY_WRITE_TIMEOUT_SECONDS=5
HISTORY_POOL_TIMEOUT_SECONDS=3
HISTORY_OPERATION_TIMEOUT_SECONDS=10
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_DB=0
REDIS_USERNAME=
REDIS_PASSWORD=
REDIS_THEME_PREFIX=theme
REDIS_THEME_TTL_SECONDS=2592000
REDIS_CONNECTION_TIMEOUT_SECONDS=3
UI_SESSION_COOKIE_NAME=theme_session
UI_SESSION_COOKIE_SECURE=false
```

Install the locked workspace and run from the repository root:

```bash
uv sync --locked --all-packages --all-extras
.venv/bin/uvicorn ui_service.main:app \
  --app-dir services/ui-service/src \
  --host 127.0.0.1 \
  --port 8000
```

UI reuses one lifecycle-owned HTTPX client for all History requests and closes
it during application shutdown.

The manual-check page is available at `http://127.0.0.1:8000/`, and the tabular
blacklist page is available at `http://127.0.0.1:8000/blacklist`. Charts and
analytical dashboards are outside the current scope. The UI contains no
AbuseIPDB, Provider Service, or database configuration.

## Theme routes

- `GET /theme` returns the current anonymous session theme as
  `{"theme": "dark"}` or `{"theme": "light"}`.
- `POST /theme` accepts the HTML form field `theme=dark` or `theme=light`,
  stores it in Redis, and responds with `303 See Other` to the same-origin
  `Referer`. A missing or invalid value returns HTTP 400.

Both routes create or refresh the opaque session cookie. No JavaScript is
required for theme switching.

## Anonymous theme-session lifecycle

1. When `theme_session` is absent or is not a UUID4, UI generates a new UUID4.
2. The browser receives only that identifier in the `theme_session` cookie.
   The cookie is `HttpOnly`, `SameSite=Lax`, and is also `Secure` for HTTPS
   requests or when `UI_SESSION_COOKIE_SECURE=true`.
3. Theme state is stored separately in Redis under `theme:<session UUID>`.
   Neither the client IP address nor User-Agent participates in session
   creation or lookup.
4. Rendering and theme-route activity refreshes the cookie lifetime; reading an
   existing Redis value refreshes its inactivity TTL.
5. When the cookie or Redis key expires, the next request starts from the
   default dark theme and receives a new cookie when necessary.

The UI creates one Redis `ConnectionPool` during application lifespan setup.
The pool opens network connections lazily on the first Redis command and
reuses them across requests. UI readiness calls Redis `PING`; a failed ping
returns not-ready without exposing connection details. Graceful application
shutdown closes the Redis client and its owned pool.

The blacklist page polls UI Service's same-origin `/blacklist/status` endpoint
every 30 seconds. UI Service reads status from History Service, which reads
MariaDB. The browser reloads the page only when `latest_snapshot_id` changes;
unchanged snapshots and temporary polling errors leave the displayed table in
place. Polling pauses while the document is hidden. It never calls Provider
Service, triggers synchronization, or consumes AbuseIPDB quota.

Route tests replace the application client and make no live service calls:

```bash
.venv/bin/pytest services/ui-service/tests
```
