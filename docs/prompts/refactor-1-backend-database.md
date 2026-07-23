# Refactor Prompt 1 — Backend Database Integration

## Role

You are a senior backend engineer implementing stage 1 of a 4-stage architecture refactor of SkyIvano. Work carefully, keep code simple and explainable, and do not exceed the scope of this stage.

## Project context

Read `docs/architecture.md`, `docs/project-status.md`, and the output of `refactor-0-discovery-and-plan.md` (the approved plan) before doing anything else. Then re-inspect the real code in `history-service/app/` and `backend-service/app/` — the plan describes intent, the code is ground truth.

Today, `backend-service` reaches PostgreSQL only indirectly, through `app/clients/history_service_client.py` calling `history-service` over HTTP. This stage removes that indirection: `backend-service` gets direct PostgreSQL access, absorbing `history-service`'s models, migrations, and persistence/query logic. `backend-service` still calls Open-Meteo directly in this stage — extracting that into a separate `fetcher-service` is Stage 2, not this one. Keep the two concerns separate so each stage is independently testable.

## Current stage

**Stage 1 of 4 — Backend database integration.**

## Stage goal

`backend-service` becomes self-sufficient for persistence: it owns SQLAlchemy models, Alembic migrations, and reads/writes PostgreSQL directly. It still fetches Open-Meteo and runs the scheduler itself (unchanged from today) — only the *storage* path changes. `history-service` is not yet deleted, but nothing in the running system should call it anymore by the end of this stage.

## Scope

Move (with `git mv`, to preserve history) into `backend-service`:

- `history-service/app/models/` → `backend-service/app/models/` (`location.py`, `current_weather.py`, `daily_weather.py`, `hourly_weather.py`, `weather_sync.py`)
- `history-service/app/database/` → `backend-service/app/database/` (`base.py`, `session.py`)
- `history-service/alembic/` and `alembic.ini` → `backend-service/`
- `history-service/app/services/persistence_service.py`, `weather_query_service.py`, `time_utils.py` → `backend-service/app/services/`
- `history-service/app/schemas/location.py` → `backend-service/app/schemas/` (merge with existing `weather.py`/`sync.py`; de-duplicate any schema that already exists in both services with slightly different shapes — reconcile in favor of whichever is more complete, and note the reconciliation in your report)
- `history-service/tests/test_models.py`, `test_api.py`, `conftest.py`, `factories.py` → `backend-service/tests/`, updating imports

Rewrite in `backend-service`:

- `app/config.py` — add `DATABASE_URL`; remove `history_service_base_url`.
- `requirements.txt` — add `sqlalchemy`, `alembic`, and the Postgres driver `history-service` used (check `history-service/requirements.txt` for the exact driver/version — likely `psycopg`).
- `app/services/weather_sync_service.py` — replace calls to `HistoryServiceClient.put_weather()` / `.post_sync_failure()` with direct calls to the moved `persistence_service` functions, run inside a single DB transaction per `docs/architecture.md`'s existing transaction description.
- `app/services/weather_read_service.py`, `app/services/freshness_service.py` — replace `HistoryServiceClient.get_latest()` / `.get_history()` / `.get_hourly()` calls with direct calls to `weather_query_service`.
- `app/api/public_weather.py` — inject a DB session (`Depends(get_db)`) instead of the HTTP client.
- `app/main.py` — wire the DB session dependency; remove any `HistoryServiceClient` instantiation.

Delete (only after the above is verified working):

- `backend-service/app/clients/history_service_client.py`
- `backend-service/app/exceptions.py` entries specific to History-Service-over-HTTP failures (`HistoryServiceTimeoutError`, `HistoryServiceUnavailableError`, `HistoryServiceResponseError`) — replace with whatever error handling direct DB access needs (e.g. catching `IntegrityError`, `OperationalError`).

Leave untouched in this stage:

