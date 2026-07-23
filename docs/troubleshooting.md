# Troubleshooting

Two sections: generic issues that are reasonably likely to occur given this stack, seeded up front so they're not re-diagnosed from scratch; and issues actually hit during implementation, added as they happen. Entries in the second section are the ones with real diagnosis detail — the first section is general guidance, not a claim that these specific incidents occurred.

## Common expected issues

**PostgreSQL connection refused**
- Cause: PostgreSQL isn't running, or is listening on a different host/port than `DATABASE_URL` specifies.
- Fix: start PostgreSQL locally; confirm with `pg_isready`; check `DATABASE_URL` matches the actual host/port/user.
- Verify: `psql "$DATABASE_URL" -c 'select 1;'`

**Incorrect `DATABASE_URL`**
- Cause: wrong driver prefix (must be `postgresql+psycopg://...` for this project — psycopg v3, not psycopg2), wrong credentials, or wrong database name.
- Fix: compare against `backend-service/.env.example` (moved here from `history-service/.env.example` in Stage 1); ensure the target database exists (`createdb skyivano`).
- Verify: `psql "$DATABASE_URL" -c '\dt'`

**Alembic migration failure**
- Cause: migration written against a database that already has conflicting objects, or `alembic/env.py` isn't pointed at the right metadata/`DATABASE_URL`.
- Fix: check `alembic current` vs `alembic history`; for a broken local dev DB, drop and recreate it rather than hand-editing migration state.
- Verify: `alembic upgrade head` completes with no errors; `alembic current` shows the head revision.

**Port already in use**
- Cause: another process (often a previous uvicorn/vite run) is already bound to 8000/8001/5173.
- Fix: `lsof -i :8000` (or the relevant port) to find the process, stop it, or run with a different `--port` and update the dependent service's env var.
- Verify: the target port shows the new process after restart.

