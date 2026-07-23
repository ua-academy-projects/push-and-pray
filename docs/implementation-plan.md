# SkyIvano — Implementation Plan

Four stages. Each stage is implemented, tested, and reported on before the next begins — see `docs/project-status.md` for live progress and `docs/prompts/` for the self-contained agent prompt for each stage. Full contracts/schema live in `docs/architecture.md`; this file is the work breakdown only.

## Stage 1 — Foundation and database

**Goal**: A working PostgreSQL schema, nothing else. No API endpoints yet.

**Scope**: Repository skeleton (already done in Stage 0), History Service configuration, SQLAlchemy 2 models for all 5 tables, Alembic setup + initial migration, database-level constraints/indexes, basic model/DB tests.

**Main tasks**:
- `history-service/app/config.py` reading `DATABASE_URL`, `DATABASE_ECHO`, `DATABASE_POOL_SIZE`, `DATABASE_MAX_OVERFLOW`.
- `history-service/app/database/base.py` (declarative base) and `session.py` (engine + session factory).
- `history-service/app/models/{location,current_weather,daily_weather,hourly_weather,weather_sync}.py` with the fields and unique constraints from `docs/architecture.md` §8.
- `alembic.ini` + `alembic/env.py` wired to the models' metadata; one initial migration creating all tables, constraints, and indexes.
- `history-service/tests/` — model-level tests: create/query a location, verify unique constraints raise on duplicates (e.g. two locations with the same coordinates, two daily rows for the same location+date).

**Files/areas affected**: `history-service/app/config.py`, `app/database/`, `app/models/`, `alembic/`, `alembic.ini`, `requirements.txt`, `tests/`.

**Dependencies**: none (first stage).

**Tests**: pytest against a real local PostgreSQL test database (no SQLite).

**Verification commands**:
```bash
cd history-service
alembic upgrade head
psql "$DATABASE_URL" -c '\d current_weather'   # inspect constraints
DATABASE_URL=postgresql+psycopg://skyivano:skyivano@localhost:5432/skyivano_test pytest
```

**Acceptance criteria**: connection is configurable via env; migration runs cleanly on an empty database; unique constraints exist and are proven by a failing-insert test; no SQLite anywhere; tests pass.

**Documentation updates**: `docs/project-status.md` (Stage 1 checklist), `docs/troubleshooting.md` if any real issues came up.

---

## Stage 2 — History Service

**Goal**: A fully functional History Service API, runnable on its own.

**Scope**: FastAPI app, Pydantic request/response schemas, DB session dependency, transactional persistence service, all read endpoints, sync-record endpoints, health check.

**Main tasks**:
- `app/schemas/` — Pydantic models for the `PUT /internal/weather` request and all response shapes.
- `app/services/persistence_service.py` — find-or-create location, upsert current/daily/hourly (`INSERT ... ON CONFLICT DO UPDATE`), record sync success, all in one transaction with rollback on failure.
- `app/services/weather_query_service.py` — latest/history/hourly read queries.
- `app/api/weather.py` — `PUT /internal/weather`, `GET /internal/weather/latest`, `GET /internal/weather/history`, `GET /internal/weather/hourly`.
- `app/api/syncs.py` — `POST /internal/syncs/failure`, `GET /internal/syncs` (+ optional start/success/failure-by-id lifecycle endpoints if they simplify rather than complicate).
- `app/api/health.py` — `GET /health` with a real DB connectivity check.
- `app/main.py` wiring routers.

**Files/areas affected**: `history-service/app/api/`, `app/schemas/`, `app/services/`, `app/main.py`, `tests/`.

**Dependencies**: Stage 1 (models + migration).

**Tests**: insert/upsert for current/daily/hourly, no-duplicate proof, rollback on invalid data, history ordering, `days` parameter validation, sync success/failure recording, health check reflects real DB state.

**Verification commands**:
```bash
cd history-service
uvicorn app.main:app --reload --port 8001
curl -X PUT localhost:8001/internal/weather -H 'Content-Type: application/json' -d @tests/fixtures/sample_payload.json
curl localhost:8001/internal/weather/latest
pytest
```

**Acceptance criteria**: service starts standalone; a `PUT` followed by a `GET /latest` round-trips correctly; repeating the same `PUT` does not create duplicate rows (verified by row count); a failed persistence attempt rolls back and old data survives; tests pass.

**Documentation updates**: `docs/project-status.md`, `docs/architecture.md` only if the implemented contract diverges from what's documented, `docs/troubleshooting.md` for real issues.

---

## Stage 3 — Backend Service and scheduler

**Goal**: A fully functional Backend Service, talking to a running History Service, with working scheduled + manual synchronization and all public read endpoints.

**Scope**: Open-Meteo client, normalization layer, History Service HTTP client, sync/read/freshness services, APScheduler wiring, internal + public endpoints, health check.