- `backend-service/app/clients/open_meteo_client.py`, `app/normalization/`, `app/scheduler/` — these move in Stage 2, not here.
- The `history-service` directory itself: do not delete it yet. Once this stage is verified, it becomes dead code (nothing calls it), but full removal is deferred to the end of Stage 2 so there's a fallback until the new fetcher path is also proven. Note its dead-code status in `docs/project-status.md`.

## Out of scope

- No Open-Meteo/scheduler extraction (Stage 2).
- No new statistics/chart endpoints (Stage 3).
- No UI changes (Stage 4).
- No Docker/CI changes.

## Architecture rules (must hold)

- `backend-service` accesses PostgreSQL directly — no HTTP hop for persistence.
- The existing unique constraints (`location_id + weather_date` on `daily_weather`, `location_id + weather_time` on `hourly_weather`) must be preserved exactly as `history-service` defined them — do not weaken or drop them during the move.
- A failed synchronization must still leave previously persisted data untouched (transaction rollback on error) — this guarantee moves from `history-service`'s transaction to `backend-service`'s, it must not be lost in the move.
- No SQLAlchemy models exist anywhere in `history-service` by the end of this stage that aren't also mirrored in `backend-service` (until the old service is deleted, they should be identical, not diverging forks).

## Detailed tasks

1. Read the docs and plan, then inspect `history-service/app/` and `backend-service/app/` to confirm the move list above still matches reality.
2. Perform the moves with `git mv`.
3. Update every import path touched by the move (`from app.models...`, `from app.database...`, `from app.services.persistence_service...`).
4. Rewrite the services/routes listed above to use direct DB access.
5. Point `backend-service`'s Alembic `env.py` at its own `app.database.base.Base.metadata` (it currently points at `history-service`'s — check the actual import path after the move).
6. Run `alembic upgrade head` against a local/dev Postgres to confirm the moved migrations apply cleanly from a fresh database.
7. Update tests: merge the moved `history-service` tests with `backend-service`'s existing suite, replacing any HTTP-client mocks with direct DB fixtures (real PostgreSQL test database per this project's existing convention — no SQLite).
8. Update `docs/project-status.md` and `docs/troubleshooting.md` (real issues only).

## Testing requirements

pytest against a real PostgreSQL test database (this project's existing convention — see `README.md` for the `skyivano_test` setup). Cover: current/daily/hourly upsert, no duplicate dates/timestamps, historical dates preserved across repeated syncs, transaction rollback on a forced failure mid-sync, sync-failure recording, health endpoint.

## Verification commands

```bash
cd backend-service
alembic upgrade head
uvicorn app.main:app --reload --port 8000
curl -X POST localhost:8000/internal/weather/sync
curl localhost:8000/api/weather
curl localhost:8000/api/sync-status
pytest
```

Confirm no process needs `history-service` running for the above to succeed.

## Documentation updates

- `docs/architecture.md`: update the sync/read diagrams and the "who owns PostgreSQL" section to reflect direct backend access; mark `history-service` as deprecated (not yet deleted).
- `docs/project-status.md`: mark Stage 1 items complete; note `history-service` is now dead code pending Stage 2.
- `docs/troubleshooting.md`: real issues only (e.g. Alembic revision conflicts from the move, driver version mismatches).

## Acceptance criteria

- `backend-service` runs standalone with no `history-service` process running.
- All moved + existing tests pass against real PostgreSQL.
- Historical daily records accumulate correctly across repeated syncs (no 10-day cap).
- Duplicate `location_id + weather_date` / `location_id + weather_time` rejected/upserted correctly, not duplicated.

## Required final report

- Summary of what was built
- Changed files (list, noting which were `git mv`-ed vs. rewritten vs. deleted)
- Tests executed and results
- Manual verification performed (commands + outcomes)
- Problems encountered
- Troubleshooting doc updates made
- Remaining work / anything deferred (explicitly: `history-service` directory still present, pending Stage 2)
- project-status.md updates made

## Stop condition

Do not start Stage 2. Stop after completing and reporting this stage.
