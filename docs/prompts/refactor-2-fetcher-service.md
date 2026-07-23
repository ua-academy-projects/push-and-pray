# Refactor Prompt 2 — Weather Fetcher Service Extraction

## Role

You are a senior backend engineer implementing stage 2 of a 4-stage architecture refactor of SkyIvano. Work carefully, keep code simple and explainable, and do not exceed the scope of this stage.

## Project context

Read `docs/architecture.md` (as updated in Stage 1), `docs/project-status.md`, and `refactor-0-discovery-and-plan.md` before doing anything else. Stage 1 already gave `backend-service` direct PostgreSQL access. `backend-service` still calls Open-Meteo and runs its own scheduler at this point — that's what this stage removes.

This stage creates a fourth service, `fetcher-service`, and moves all Open-Meteo/scheduling responsibility into it. After this stage, `backend-service` never calls Open-Meteo again; it only receives normalized data over HTTP from `fetcher-service`.

## Current stage

**Stage 2 of 4 — Weather Fetcher Service extraction.**

## Stage goal

A fully functional, independently runnable `fetcher-service` that calls Open-Meteo on its own schedule (and on demand via an internal endpoint), normalizes the response, and pushes it to `backend-service`'s new internal API. `backend-service` no longer contains any Open-Meteo client code, normalization code, or scheduler.

## Scope

### New service: `fetcher-service/`

Scaffold it to mirror `backend-service`'s existing project layout (`app/config.py`, `app/main.py`, `app/api/`, `app/clients/`, `requirements.txt`, `pytest.ini`, `tests/`, `README.md`, `.env.example`).

Move (with `git mv`) from `backend-service` into `fetcher-service`:

- `app/clients/open_meteo_client.py`
- `app/normalization/`
- `app/scheduler/weather_scheduler.py`
- `tests/test_open_meteo_client.py`, `test_normalizer.py`, `test_scheduler.py`

Rewrite/create in `fetcher-service`:

- `app/config.py` — `OPEN_METEO_BASE_URL`, `BACKEND_INTERNAL_BASE_URL`, `WEATHER_LOCATION_NAME`, `WEATHER_COUNTRY`, `WEATHER_LATITUDE`, `WEATHER_LONGITUDE`, `WEATHER_TIMEZONE`, `WEATHER_SYNC_ENABLED`, `WEATHER_SYNC_ON_STARTUP`, `WEATHER_SYNC_INTERVAL_MINUTES`, `WEATHER_PAST_DAYS` (default 10), `WEATHER_FORECAST_DAYS` (default 10), `HTTP_TIMEOUT_SECONDS`.
- `app/clients/backend_client.py` — new httpx client calling `backend-service`'s internal endpoints (see below), replacing what `history_service_client.py` used to do for the sync-push half only (not the read half — the fetcher never reads weather data back).
- `app/services/fetch_sync_service.py` (or similar name) — the single orchestration function (fetch → validate → normalize → POST to backend → record local success/failure) adapted from `backend-service`'s old `weather_sync_service.py`. Must remain callable identically from the scheduler, from `POST /internal/fetch`, and — indirectly — from the Backend's new `POST /api/sync/trigger` proxy, with overlap prevention (one in-flight sync at a time) covering all three trigger paths. The Open-Meteo request must use both `past_days=WEATHER_PAST_DAYS` and `forecast_days=WEATHER_FORECAST_DAYS` in the same call; the normalizer splits the returned daily array into "observed" (date ≤ today in `WEATHER_TIMEZONE`) and "forecast" (date > today) before sending to the Backend, so the Backend can route each half to the correct table (see `refactor-3-statistics-api.md`).
- `app/api/internal_fetch.py` — `POST /internal/fetch` (manually runs the same sync function as the scheduler), `GET /internal/scheduler/status`.
- `app/api/health.py` — `GET /health`.
- `app/main.py` — wiring + scheduler startup (same `max_instances=1`, `coalesce=True`, `replace_existing=True` config the old scheduler used).

### `backend-service` changes