**Main tasks**:
- `app/config.py` reading all backend env vars from `docs/architecture.md` §10.
- `app/clients/open_meteo_client.py` — httpx client with configurable timeout; raises typed exceptions for timeout/connection/non-2xx/invalid-JSON.
- `app/normalization/open_meteo_normalizer.py` — validates required fields, checks array-length consistency, converts to the internal schema; isolates every Open-Meteo-specific field name here.
- `app/clients/history_service_client.py` — httpx client for `PUT`/`GET` calls to the History Service, with typed exceptions for timeout/unavailable.
- `app/services/weather_sync_service.py` — the single `run_weather_sync(trigger_type)` function: lock check → fetch → normalize → persist → record outcome. Callable from scheduler, internal endpoint, and (future) cron/K8s CronJob.
- `app/services/weather_read_service.py` + `freshness_service.py` — assemble `GET /api/weather` responses and compute `is_stale`/`stale_reason`.
- `app/scheduler/weather_scheduler.py` — APScheduler config only (interval job + startup check), no business logic.
- `app/api/internal_weather.py` — `POST /internal/weather/sync`, `GET /internal/scheduler/status`.
- `app/api/public_weather.py` — `GET /api/weather`, `/api/weather/history`, `/api/weather/hourly`, `/api/sync-status`.
- `app/api/health.py` — `GET /api/health`.

**Files/areas affected**: `backend-service/app/**`, `tests/`.

**Dependencies**: Stage 2 (a working History Service to call, mocked in tests).

**Tests**: successful/timeout/connection-failure/non-2xx/invalid-JSON/missing-fields/inconsistent-array Open-Meteo responses; normalization correctness; successful/timeout/unavailable History Service persistence; failed-sync recording; scheduler startup enabled/disabled; startup sync skipped when recent data exists; overlapping sync prevention; public GET endpoints proven to never call Open-Meteo (mock asserts zero calls); stale-data calculation; no-data response shape.

**Verification commands**:
```bash
cd backend-service
uvicorn app.main:app --reload --port 8000   # with history-service already running
curl -X POST localhost:8000/internal/weather/sync
curl localhost:8000/api/weather
curl localhost:8000/api/sync-status
pytest
```

**Acceptance criteria**: scheduler runs independently of any UI/browser activity; manual endpoint rejects overlap; public endpoints return persisted data and never touch Open-Meteo; stale data is clearly flagged; a forced Open-Meteo failure leaves prior data intact and visible; tests pass.

**Documentation updates**: `docs/project-status.md`, `docs/architecture.md` if contracts changed, `docs/troubleshooting.md` for real issues.

---

## Stage 4 — UI Service and final integration

**Goal**: A polished, working dashboard, and a verified full local stack.

**Scope**: Vite React/TS app, API client, all display components, dynamic weather styling, loading/empty/stale/error states, accessibility pass, tests, final end-to-end manual check.

**Main tasks**:
- `src/api/weatherApi.ts` — thin fetch wrapper around `VITE_BACKEND_BASE_URL`, calling only `/api/*`.
- `src/types/weather.ts`, `src/utils/weatherCode.ts` (centralized WMO code → description/icon/theme mapping), `dateFormat.ts`, `windDirection.ts`.
- `src/hooks/useWeather.ts` — fetch on mount, poll on one clearly-named short interval constant (60 seconds) so a successful scheduled sync reaches the screen automatically, expose loading/error/data/stale state. Keeps a `reload()` re-fetch function available but not currently wired to a visible control.
- Components: `Header`, `CurrentWeatherCard`, `WeatherMetrics`, `HourlyTimeline`, `DailyHistory`, `DataStatus`, `WeatherBackground`. `Header`'s reload button is implemented but commented out (not rendered) for now — a deliberate, reversible choice, not a removed feature.
- `src/App.tsx` composing the above; loading/empty/error states rendered distinctly (not just color-coded).
- CSS: glassmorphism cards, gradient/animated background driven by weather theme + day/night, `prefers-reduced-motion` handling, responsive layout.
- `tests/` — Vitest + RTL covering initial fetch (and that it's the *only* network call), rendering of each data section, loading/empty/stale/error states, polling re-fetch behavior, weather-code mapping.

**Files/areas affected**: `ui-service/src/**`, `tests/`.

**Dependencies**: Stage 3 (a working Backend to call; tests use mocked fetch, not a live backend).

**Tests**: initial `GET /api/weather` call and no others; current/metrics/hourly/history rendering; loading/empty/stale/error states; polling re-fetches `/api/weather` on the interval and updates the render; `reload()` unit-tested directly on the hook; weather-code mapping unit tests.

**Verification commands**:
```bash
cd ui-service
npm run dev   # with backend-service + history-service running
npm test
```

**Acceptance criteria**: matches the full acceptance list at the end of `docs/architecture.md`'s source spec — modern/polished look, all sections render from persisted data, stale/error/empty states are friendly and non-blocking, responsive, accessible, tests pass, full stack runs locally end-to-end.

**Documentation updates**: `docs/project-status.md` (final), `README.md` if run commands changed, `docs/troubleshooting.md` for real issues.
