# Project Status

## Stage 0 — Scaffolding & documentation

- [x] Repository structure (all three services + docs/)
- [x] Root README, .gitignore, root .env.example
- [x] Per-service README + .env.example
- [x] docs/architecture.md
- [x] docs/implementation-plan.md
- [x] docs/troubleshooting.md (seeded)
- [x] docs/project-status.md
- [x] docs/prompts/ (4 stage prompts)

Status: **Completed**

**Post-Stage-0 schema amendment**: `weather_syncs` extended with `open_meteo_request_url`, `open_meteo_status_code`, `open_meteo_duration_ms` so the actual outbound Open-Meteo call is recorded, not just the sync outcome (per user decision — see `docs/architecture.md` §8/§12 decision 15). Reflected in `docs/architecture.md` and the Stage 2/3 prompts before any code was written, so Stage 1 will build the schema with these columns from the start.

## Stage 1 — Foundation and database

- [x] History Service configuration (`app/config.py`)
- [x] SQLAlchemy models (locations, current_weather, daily_weather, hourly_weather, weather_syncs)
- [x] Alembic setup + initial migration
- [x] Database constraints and indexes verified
- [x] Model/DB tests (against real PostgreSQL)
- [x] Documentation update

Status: **Completed**

Tests executed: `pytest` in `history-service/` against `skyivano_test` (real PostgreSQL, in a local Docker container) — 8/8 passed. Migration verified both directions (`alembic upgrade head` / `downgrade -1` / `upgrade head` again, tests still green). Known issues: none blocking; two environment friction points hit and resolved, logged in `docs/troubleshooting.md` (`psycopg2` → `psycopg` v3 driver swap; dependency version pins bumped for Python 3.14 compatibility).

## Stage 2 — History Service

- [x] Pydantic schemas
- [x] Persistence service (transactional upsert)
- [x] `PUT /internal/weather`
- [x] `GET /internal/weather/latest`
- [x] `GET /internal/weather/history`
- [x] `GET /internal/weather/hourly`
- [x] Sync record endpoints (`POST /internal/syncs/failure`, `GET /internal/syncs`)
- [x] `GET /health`
- [x] Tests (insert/upsert/no-duplicates/rollback/ordering/health)
- [x] Documentation update

Status: **Completed**

Tests executed: `pytest` in `history-service/` against `skyivano_test` — 21/21 passed (13 new API tests + 8 Stage 1 model tests, still green). Manually verified with a running server + real `curl`/`httpx` round-trips: PUT→GET round-trip, repeated PUT does not duplicate rows (confirmed via direct row counts in `psql`), a genuinely broken payload (duplicate `weather_time` in one request) rolls back and leaves prior data untouched, `days` validation, sync failure recording, health check both healthy and (via an unrelated Docker outage, see troubleshooting) actually-degraded. Known issue: the `/health` degraded-DB path is covered by manual verification, not an automated test — simulating a live connection failure mid test-session without mocking the database (disallowed by the testing requirements) wasn't practical; not considered a gap worth chasing given a real outage already exercised it end-to-end.

## Stage 3 — Backend Service and scheduler

- [x] Open-Meteo client + error handling
- [x] Normalization layer
- [x] History Service HTTP client
- [x] weather_sync_service / weather_read_service / freshness_service
- [x] APScheduler wiring (startup + interval + lock)
- [x] `POST /internal/weather/sync`, `GET /internal/scheduler/status`
- [x] Public `/api/*` endpoints
- [x] `GET /api/health`
- [x] Tests (mocked Open-Meteo + History Service)
- [x] Documentation update

Status: **Completed**

Tests executed: `pytest` in `backend-service/` — 44/44 passed (Open-Meteo client, normalizer, History Service client via the sync service, freshness calculation, scheduler/startup behavior, and API-level tests, all with Open-Meteo/History mocked via `respx`). Manually verified end-to-end against the **real** Open-Meteo API and a live History Service/Postgres: startup sync fetched real Ivano-Frankivsk weather, normalized and persisted it (11 daily + 264 hourly rows across the full past_days+forecast_days range), `GET /api/weather` correctly scoped hourly down to just today (24 of the 264 rows) while surfacing all 11 daily rows; manual `POST /internal/weather/sync` works and two concurrent calls proved overlap prevention live (one `success`, one `skipped`, only one real Open-Meteo call); `/internal/weather/sync` never leaks raw Open-Meteo field names in its response; `/api/sync-status`, `/internal/scheduler/status`, `/api/health` all verified live.

