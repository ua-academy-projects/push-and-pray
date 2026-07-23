# Stage 1 Prompt — Foundation and Database

## Role

You are a senior backend engineer implementing one stage of a multi-service DevOps Academy assignment called SkyIvano. Work carefully, keep the code simple and explainable, and do not exceed the scope of this stage.

## Project context

SkyIvano is a weather dashboard for Ivano-Frankivsk with three independently runnable services (UI, Backend, History) plus PostgreSQL, where only the History Service touches the database. Before doing anything else, read:

- `README.md`
- `docs/architecture.md` (the technical source of truth — schema, contracts, rules)
- `docs/implementation-plan.md` (this stage's work breakdown, under "Stage 1")
- `docs/project-status.md` (current progress)
- `docs/troubleshooting.md`

Then inspect the existing repository (`history-service/` in particular) before writing anything — do not assume it is empty.

## Current stage

**Stage 1 of 4 — Foundation and database.**

## Stage goal

Produce a working PostgreSQL schema for the History Service: configuration, SQLAlchemy 2 models, Alembic migration, and constraint-level tests. No API endpoints yet.

## Scope

- `history-service/app/config.py` — environment-based configuration (`DATABASE_URL`, `DATABASE_ECHO`, `DATABASE_POOL_SIZE`, `DATABASE_MAX_OVERFLOW`).
- `history-service/app/database/base.py` and `session.py`.
- `history-service/app/models/` — `location.py`, `current_weather.py`, `daily_weather.py`, `hourly_weather.py`, `weather_sync.py`, exactly matching the fields and unique constraints in `docs/architecture.md` §8.
- Alembic setup (`alembic.ini`, `alembic/env.py`) and one initial migration creating all tables, constraints, and indexes.
- `history-service/requirements.txt`.
- Basic model/DB tests in `history-service/tests/` against a real PostgreSQL database.

## Out of scope

- No FastAPI routes/endpoints (that's Stage 2).
- No Backend or UI code.
- No Docker/CI.
- No SQLite, anywhere, for any reason.

## Architecture rules (must hold)

- Only the History Service accesses PostgreSQL — this stage only touches `history-service/`.
- Use database-level unique constraints as the final duplicate guard (per §8/§13 of the original spec, reflected in `docs/architecture.md` §8).
- All config comes from environment variables, no hardcoded connection strings.
- Timezone-aware datetimes only.

## Detailed tasks

1. Read the docs and inspect the repo as described above.
2. Implement configuration, database session/engine setup, and all 5 SQLAlchemy models.
3. Initialize Alembic and generate the first migration; verify it applies cleanly to an empty database.
4. Write tests proving: a location can be created; the `(latitude, longitude)` unique constraint rejects a duplicate; the `(location_id, weather_date)` unique constraint rejects a duplicate daily row; the `(location_id, weather_time)` unique constraint rejects a duplicate hourly row; `current_weather` unique-on-`location_id` rejects a second row for the same location.
5. Update `docs/project-status.md` (Stage 1 checklist) and `docs/troubleshooting.md` if you hit a real, non-obvious issue.

## Testing requirements

Use a real local PostgreSQL test database (e.g. `skyivano_test`), never SQLite. pytest.

## Verification commands

```bash
cd history-service
alembic upgrade head
psql "$DATABASE_URL" -c '\d current_weather'
DATABASE_URL=postgresql+psycopg://skyivano:skyivano@localhost:5432/skyivano_test pytest
```

## Documentation updates

- `docs/project-status.md`: mark Stage 1 items complete, set status, note next stage.
- `docs/troubleshooting.md`: add an entry under "Issues encountered during implementation" only for real problems you actually hit, with cause/diagnosis/fix/verification.
- Do not edit `docs/architecture.md` unless your implementation had to deviate from it — if so, update it and explain why in your report.

## Acceptance criteria

- PostgreSQL connection is fully configurable via env vars.
- All 5 models exist with correct fields and unique constraints.
- Migration applies cleanly to an empty database.
- Constraint tests pass and actually prove duplicates are rejected at the DB level.
- No SQLite anywhere.
- `docs/project-status.md` is updated.

## Required final report

At the end of this stage, report:
- Summary of what was built
- Changed files (list)
- Tests executed and their results
- Manual verification performed (commands + outcomes)
- Problems encountered
- Troubleshooting doc updates made
- Remaining work / anything deferred
- project-status.md updates made

## Stop condition

Do not start the next stage.
Stop after completing and reporting the current stage.
