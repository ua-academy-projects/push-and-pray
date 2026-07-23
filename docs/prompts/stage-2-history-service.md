# Stage 2 Prompt — History Service

## Role

You are a senior backend engineer implementing one stage of a multi-service DevOps Academy assignment called SkyIvano. Work carefully, keep the code simple and explainable, and do not exceed the scope of this stage.

## Project context

SkyIvano is a weather dashboard for Ivano-Frankivsk with three independently runnable services (UI, Backend, History) plus PostgreSQL, where only the History Service touches the database. Before doing anything else, read:

- `README.md`
- `docs/architecture.md` (technical source of truth — API contracts, schema, rules)
- `docs/implementation-plan.md` (this stage's work breakdown, under "Stage 2")
- `docs/project-status.md` (current progress — Stage 1 should already be complete)
- `docs/troubleshooting.md`

Then inspect the existing repository, especially `history-service/app/models`, `database/`, and `config.py` from Stage 1 — build on what's there, do not recreate it.

## Current stage

**Stage 2 of 4 — History Service.**

## Stage goal

A fully functional, independently runnable History Service API: persistence (with upserts) and read endpoints, backed by the Stage 1 schema.

## Scope

- `app/schemas/` — Pydantic request/response models matching `docs/architecture.md` §7's History Service contract.
- `app/services/persistence_service.py` — find-or-create location; upsert current/daily/hourly using `INSERT ... ON CONFLICT DO UPDATE` on the unique constraints from Stage 1; record a successful sync; all inside one transaction with rollback on any failure.
- `app/services/weather_query_service.py` — latest/history/hourly read queries.
- `app/api/weather.py` — `PUT /internal/weather`, `GET /internal/weather/latest`, `GET /internal/weather/history?days=`, `GET /internal/weather/hourly?date=`.
- `app/api/syncs.py` — `POST /internal/syncs/failure`, `GET /internal/syncs` (add the optional start/success/failure-by-id endpoints only if they keep the code simpler than the single-PUT approach — your call, document which you chose and why).
- `app/api/health.py` — `GET /health` with a real database connectivity check.
- `app/main.py` wiring it all together.

## Out of scope

- No Backend or UI code.
- No changes to the Stage 1 schema unless you find a genuine defect — if so, add a new migration, don't hand-edit the old one, and explain why in your report.
- No Docker/CI.

## Architecture rules (must hold)

- This service never calls Open-Meteo.
- All persistence logic lives in `services/`, not sprawled across route handlers.
- Duplicate prevention relies on the DB unique constraints (already in place from Stage 1) via `ON CONFLICT`, not just application-side checks.
- A failed `PUT /internal/weather` must roll back fully and leave prior data untouched.
- No authentication is required for `/internal/*` in this assignment, but note in your `app/main.py` (a short comment) that these endpoints need protection in production — full reasoning is already in `docs/architecture.md` §11, don't duplicate it at length.

## Detailed tasks

1. Read the docs and inspect the repo as described above.
2. Implement schemas, persistence service, query service, and all routes listed in Scope.
3. Make sure `PUT /internal/weather` is transactional: on any error, nothing is partially written.
4. Write tests: first location insert, location reuse on repeat, first current-weather insert, current-weather update (no duplicate row), first daily insert, repeated daily upsert with no duplicates, first hourly insert, repeated hourly upsert with no duplicates, sync success record (including `open_meteo_request_url`/`open_meteo_status_code`/`open_meteo_duration_ms` being persisted correctly), sync failure record (including with partial/null call metadata), transaction rollback leaves prior data intact, history query ordering (newest first), `days` parameter validation (including an out-of-range value), health endpoint reflects real DB state.
5. Update `docs/project-status.md` and `docs/troubleshooting.md` (real issues only).

## Testing requirements

pytest against real PostgreSQL (`skyivano_test`), no SQLite, no mocking of the database.

## Verification commands

```bash
cd history-service
uvicorn app.main:app --reload --port 8001
curl -X PUT localhost:8001/internal/weather -H 'Content-Type: application/json' -d @tests/fixtures/sample_payload.json
curl localhost:8001/internal/weather/latest
curl localhost:8001/health
DATABASE_URL=postgresql+psycopg://skyivano:skyivano@localhost:5432/skyivano_test pytest
```

## Documentation updates

- `docs/project-status.md`: mark Stage 2 items complete.
- `docs/architecture.md`: update only if your final endpoint/field names diverge from what's documented — call this out explicitly in your report.
- `docs/troubleshooting.md`: real issues only.

## Acceptance criteria

- Service starts standalone (History Service alone, no Backend needed).
- `PUT` then `GET /internal/weather/latest` round-trips correctly.
- Repeating the same `PUT` does not increase row counts for current/daily/hourly.
- A deliberately broken payload fails the transaction and leaves prior good data intact.
- `GET /internal/weather/history` and `/hourly` return correctly ordered, correctly filtered data.
- All tests pass.

## Required final report

- Summary of what was built
- Changed files (list)
- Tests executed and results
- Manual verification performed (commands + outcomes, including a duplicate-PUT row-count check)
- Problems encountered
- Troubleshooting doc updates made
- Remaining work / anything deferred
- project-status.md updates made

## Stop condition

Do not start the next stage.
Stop after completing and reporting the current stage.
