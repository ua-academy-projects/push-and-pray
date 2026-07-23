# Backend Service

Calls Open-Meteo, normalizes the response, runs the scheduled synchronization, persists directly to PostgreSQL, and serves both the public API (used by the UI) and internal admin endpoints. As of the refactor's Stage 1 (`../docs/prompts/refactor-1-backend-database.md`), this service owns PostgreSQL directly — the separate History Service is retired (`../docs/architecture.md` §2). The Open-Meteo/scheduler half of this service is planned to move out into a separate Fetcher Service in Stage 2.

Full API contract, sync flow, and configuration reference: [../docs/architecture.md](../docs/architecture.md).

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # set DATABASE_URL for your local PostgreSQL instance
alembic upgrade head
```

Requires a running PostgreSQL instance — see the root [README.md](../README.md) for local setup. No other service needs to be running first.

## Run

```bash
uvicorn app.main:app --reload --port 8000
```

## Test

```bash
DATABASE_URL=postgresql+psycopg://skyivano:skyivano@localhost:5432/skyivano_test pytest
```

Requires real PostgreSQL — every test in this suite is now gated by a test-database check (moved here from the old History Service), not just the persistence tests. No SQLite, no mocked database.

## Manual sync trigger (local/admin use only)

```bash
curl -X POST http://localhost:8000/internal/weather/sync
```