**~~History Service unavailable (from the Backend's perspective)~~ — obsolete as of the Stage 1 refactor**
- The History Service no longer exists as a running component (`docs/prompts/refactor-0-discovery-and-plan.md`); the Backend now accesses PostgreSQL directly and has nothing to reach over HTTP for persistence. If the Backend can't read/write weather data, that's a **database** connectivity problem now — see "PostgreSQL connection refused" above and check `GET /api/health`'s `database_connected` field.

**Backend test suite now requires a real test database for every test, not just DB-touching ones (Stage 1 change)**
- Cause: `backend-service/tests/conftest.py` (moved from the History Service) has session-scoped `autouse` fixtures — `_require_test_database` and `_clean_tables` — that apply to the whole `backend-service/tests/` directory once merged in, not just the persistence tests. Previously, `backend-service`'s own tests ran with everything mocked and needed no database at all.
- Symptom if missed: `pytest.exit("DATABASE_URL does not point at a database named like '*test*' ...")` before any test runs.
- Fix: always export `DATABASE_URL` pointed at `skyivano_test` before running `pytest` in `backend-service/`, the same convention the History Service always used.
- Verify: `DATABASE_URL=postgresql+psycopg://skyivano:skyivano@localhost:5432/skyivano_test pytest` in `backend-service/`.

**Fetcher cannot reach Open-Meteo** *(moved here from the Backend in Stage 2 — only `fetcher-service` calls Open-Meteo now)*
- Cause: no internet access, DNS failure, or Open-Meteo is down.
- Fix: check general connectivity; this should surface as a *failed fetch* with prior data still served by the Backend, not a crash.
- Verify: `curl "$OPEN_METEO_BASE_URL?latitude=48.9226&longitude=24.7111&current=temperature_2m"` returns JSON.

**Open-Meteo request timeout**
- Cause: slow network or an unrealistically low `HTTP_TIMEOUT_SECONDS` on `fetcher-service`.
- Fix: raise the timeout value; confirm it's actually being applied to the httpx client.
- Verify: fetch completes, or fails gracefully and is recorded as `failed`, within the configured timeout.

**Invalid/unexpected Open-Meteo response shape**
- Cause: a field the normalizer expects is missing, or hourly/daily arrays have mismatched lengths.
- Fix: the normalizer (`fetcher-service/app/normalization/`) should reject and raise a typed error rather than silently producing partial/garbage data; the sync is then recorded as `failed` and prior data is preserved.
- Verify: a normalization unit test with a deliberately malformed fixture raises the expected exception.

**Scheduler not running** *(moved to `fetcher-service` in Stage 2)*
- Cause: `WEATHER_SYNC_ENABLED=false` on `fetcher-service`, or the scheduler was never started in its `main.py` startup hook.
- Fix: check the flag; check `GET /internal/scheduler/status` on the **Fetcher** (port 8002, not the Backend).
- Verify: `curl localhost:8002/internal/scheduler/status` shows `enabled: true` and a `next_run_time`.

**Synchronization overlapping**
- Cause: a long-running fetch plus a new scheduled/manual trigger firing before it finishes.
- Fix: the Fetcher's shared lock should reject/skip the second attempt; confirm `max_instances=1` is actually set on the APScheduler job. The Backend has a *separate* lock scoped only to `POST /api/sync/trigger` (Stage 2) — don't confuse the two when debugging.
- Verify: firing `POST /internal/fetch` on the Fetcher (or `POST /api/sync/trigger` on the Backend) twice in quick succession only performs one Open-Meteo call.

**`POST /internal/weather/sync` returns 404 (obsolete as of Stage 2)**
- Cause: this endpoint existed on the Backend through Stage 1 (it triggered a full fetch+persist cycle). As of Stage 2, triggering a fetch is the Fetcher's job (`POST /internal/fetch`, port 8002) or the Backend's manual-refresh proxy (`POST /api/sync/trigger`, port 8000). The Backend's `PUT /internal/weather/sync` (note: `PUT`, not `POST`) is a *different* endpoint — the Fetcher pushing data, not a trigger.
- Fix: use the right endpoint for the right service; see `docs/architecture.md` §8.

**No persisted data available**
- Cause: fresh database, first sync hasn't run or hasn't succeeded yet.
- Fix: this is an expected state — `GET /api/weather` should return a clear "no data yet" response, and the UI should show a friendly empty state, not an error or fake data.
- Verify: on an empty DB, `curl localhost:8000/api/weather` returns the documented no-data shape, not a 500.

**Data marked as stale**
- Cause: `now - last_synchronized_at > WEATHER_DATA_MAX_AGE_MINUTES`, or the last sync failed.
- Fix: this is expected behavior, not a bug — check `stale_reason` to distinguish "overdue" vs "last sync failed" vs "no sync time available."
- Verify: `curl localhost:8000/api/sync-status`.

**CORS problems (UI → Backend)**
- Cause: the UI's origin isn't in `BACKEND_CORS_ORIGINS`.
- Fix: add the UI's dev-server origin (default `http://localhost:5173`) to the Backend's CORS config.
- Verify: browser dev tools network tab shows no CORS error on `GET /api/weather`.

**UI cannot reach Backend**
- Cause: `VITE_BACKEND_BASE_URL` wrong, or Backend not running.
- Fix: check `ui-service/.env`; confirm `curl $VITE_BACKEND_BASE_URL/api/health` works from the same machine.

**Timezone problems**
- Cause: naive (timezone-unaware) datetimes being compared or stored, or a mismatch between UTC storage and Europe/Kyiv display.
- Fix: always use timezone-aware datetimes; store in UTC, convert only at the presentation/query boundary.
- Verify: a unit test asserting `is_stale` calculation is correct across a DST boundary/UTC offset change.

**Duplicate database rows**
- Cause: an upsert that doesn't actually target the unique constraint (e.g. plain `INSERT` instead of `INSERT ... ON CONFLICT DO UPDATE`).
- Fix: verify the `ON CONFLICT` target matches the real unique constraint columns.
- Verify: run the same sync twice, then `SELECT count(*) FROM daily_weather WHERE location_id = ... AND weather_date = ...` — must be 1.

**Tests using the wrong database**
- Cause: `DATABASE_URL` pointed at the dev database instead of a dedicated test database when running `pytest`.
- Fix: always export `DATABASE_URL` for `skyivano_test` before running Backend Service tests (this now includes the whole `backend-service/tests/` suite, not just persistence tests — see below); never let tests run against `skyivano`.
- Verify: confirm the test run's `DATABASE_URL` env var before invoking pytest.

## Issues encountered during implementation

**`GET /api/weather/hourly` failed with `ResponseValidationError` after adding the statistics endpoints (refactor Stage 3)**
- Problem: the existing hourly test started failing with a `ResponseValidationError` listing "Field required: id, location_id, synchronized_at, created_at, updated_at" for every hourly row, even though nothing about the hourly logic itself had changed in this stage.
- Cause: while adding several new imports to `app/api/public_weather.py` for the new statistics/chart/forecast schemas, `WeatherHourlyResponse` was accidentally imported from `app.schemas.persistence` (the DB-column-carrying shape, expects `HourlyWeatherOut` items) instead of `app.schemas.weather` (the flat public shape `weather_read_service.get_hourly()` actually constructs) — two unrelated classes happen to share the exact same name in different modules.
- Diagnosed by: the pytest failure output listed the exact missing fields, which immediately pointed at a schema-shape mismatch rather than a logic bug; checking the import line confirmed which of the two same-named classes was wired in.
- Fix: imported `WeatherHourlyResponse` from `app.schemas.weather` instead.
- Verify: `pytest tests/test_api.py -k hourly` in `backend-service/`.
- Avoid later: when two modules define a class with the same name for different purposes (here: a lean public-facing schema vs. a full DB-backed one), a stray import from the wrong module produces no error at import time and no error until FastAPI actually tries to validate a real response against it — worth a quick visual double-check of import lines whenever adding several schema imports to one file at once, since Python won't catch this class of mistake for you.

**`psycopg2-binary` failed to install (Stage 1)**
- Problem: `pip install -r requirements.txt` failed building `psycopg2-binary` with `Error: pg_config executable not found`.
- Cause: the local Python (3.14) is newer than any prebuilt `psycopg2-binary` wheel available at the time, so pip fell back to building from source, which needs PostgreSQL's `pg_config` — not present because Postgres itself runs in Docker, not natively on this machine.
- Diagnosed by: reading the pip build error directly (`pg_config executable not found`).
- Fix: switched the History Service's driver from `psycopg2-binary` to `psycopg[binary]` (psycopg v3), which ships current binary wheels and is a fully supported SQLAlchemy 2 sync dialect. Connection strings changed from `postgresql+psycopg2://` to `postgresql+psycopg://` throughout the repo.
- Verify: `pip install -r history-service/requirements.txt` completes without a build step; `python -c "import psycopg"` succeeds.
- Avoid later: prefer `psycopg` (v3) over `psycopg2` for new environments unless a specific dependency requires `psycopg2`.

**Local PostgreSQL provisioned via a plain Docker container, not a native install**
- Context: no PostgreSQL or Python 3.12 was present on the dev machine; the user chose to keep the existing Python and run Postgres via `docker run` rather than a native Homebrew install.
- Setup: `docker run -d --name skyivano-postgres -e POSTGRES_USER=skyivano -e POSTGRES_PASSWORD=skyivano -e POSTGRES_DB=skyivano -p 5432:5432 -v skyivano-pgdata:/var/lib/postgresql/data postgres:16`, then `docker exec skyivano-postgres createdb -U skyivano skyivano_test`.
- This is a **local development convenience only** — it does not make the project "use Docker" in the architectural sense; the three application services (UI, Backend, History) still run natively per `docs/architecture.md`, and there is no Dockerfile/Compose file for them.
- Note for anyone without Docker: a native PostgreSQL install works identically — just `createdb skyivano` and `createdb skyivano_test` and point `DATABASE_URL` at it.

**Docker daemon went down between sessions, History Service returned 503 (Stage 2)**
- Problem: starting the History Service and calling `/health` returned `503 {"status": "degraded", "database": "unreachable"}`, with a `psycopg.OperationalError: connection to server ... failed: Connection refused` logged server-side.
- Cause: Docker Desktop (and its daemon) had stopped since the last session; the `skyivano-postgres` container was therefore also stopped, though not removed.
- Diagnosed by: `/health`'s own error response pointed straight at "database unreachable"; `docker ps -a` showed the container in an `Exited` state.
- Fix: `open -a Docker` to relaunch Docker Desktop, wait for the daemon, then `docker start skyivano-postgres`. The named volume (`skyivano-pgdata`) persisted all prior data across the restart — nothing needed re-creating.
- Verify: `docker exec skyivano-postgres pg_isready -U skyivano`, then `curl localhost:8001/health` returns `{"status": "ok", ...}`.
- Avoid later: this is exactly why `/health` checks real DB connectivity instead of just "is the process up" — it surfaces this class of problem immediately and specifically, instead of every endpoint failing with a generic error.

**`pydantic-core` failed to build on Python 3.14 (Stage 1)**
- Problem: after fixing the `psycopg2` issue above, `pip install -r requirements.txt` then failed building `pydantic-core` from source, with `error: the configured Python interpreter version (3.14) is newer than PyO3's maximum supported version (3.13)`.
- Cause: the pinned `pydantic==2.10.3` (and its `pydantic-core` dependency) predates Python 3.14 and has no prebuilt wheel for it; pip fell back to a Rust source build via PyO3, which explicitly refuses interpreters newer than it supports.
- Diagnosed by: reading the build error (`PyO3's maximum supported version`).
- Fix: removed the version pin, let pip resolve the latest compatible `pydantic`/`pydantic-settings` (which do ship 3.14 wheels), then re-pinned `requirements.txt` to the exact resolved versions via `pip freeze` for reproducibility.
- Verify: `pip install -r history-service/requirements.txt` completes with no compilation step; `python -c "import pydantic"` succeeds.
- Avoid later: when pinning dependency versions for a service, prefer a recent version and a periodic bump rather than a version frozen at spec-writing time — very new Python releases will keep outrunning old pins.

**Real Open-Meteo request URL too long for `open_meteo_request_url` column (Stage 3)**
- Problem: the first real end-to-end run (Backend startup sync against the live Open-Meteo API, not mocked) failed with `PUT /internal/weather` returning `500`, logged in the History Service as `psycopg.errors.StringDataRightTruncation: value too long for type character varying(500)`.
- Cause: `weather_syncs.open_meteo_request_url` was defined as `VARCHAR(500)` (a size picked without checking the real value). The actual request URL -- with the full comma-separated `current`/`hourly`/`daily` field lists Open-Meteo requires -- is 741 characters long, well over that limit. Every unit test used mocked, short URLs, so this never surfaced until a real network call was made.
- Diagnosed by: reading the History Service's server-side traceback, which named the exact column and constraint.
- Fix: changed the column from `String(500)` to `Text` (unbounded -- there's no natural cap on a URL) in `app/models/weather_sync.py`, generated a real Alembic migration (`alter_column ... type_=sa.Text()`) rather than hand-editing the already-applied initial migration, and applied it to both `skyivano` and `skyivano_test`.
- Verify: `alembic upgrade head` on both databases; re-run the startup sync against the real Open-Meteo API and confirm `PUT /internal/weather` returns `200`.
- Avoid later: this is a direct argument for always exercising at least one real, unmocked end-to-end run before calling a stage done -- mocked tests validate logic, but only a real call validates real-world data sizes (URLs, payload sizes, unexpected field values).

**React Testing Library `getByText` couldn't find text that was visibly on the screen (Stage 4)**
- Problem: `screen.getByText(/25°C/)` failed even though "25°C" was clearly rendered.
- Cause: JSX like `{Math.round(value)}°C` produces two sibling text nodes ("25" and "°C"), not one merged string -- `getByText` matches within a single text node by default, so a regex spanning both never matches. Separately, two components legitimately rendering the same word ("Today" as both an hourly-timeline heading and a daily-history label) caused a "found multiple elements" failure.
- Diagnosed by: reading RTL's pretty-printed DOM dump in the failure output, which showed the value split across `<span>`s.
- Fix: assert on `element.textContent` (which concatenates child text nodes) instead of `getByText` for split values, and scope queries with `within(container)` when the same text legitimately appears in more than one section.
- Verify: `npm test` in `ui-service/`.
- Avoid later: prefer `within(landmark).getByText(...)` over a page-wide `getByText` whenever a component under test sits alongside siblings that might repeat the same words.

**`vi.useFakeTimers()` made `waitFor`-based hook tests hang until timeout (Stage 4)**
- Problem: every test in `tests/useWeather.test.ts` timed out at 5000ms once fake timers were introduced to test the polling interval.
- Cause: Testing Library's `waitFor` polls using real timers internally; with `vi.useFakeTimers()` active, those internal timers never fire on their own, so `waitFor` waits forever for a condition that would actually already be true.
- Diagnosed by: recognizing the timeout pattern as a known fake-timers/`waitFor` interaction rather than an app bug (nothing in the hook itself changed).
- Fix: replaced `waitFor` with `await act(async () => { await vi.advanceTimersByTimeAsync(ms); })`, which both advances fake time and flushes the promises/microtasks that timer callback triggers -- then asserted directly with no polling wrapper needed.
- Verify: `npm test -- tests/useWeather.test.ts`.
- Avoid later: don't mix `waitFor` with fake timers; use `vi.advanceTimersByTimeAsync` (or switch to real timers for that specific test) instead.

**`daily_forecast.precipitation_probability_max` was always `NULL` (refactor Stage 2)**
- Problem: after a real end-to-end fetch against live Open-Meteo, every row in `daily_forecast` had `precipitation_probability_max = NULL`, even though Open-Meteo was confirmed (via a direct `curl`) to return real, non-null values for that field.
- Cause: a silent field-name mismatch across the service boundary. The Fetcher's normalized schema and Open-Meteo's own field are both named `precipitation_probability_max`, but the Backend's `DailyForecastIn` Pydantic schema was initially named `precipitation_probability`. Since the field is `Optional`, no validation error occurred — the mismatched key was just never populated, defaulting silently to `None`. Every unit test on both sides used mocks that were internally consistent with their own (wrong, on the Backend's side) naming, so nothing caught it.
- Diagnosed by: querying the real database rows directly after a live fetch and comparing against a direct `curl` to Open-Meteo confirming the source data was non-null.
- Fix: renamed the field to `precipitation_probability_max` throughout the Backend (model, Pydantic schema, `persistence_service.py`, all tests) to match the Fetcher and Open-Meteo exactly. Since the migration adding `daily_forecast` had only just been applied locally and nothing else depended on the wrong name yet, downgraded one revision, fixed the model, and regenerated the migration rather than adding a follow-up rename migration.
- Verify: `alembic upgrade head`; trigger a real fetch; `SELECT weather_date, precipitation_probability_max FROM daily_forecast` shows real percentages, not `NULL`.
- Avoid later: when two services independently define "the same" field in their own schemas (by design — services don't share models), a mismatched name is a silent data-loss bug, not a crash, if the field is `Optional`. Cross-check field names against the actual wire payload (or write a same-shape assertion in one integration test) whenever a new field crosses a service boundary, not just at the unit level on each side.

**`PersistenceError` propagated as a raw traceback instead of a clean 500 (refactor Stage 2)**
- Problem: a test exercising `PUT /internal/weather/sync`'s rollback behavior (a deliberately malformed payload) failed with a raw `psycopg`/`sqlalchemy` traceback surfacing through `TestClient`, instead of the expected `response.status_code == 500`.
- Cause: `persistence_service.upsert_weather()` catches the underlying DB exception, rolls back, and re-raises `PersistenceError` — but no FastAPI exception handler was registered for it. Starlette's `TestClient` (default `raise_server_exceptions=True`) re-raises any exception that isn't caught by a registered handler, rather than converting it to a generic 500, specifically so real bugs are loud during testing. In Stage 1 this exception was only ever raised from a background thread (`asyncio.to_thread`), never from an HTTP request handler directly, so this gap existed but was never exercised.
- Diagnosed by: reading the pytest failure output, which showed the real `CardinalityViolation` traceback instead of a clean HTTP assertion failure.
- Fix: added `@app.exception_handler(PersistenceError)` in `backend-service/app/main.py`, returning a `JSONResponse(status_code=500, content={"detail": "Failed to persist weather data"})` — no leaked internals, consistent with the project's existing "never leak raw exception details" convention.
- Verify: `pytest tests/test_api.py -k rollback` in `backend-service/`.
- Avoid later: any exception a service deliberately raises to signal "this request failed" needs a registered handler if it's ever reachable from an HTTP route — don't assume FastAPI's default unhandled-exception behavior is sufficient, especially since it behaves differently under `TestClient` than in production.

**Recharts charts rendered as empty `<div>`s with no `<svg>` under Vitest/jsdom (refactor Stage 4)**
- Problem: tests asserting a chart panel contains an `<svg>` failed — the DOM showed Recharts' wrapper `<div>` but no chart content at all, even with real, non-empty data passed in.
- Cause: Recharts' `<ResponsiveContainer>` measures its wrapper element (via `ResizeObserver`, falling back to `getBoundingClientRect`/`offsetWidth`/`offsetHeight`) to decide what size to render at; jsdom implements none of these meaningfully (no `ResizeObserver` global at all, and `getBoundingClientRect` always returns all-zero dimensions), so the container computes a 0×0 target and renders nothing.
- Diagnosed by: recognizing this as a known Recharts+jsdom interaction (documented by the library) rather than an app bug, once the component's real-browser screenshot (see the manual verification below) showed the same charts rendering correctly with real data.
- Fix: in `ui-service/tests/setup.ts`, added a minimal `ResizeObserver` stub on `globalThis` and overrode `HTMLElement.prototype.offsetWidth`/`offsetHeight`/`getBoundingClientRect` to report a fixed, nonzero size (600×300) for every element in the test environment.
- Verify: `npm test -- tests/AveragesSection.test.tsx` in `ui-service/` — the "all five chart panels, each backed by an `<svg>`" test passes.
- Avoid later: any chart library built on `ResponsiveContainer`-style auto-sizing needs this same jsdom shim; it's a test-environment gap, not something to work around in application code.

**An apparent mobile horizontal-overflow bug turned out to be a headless-Chrome CLI viewport limitation, not an app bug (refactor Stage 4)**
- Symptom: a headless-Chrome screenshot requested at `--window-size=390,844` (or 320, or 420) showed content — the `StatusStrip`'s "Refresh now" button, `CurrentWeatherCard`'s detail column, `WeatherMetrics` labels — cut off at the right edge, as if the page were wider than the viewport and not properly wrapping/stacking, even though the relevant components already had `flex-wrap: wrap` and a `@media (max-width: 560px)` stacking rule.
- Investigation: an isolated one-element test page confirmed the actual cause — at `--window-size=390,...`, `window.innerWidth` inside the loaded page reported `500`, not `390`; the CSS layout viewport did not match the requested window size at all below roughly 500px, though the *output PNG's pixel dimensions* still matched the request exactly (a crop of a wider layout, not a true render at the requested width). A `max-width: 560px` media query correctly evaluated as active against the real (500px) viewport in that same test, confirming the app's responsive CSS itself was working — the measurement tool was the thing lying about its own viewport size.
- Confirmed not a real bug by: re-running the same screenshot at 500px, 800px, and wider — content flowed and stacked correctly with no overflow at every width the tool could actually render accurately.
- Fix: none needed for the false-positive itself. Added `min-width: 0` on `.app-content`'s direct children (`global.css`) and an `overflow-x: hidden` backstop on `html`/`body` anyway, as standard defensive hardening against the general "a flex item's default content-based minimum width can stretch its ancestors past the viewport" class of bug — cheap insurance, not a fix for a confirmed defect.
- Verify: `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --window-size=500,1400 --screenshot=out.png http://localhost:5173/` renders the full dashboard with no clipped controls.
- Avoid later: when using a headless-Chrome CLI screenshot (rather than a real browser-automation library) to check a specific viewport width, verify the tool's actual effective viewport first (e.g. render a page that prints `window.innerWidth`) before trusting a narrow `--window-size` value — this Chrome version (150.x) silently floors it around 500px.

**A full-page screenshot showed the background gradient cutting off partway down the page (Stage 4)**
- Symptom, not a bug: a Playwright `fullPage: true` screenshot showed the page's flat dark navy `body` background below roughly one viewport height, instead of the themed gradient continuing.
- Cause: the background is `position: fixed`, which is sized to the viewport. Chromium's full-page screenshot capture does not reliably extend `position: fixed` elements to cover the full captured (scrolled) height, even though the element behaves correctly during normal, real scrolling.
- Diagnosed by: taking a second screenshot after actually scrolling the page and capturing only the real viewport (`fullPage: false`) -- the gradient covered the visible area correctly, proving this was a screenshot-tool artifact, not a rendering bug.
- Fix: none needed -- confirmed as expected `position: fixed` behavior, not a defect.
- Verify: scroll the real page in a browser; the background always covers the viewport.
- Avoid later: when a full-page screenshot of a `position: fixed` background looks broken, re-check with a scrolled, viewport-sized screenshot before treating it as a bug.
