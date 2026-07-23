# Backend Service

Orchestration point of the system. Calls Open-Meteo, normalizes the response, runs the scheduled synchronization, and serves both the public API (used by the UI) and internal admin endpoints. Never accesses PostgreSQL directly — all persistence goes through the History Service over HTTP.

Full API contract, sync flow, and configuration reference: [../docs/architecture.md](../docs/architecture.md).

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # adjust HISTORY_SERVICE_BASE_URL etc. if needed
```

Requires the History Service to be running (see [../history-service/README.md](../history-service/README.md)).

## Run

```bash
uvicorn app.main:app --reload --port 8000
```

## Test

```bash
pytest
```

Tests mock Open-Meteo and the History Service HTTP client — no live network calls or database required.

## Manual sync trigger (local/admin use only)

```bash
curl -X POST http://localhost:8000/internal/weather/sync
```
