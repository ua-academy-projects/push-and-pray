# Stage 3 Prompt — Backend Service and Scheduler

## Role

You are a senior backend engineer implementing one stage of a multi-service DevOps Academy assignment called SkyIvano. Work carefully, keep the code simple and explainable, and do not exceed the scope of this stage.

## Project context

SkyIvano is a weather dashboard for Ivano-Frankivsk. The Backend Service is the orchestration point: it calls Open-Meteo, normalizes the response, runs a scheduled synchronization independent of user traffic, and exposes both public (UI-facing) and internal (admin) HTTP APIs. It never touches PostgreSQL directly — it only calls the already-built History Service over HTTP. Before doing anything else, read:

- `README.md`
- `docs/architecture.md` (technical source of truth — sync flow, contracts, freshness rules)
- `docs/implementation-plan.md` (this stage's work breakdown, under "Stage 3")
- `docs/project-status.md` (Stages 1–2 should already be complete)
- `docs/troubleshooting.md`

Then inspect the existing repository, especially the History Service's actual API (`history-service/app/api/`, `app/schemas/`) so the Backend's client code matches what really exists, not just what's documented.

## Current stage

**Stage 3 of 4 — Backend Service and scheduler.**

## Stage goal

A fully functional, independently runnable Backend Service that synchronizes weather data on a schedule (and on demand via an internal endpoint), and serves persisted data to the UI through public read endpoints.

## Scope

- `app/config.py` — all backend env vars from `docs/architecture.md` §10.
- `app/clients/open_meteo_client.py` — httpx, configurable timeout, fixed Ivano-Frankivsk coordinates from config, `timezone=Europe/Kyiv&past_days=10&forecast_days=1`, typed exceptions for timeout/connection/non-2xx/invalid-JSON. Must return (or let the caller measure) the request URL, HTTP status code, and call duration alongside the parsed response — these get forwarded to the History Service per `docs/architecture.md` §8/§12 decision 15, so the actual outbound call is recorded, not just the sync outcome.
- `app/normalization/open_meteo_normalizer.py` — validate required fields, check array-length consistency, produce the internal schema described in `docs/architecture.md`. Isolate every Open-Meteo field name here — nowhere else in the codebase should know Open-Meteo's naming.
- `app/clients/history_service_client.py` — httpx calls to the History Service's `PUT`/`GET` endpoints, typed exceptions for timeout/unavailable.
- `app/services/weather_sync_service.py` — the single `run_weather_sync(trigger_type)` function containing all sync logic: overlap check → fetch (capturing request URL/status/duration) → normalize → persist (passing that call metadata through to `PUT /internal/weather` or `POST /internal/syncs/failure`) → record outcome. Must be callable identically from the scheduler, the internal endpoint, and (conceptually) a future cron/K8s job.
- `app/services/weather_read_service.py` and `freshness_service.py` — assemble `GET /api/weather` responses; compute `is_stale`/`stale_reason` from `WEATHER_DATA_MAX_AGE_MINUTES` using timezone-aware datetimes.
- `app/scheduler/weather_scheduler.py` — APScheduler configuration only (`max_instances=1`, `coalesce=True`, `replace_existing=True`, reasonable `misfire_grace_time`, interval from config) plus the startup-sync freshness check. No sync business logic here — it must call `weather_sync_service.run_weather_sync()`.
- `app/api/internal_weather.py` — `POST /internal/weather/sync`, `GET /internal/scheduler/status`.
- `app/api/public_weather.py` — `GET /api/weather`, `GET /api/weather/history`, `GET /api/weather/hourly`, `GET /api/sync-status`.
- `app/api/health.py` — `GET /api/health` (no Open-Meteo call, no sync trigger).
- `app/main.py` wiring routers + scheduler startup.

## Out of scope

- No UI code.
- No changes to the History Service's contract — if you discover a real mismatch, fix the Backend's client to match, and only touch History Service code if there's a genuine bug (explain in your report).
- No Docker/CI.
- No authentication on `/internal/*` — document the production concern in a short comment, full reasoning is already in `docs/architecture.md` §11.

## Architecture rules (must hold)

- The Backend calls Open-Meteo; nothing else does.
- The Backend never accesses PostgreSQL — all persistence goes through the History Service client.
- `GET /api/*` endpoints never call Open-Meteo and never trigger a sync, under any circumstance (including empty-database first load).
- Only one synchronization runs at a time, enforced by both scheduler config and an explicit lock shared across all three trigger paths.
- Failed synchronization must never delete or corrupt previously persisted data — that guarantee lives in the History Service's transaction (Stage 2); the Backend's job is to record the failure via `POST /internal/syncs/failure` and keep serving old data.

## Detailed tasks

1. Read the docs and inspect the repo as described above.
2. Implement the Open-Meteo client, normalizer, History Service client, and all services/routes listed in Scope.
3. Wire the scheduler at startup: check `WEATHER_SYNC_ENABLED`; if on, check `WEATHER_SYNC_ON_STARTUP`; if on, check whether recent successful data exists (via History Service) before running an initial sync; then schedule the recurring job at `WEATHER_SYNC_INTERVAL_MINUTES`.
4. Write tests: successful Open-Meteo response parsing and correct query parameters sent; Open-Meteo timeout/connection failure/non-2xx/invalid JSON/missing fields/inconsistent hourly arrays; normalization correctness; successful History Service persistence including the request URL/status code/duration being forwarded correctly; History Service timeout/unavailable; failed-sync recording (including partial call metadata on a non-2xx response, and null call metadata on a timeout where no response ever came back); scheduler starts when enabled and is inert when disabled; startup sync skipped when recent data exists; overlapping synchronization prevented (assert only one Open-Meteo call happens when two triggers race); public GET endpoints proven to make zero Open-Meteo calls; correct stale-data calculation; correct no-data response when nothing has ever synced.
5. Update `docs/project-status.md` and `docs/troubleshooting.md` (real issues only).

## Testing requirements

pytest + pytest-asyncio. Mock Open-Meteo (httpx) and the History Service client — no live network calls, no real database needed for these tests.

## Verification commands

```bash
# with history-service already running on :8001
cd backend-service
uvicorn app.main:app --reload --port 8000
curl -X POST localhost:8000/internal/weather/sync
curl localhost:8000/api/weather
curl localhost:8000/api/sync-status
curl localhost:8000/internal/scheduler/status
pytest
```

## Documentation updates

- `docs/project-status.md`: mark Stage 3 items complete.
- `docs/architecture.md`: update only if implemented endpoints/fields diverge from what's documented — call this out explicitly.
- `docs/troubleshooting.md`: real issues only.

## Acceptance criteria

- Backend starts standalone (given a running History Service).
- Scheduler runs without any UI/browser interaction — verify by observing a sync happen with nothing hitting `/api/*`.
- `POST /internal/weather/sync` performs one sync and returns metadata only (no raw Open-Meteo payload).
- A forced Open-Meteo failure (e.g. via test) results in a `failed` sync record and unchanged `GET /api/weather` data.
- `GET /api/weather` clearly reports `is_stale`/`stale_reason` when data is old or missing.
- All tests pass.

## Required final report

- Summary of what was built
- Changed files (list)
- Tests executed and results
- Manual verification performed (commands + outcomes)
- Problems encountered
- Troubleshooting doc updates made
- Remaining work / anything deferred
- project-status.md updates made

## Stop condition

Do not start the next stage.
Stop after completing and reporting the current stage.