Real bug found and fixed via that end-to-end run (not caught by mocked tests): `weather_syncs.open_meteo_request_url` was `VARCHAR(500)`, but the real Open-Meteo request URL is 741 characters — widened to `Text` via a new Alembic migration. Full writeup in `docs/troubleshooting.md`.

## Stage 4 — UI Service and integration

- [x] Vite React/TS scaffold + API client
- [x] Current weather, metrics, hourly timeline, daily history components
- [x] Weather-code mapping utility
- [x] Dynamic background/theming
- [x] Loading / empty / stale / error states
- [x] Accessibility pass
- [x] Vitest + RTL tests
- [x] Full local end-to-end verification
- [x] Documentation update

Status: **Completed**

**Pre-Stage-4 UI behavior decision**: the "Reload displayed data" button will be implemented but not rendered (commented out) for now; the polling interval is shortened to 60 seconds instead so a successful scheduler sync reaches the screen automatically, without the UI ever triggering a sync itself. See `docs/architecture.md` §12 decision 17.

Tests executed: `npm test` in `ui-service/` — 24/24 passed (initial-fetch-only assertion, current/metrics/hourly/daily rendering, loading/empty/stale/error states, polling behavior via `vi.advanceTimersByTimeAsync`, `reload()` unit-tested directly on the hook, weather-code mapping, no-reload-button assertion, a practical responsive-layout check on the hourly scroller). `tsc -b` and `vite build` both clean.

Manual end-to-end verification: ran all three services together (Postgres in Docker, History Service, Backend Service, UI dev server) with real Ivano-Frankivsk data from Open-Meteo. Used a headless-Chromium script (Playwright, installed ad hoc — see troubleshooting) to load the real page and screenshot it: hero card, metrics, hourly timeline, and 10-day history all rendered correctly from persisted data; zero browser console errors; no horizontal overflow at a 390px mobile viewport; the stale-data banner was verified live by temporarily setting `WEATHER_DATA_MAX_AGE_MINUTES=0` on the Backend — non-blocking warning appeared with the rest of the dashboard still fully rendered underneath, exactly as designed.

Real issues found and fixed during this stage (all in `docs/troubleshooting.md`): an RTL text-matching gotcha (split text nodes / ambiguous duplicate text), a `vi.useFakeTimers()` + `waitFor` incompatibility. One suspicious symptom (background gradient appearing to cut off in a full-page screenshot) was investigated and confirmed to be a screenshot-tool artifact, not a real bug — verified by scrolling a real viewport.

## Known issues

- Local dev environment uses Python 3.14 (not 3.12) and PostgreSQL via a plain Docker container rather than a native install — both by explicit user decision. Neither affects the application architecture; see `docs/troubleshooting.md` "Issues encountered during implementation" for details.
- `/health`'s degraded-database path (both services) is verified manually, not by an automated test.
- The "Reload displayed data" button is implemented (`reload()` in `useWeather`) but not rendered — a deliberate product decision, not a defect. See `docs/architecture.md` §12 decision 17.
- `chromium-cli` (the tool the `run` skill expects for browser verification) wasn't available in this environment; Playwright + Chromium were installed ad hoc in the scratchpad directory for one-off visual verification. Not part of the project's own dependencies.

## Overall project status

All four stages complete. The full stack (PostgreSQL → History Service → Backend Service → UI Service) runs locally end-to-end with real Ivano-Frankivsk weather data, verified both by automated tests (89 total: 21 History + 44 Backend + 24 UI) and manual/visual verification including real, unmocked calls to Open-Meteo.

## Next stage

None — all planned stages are complete. Remaining work is the explicitly out-of-scope future work listed in `docs/architecture.md` §13 (Docker/Compose for the app services themselves, Kubernetes, CI/CD, cloud deployment, monitoring, statistics endpoints).
