# History Service

Owns and exclusively accesses the PostgreSQL database. Persists weather data sent by the Backend Service and serves it back on request. Never calls Open-Meteo.

Full API contract and schema: [../docs/architecture.md](../docs/architecture.md).

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # adjust DATABASE_URL if needed
createdb skyivano       # if not already created
alembic upgrade head
```

## Run

```bash
uvicorn app.main:app --reload --port 8001
```

## Test

Tests run against real PostgreSQL (no SQLite). Point `DATABASE_URL` at a dedicated test database:

```bash
createdb skyivano_test
DATABASE_URL=postgresql+psycopg://skyivano:skyivano@localhost:5432/skyivano_test pytest
```

## Migrations

```bash
alembic revision --autogenerate -m "description"
alembic upgrade head
alembic downgrade -1
```
