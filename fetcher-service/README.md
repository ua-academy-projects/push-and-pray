# Weather Fetcher Service

The only service that calls Open-Meteo. Runs a scheduled synchronization independent of user traffic, normalizes the response, and pushes it to the Backend Service's internal API over HTTP. Never accesses PostgreSQL, never contains SQLAlchemy models, never serves data directly to the UI.

Full API contract, sync flow, and configuration reference: [../docs/architecture.md](../docs/architecture.md).

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # adjust BACKEND_INTERNAL_BASE_URL etc. if needed
```

Requires the Backend Service to be reachable (`BACKEND_INTERNAL_BASE_URL`) for pushing synced data — see [../backend-service/README.md](../backend-service/README.md). No PostgreSQL connection of its own.

## Run

```bash
uvicorn app.main:app --reload --port 8002
```

## Test

```bash
pytest
```

Tests mock Open-Meteo and the Backend Service HTTP client — no live network calls, no database.

## Manual fetch trigger (local/admin use only)

```bash
curl -X POST http://localhost:8002/internal/fetch
```

The UI must never call this endpoint. A user-facing manual refresh goes through the Backend's `POST /api/sync/trigger`, which proxies here.