- `app/api/internal_weather.py` → rename/restructure to expose `PUT /internal/weather/sync` (accepts the fetcher's normalized payload: current + observed daily + forecast daily + hourly in one request) and `POST /internal/weather/sync-failure`. Reuse the moved `persistence_service.upsert_weather()` / `record_sync_failure()` from Stage 1 — this is a routing change, not new persistence logic. `upsert_weather()` gains the observed-vs-forecast split described above: observed daily rows go to `daily_weather` (accumulate forever, per the existing rule), forecast daily rows go to the new `daily_forecast` table (Stage 3), fully replaced on each sync — no accumulation guarantee for forecast data, since a forecast is expected to be superseded.
- Remove the old `POST /internal/weather/sync` (trigger-a-full-cycle) and `GET /internal/scheduler/status` handlers — that behavior now lives in `fetcher-service`.
- Add `app/api/sync_trigger.py` (or add to `public_weather.py`) — `POST /api/sync/trigger`: the **one deliberate exception** to "Backend never calls Fetcher." Called only by the UI's manual "Refresh now" button. Backend calls `fetcher-service`'s `POST /internal/fetch` synchronously via a new `app/clients/fetcher_client.py`, waits for the fetch→normalize→push cycle to complete (respecting `HTTP_TIMEOUT_SECONDS`), and returns a small result summary (success/failure, timestamp, records synced) — never Open-Meteo's raw response or a stack trace. If a sync is already in progress (scheduled or another manual trigger), return the in-progress status rather than queuing a second one. This endpoint requires `FETCHER_SERVICE_BASE_URL` in Backend's config — add it now, specifically for this one call, and document in `docs/architecture.md` that it exists solely for the manual-refresh path, not for Backend to poll or manage the Fetcher generally.
- Add `GET /api/sync/history?limit=20` — returns recent `weather_syncs` rows (timestamp, trigger type `scheduled`/`manual`, status, duration, records counts, error message if failed) for the UI's sync-history popup. This is a thin read over the existing `weather_syncs` table/`list_syncs` query from Stage 1 — no new persistence logic, just a public route.
- `app/config.py` — remove `OPEN_METEO_BASE_URL` and all `WEATHER_SYNC_*` scheduler settings (backend no longer schedules anything). Keep `DATABASE_URL`, `WEATHER_DATA_MAX_AGE_MINUTES`, `CORS_ALLOWED_ORIGINS`. Add `FETCHER_SERVICE_BASE_URL`, used exclusively by `POST /api/sync/trigger` as described above.
- Remove `requirements.txt` entries only needed for Open-Meteo calls/scheduling (`apscheduler`, if nothing else in backend uses it).
- Delete `backend-service/app/clients/open_meteo_client.py`, `app/normalization/`, `app/scheduler/` (now empty after the `git mv`).

### Cleanup

- Delete the `history-service` directory entirely — by now its models/migrations/persistence (Stage 1) and its only caller's Open-Meteo-triggering role (this stage) both have equivalents elsewhere. Confirm both prior stages are fully verified before deleting; call this out explicitly in your report before doing it.

## Out of scope

- No statistics/chart endpoints (Stage 3).
- No UI changes (Stage 4) — the UI's existing `/api/weather*` calls should keep working unchanged against `backend-service`.
- No Docker/CI changes.

## Architecture rules (must hold)

- Only `fetcher-service` calls Open-Meteo.
- `backend-service` never calls Open-Meteo. It calls `fetcher-service` in exactly one case — `POST /api/sync/trigger` forwarding to `POST /internal/fetch` — and nowhere else; no other Backend code path may call the Fetcher.
- `fetcher-service` never touches PostgreSQL, never imports SQLAlchemy models.
- `fetcher-service` sends data to `backend-service` only via the internal HTTP contract — no shared code/models between the two.
- `ui-service` never calls `fetcher-service` directly — a manual refresh always goes UI → Backend (`POST /api/sync/trigger`) → Fetcher, never UI → Fetcher.
- Only one fetch/sync runs at a time in `fetcher-service` (overlap prevention), enforced the same way the old scheduler enforced it in `backend-service`.
- A failed fetch/sync must never corrupt or delete previously persisted data — `backend-service`'s transaction guarantee from Stage 1 covers this on the receiving end; `fetcher-service`'s job is only to report the failure via `POST /internal/weather/sync-failure` and not retry destructively.

## Detailed tasks

1. Read the docs and inspect the current `backend-service` code (Open-Meteo client, normalizer, scheduler, old `weather_sync_service.py`) so the extraction reuses working logic rather than rewriting it from scratch.
2. Scaffold `fetcher-service`, perform the `git mv`s, fix imports.
3. Implement `backend_client.py` and the orchestration service in `fetcher-service`.
4. Implement the new internal endpoints in `backend-service` (`PUT /internal/weather/sync`, `POST /internal/weather/sync-failure`), reusing Stage 1's persistence functions.
5. Wire `fetcher-service`'s scheduler at startup (same enabled/on-startup/interval logic as before, now driven by `fetcher-service`'s own config).
6. Write/port tests (see below).
7. Verify end-to-end manually (commands below), then delete `history-service/`.
8. Update `docs/project-status.md` and `docs/troubleshooting.md`.

