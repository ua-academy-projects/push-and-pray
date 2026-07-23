# Refactor Prompt 0 — Discovery and Plan (no code changes)

## Role

You are a senior backend/architecture engineer planning a structural refactor of SkyIvano, a multi-service weather dashboard built as a DevOps Academy assignment. This prompt is planning-only. Do not edit, move, or delete any files.

## Project context

SkyIvano currently has three services:

```
Scheduled sync:  backend-service (scheduler + Open-Meteo client) -> Open-Meteo
                 backend-service -> HistoryServiceClient (HTTP) -> history-service -> PostgreSQL
User reads:      Browser -> ui-service -> backend-service -> HistoryServiceClient (HTTP) -> history-service -> PostgreSQL
```

- `backend-service` calls Open-Meteo directly (`app/clients/open_meteo_client.py`), normalizes it (`app/normalization/open_meteo_normalizer.py`), runs the sync scheduler (`app/scheduler/weather_scheduler.py`), and pushes/pulls data to/from `history-service` over HTTP via `app/clients/history_service_client.py`. It never touches PostgreSQL.
- `history-service` owns PostgreSQL: SQLAlchemy models (`app/models/`), Alembic migrations (`alembic/`), and persistence/query logic (`app/services/persistence_service.py`, `app/services/weather_query_service.py`). It is only ever called by `backend-service`.
- `ui-service` (React/TS) talks only to `backend-service`'s public API.

Read `README.md` and `docs/architecture.md` first — they are the source of truth for the *current* system and describe these contracts precisely.

## Why we're changing it

We want a target architecture where responsibilities are split by *what talks to the outside world* rather than *who orchestrates*:

```
Scheduled sync:  fetcher-service -> Open-Meteo -> fetcher-service -> backend-service -> PostgreSQL
User reads:      Browser -> ui-service -> backend-service -> PostgreSQL
```

- `backend-service` becomes the only service that touches PostgreSQL. It absorbs `history-service`'s models, migrations, and persistence/query logic, and keeps serving the public API to the UI. It stops calling Open-Meteo.
- A new `fetcher-service` absorbs `backend-service`'s current Open-Meteo client, normalizer, and scheduler. It never touches PostgreSQL — it POSTs/PUTs normalized data to `backend-service` over HTTP instead.
- `history-service` is retired as a standalone runtime service once its functionality has an equivalent inside `backend-service`.

This gives a cleaner separation ("who calls the external API" vs. "who owns the database") and removes an unnecessary hop (backend used to be a pure pass-through relay between Open-Meteo and history-service).

## Your task (planning only)

1. Inspect the current repository state (`backend-service/`, `history-service/`, `ui-service/`, `docs/`) — confirm the summary above still matches reality; note any drift.
2. Produce a written comparison of current vs. target architecture (a short diagram + prose is fine).
3. List every file that should be **moved** (with `git mv`, to preserve history), grouped by destination:
   - `history-service/app/models/*`, `app/database/`, `alembic/`, `alembic.ini`, `app/services/persistence_service.py`, `app/services/weather_query_service.py`, `app/services/time_utils.py`, `app/schemas/location.py` → into `backend-service/`.
   - `backend-service/app/clients/open_meteo_client.py`, `app/normalization/`, `app/scheduler/` → into a new `fetcher-service/`.
4. List every file that must be **rewritten** (not just moved), and why — e.g. `backend-service/app/services/weather_sync_service.py` (currently orchestrates the whole fetch→normalize→push cycle; must split into "fetcher orchestrates fetch+normalize+send" and "backend receives+persists"), `backend-service/app/api/internal_weather.py` (trigger/scheduler-status endpoints move to the fetcher), `backend-service/app/api/public_weather.py` (must read from local DB services instead of `HistoryServiceClient`), the daily statistics/chart layer (does not exist yet — new code, not a move).
5. List code that becomes **obsolete**: `backend-service/app/clients/history_service_client.py`, `HISTORY_SERVICE_BASE_URL`, the `history-service` FastAPI app shell (`main.py`, its own `app/api/`) once step 3/4 land.
6. Propose the target repository structure (directory tree) for all four components, including the new `fetcher-service/` scaffold (mirror `backend-service`'s existing layout: `app/config.py`, `app/api/`, `app/clients/`, `app/main.py`, `tests/`, `requirements.txt`, `pytest.ini`, `README.md`, `.env.example`).
7. Propose the updated public and internal API contracts (see `docs/architecture.md` for current ones) — call out every endpoint that is added, renamed, or removed, and why.
8. Propose the database migration: what new columns/tables are needed (e.g. `daily_weather` currently has no `average_temperature`, `average_temperature_method`, `average_apparent_temperature`, `average_humidity`, `average_cloud_cover`, or `average_wind_speed` — these must be added via a new Alembic migration, not a rewrite of the existing one).
9. Propose a staged plan matching these four stages (already drafted as separate prompts — see `refactor-1` through `refactor-4` in this directory):
   - Stage 1: Backend database integration
   - Stage 2: Fetcher Service extraction
   - Stage 3: Statistics API and database adjustments
   - Stage 4: UI charts and final integration
10. Identify risks: data loss during the model/migration move, breaking the running app mid-migration, env var renames breaking existing `.env` files, git history loss if files are recreated instead of `git mv`-ed, coordinating the internal contract change between backend and the not-yet-existing fetcher, `history-service` deletion timing (must not happen before Stage 2 is verified end-to-end).

## Deliverable

A written plan covering points 1–10 above, presented to the user for approval. **Do not modify any files in this prompt.** Stop and wait for confirmation before starting `refactor-1-backend-database.md`.