## Testing requirements

**Fetcher tests** (pytest + pytest-asyncio, mock Open-Meteo and the backend client — no live network calls, no database): successful Open-Meteo request with correct query parameters, timeout, invalid/inconsistent response, normalization correctness, successful push to backend, backend unavailable, backend timeout, scheduler startup, scheduler disabled, overlapping-sync prevention, failure reporting to backend.

**Backend tests** (real PostgreSQL, per this project's convention): `PUT /internal/weather/sync` upserts correctly and rejects invalid payloads, observed vs. forecast daily rows land in the correct table, `POST /internal/weather/sync-failure` records failures without touching existing data, public `GET /api/*` endpoints still work and make zero outbound calls to Open-Meteo, `POST /api/sync/trigger` calls the (mocked) Fetcher exactly once and returns a clean summary, a second concurrent call to `POST /api/sync/trigger` while one is in progress does not start a duplicate fetch, `GET /api/sync/history` returns recent syncs ordered newest-first including both `scheduled` and `manual` trigger types.

## Verification commands

```bash
cd backend-service && uvicorn app.main:app --reload --port 8000
cd fetcher-service && uvicorn app.main:app --reload --port 8002
curl -X POST localhost:8002/internal/fetch
curl localhost:8002/internal/scheduler/status
curl localhost:8000/api/weather
curl localhost:8000/api/sync-status
cd backend-service && pytest
cd fetcher-service && pytest
```

Confirm `backend-service` still serves `GET /api/weather` correctly with `fetcher-service` stopped (stale but not broken), and that stopping `backend-service` causes `fetcher-service`'s push to fail gracefully and record a failed sync locally without crashing the scheduler.

## Documentation updates

- `docs/architecture.md`: full rewrite of the sync-flow diagram and API contracts section to show `fetcher-service` as a fourth component; document the new internal contract (`PUT /internal/weather/sync`, `POST /internal/weather/sync-failure`); explain why History Service was merged into Backend and why Fetcher is a separate service.
- `README.md`: update the service table, run commands (now four services, not three), and remove `history-service` entirely.
- `docs/project-status.md`: mark Stage 2 complete; confirm `history-service` deleted.
- `docs/troubleshooting.md`: real issues only.

## Acceptance criteria

- `history-service` no longer exists in the repository.
- `fetcher-service` runs standalone and syncs on its own schedule with no UI/browser interaction.
- `backend-service` contains no Open-Meteo URL, client, or scheduler.
- A `fetcher-service` failure preserves existing data in `backend-service`/PostgreSQL.
- All tests pass in both services.

## Required final report

- Summary of what was built
- Changed files (list, noting `git mv` vs. new vs. deleted)
- Tests executed and results
- Manual verification performed (commands + outcomes)
- Problems encountered
- Troubleshooting doc updates made
- Remaining work / anything deferred
- project-status.md updates made
- Explicit confirmation that `history-service/` was deleted, and why it was safe to do so at this point

## Stop condition

Do not start Stage 3. Stop after completing and reporting this stage.
