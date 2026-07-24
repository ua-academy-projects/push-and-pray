# Rateboard

[Українська версія](README.uk.md)

Rateboard is a three-service cryptocurrency and fiat dashboard built for DevOps Academy Assignment 1.

```text
Browser -> UI (HTML/CSS/JS) -> Backend (Python/FastAPI) -> CoinGecko / Frankfurter
                                    |
                                    +-> RabbitMQ -> History (Go) -> PostgreSQL
                                    +-> History HTTP (reads and write fallback)
```

The browser obtains all application data only from Backend; it additionally loads pinned Chart.js assets from jsDelivr. Backend owns public-provider access and orchestration. History is the only service that accesses PostgreSQL.

## Current features

- Bitcoin/USD headline with a full-width 7-day sparkline, top-10 cryptocurrency list with one-hour/day changes and compact 7-day sparklines, and 10 fiat pairs against UAH.
- Multiple removable full-width comparison cards stacked vertically; every crypto card includes a 7-day sparkline and refresh preserves the card layout.
- CoinGecko one-hour and one-day changes (`—` where a provider does not supply them).
- All displayed rates rounded to two decimal places; service/database precision remains unchanged.
- Searchable checkbox selection of up to five instruments per chart.
- Separate capitalization tab with proportional CoinGecko treemaps; green/red/gray encodes market-cap growth, decline, or negligible change.
- Multiple independent capitalization maps for `1h`, `4h`, `1d`, `7d`, `30d`, and `1y` periods.
- Capitalization-tile typography scales with each rectangle; symbol and capitalization remain visible in tiny tiles while the percentage change is hidden first.
- Separate dynamic chart cards backed by PostgreSQL, with independent data periods (`1d`, `7d`, `30d`, `90d`, `1y`) and aggregation steps (`5m`, `30m`, `1h`, `4h`, `1d`). Existing charts refresh automatically on five-minute wall-clock boundaries while the page is visible.
- Clean chart lines with proximity-based exact timestamp/value tooltips, plus per-chart pan/zoom/reset, refresh-all, and clear-all.
- Structured print/PDF report containing generation time to the second, all current overview cards, every capitalization map, every graph (or unavailable-data messages), and Rateboard footer.
- Persistent accessible light/dark theme.
- Five-minute background collector while Backend is running.
- Idempotent PostgreSQL persistence and manual annual backfill.

## Prerequisites

- Python 3.12+
- Go 1.23+
- PostgreSQL 16+
- RabbitMQ 4+
- `psql`, `pg_isready`, and `curl`
- A browser and internet access for providers and pinned Chart.js CDN assets

On macOS/Homebrew, `start-all.sh` can start installed PostgreSQL 16 and RabbitMQ services. On other systems both must already be running when RabbitMQ is enabled.

## First-time setup

Create local configuration. `.env` is excluded by both Git and Codex ignore rules:

```sh
cp .env.example .env
```

Set a unique `API_FETCHER_TOKEN`. `COINGECKO_API_KEY` is optional for keyless access but recommended for rate limits. Never commit `.env` or API-key files.

Create the database and role if they do not already exist. The exact administrative command depends on your PostgreSQL installation; the default application URL expects database/user/password `rates`:

```text
postgres://rates:rates@127.0.0.1:5432/rates?sslmode=disable
```

Then either use automatic start or run each service manually.

## Start everything

```sh
./scripts/start-all.sh
```

The script:

1. loads `.env`, validates all service/orchestration settings, and checks required commands;
2. checks PostgreSQL and RabbitMQ and starts their Homebrew services when available;
3. applies all History migrations (`001_init.sql`, `002_sampling.sql`, and `003_backfill_timestamps.sql`);
4. downloads Go modules and starts History;
5. creates/installs the Python virtualenv when missing and starts Backend;
6. starts the static UI server;
7. optionally runs annual backfill when `BACKFILL_YEAR_ON_START=1`;
8. writes logs to `.run/` and stops UI, Backend, and History on Ctrl+C.

Startup probes, graceful-shutdown retries, their intervals, and the optional Homebrew PostgreSQL binary directory are configured through the `SERVICE_*` and `POSTGRES_BIN_DIR` values documented in `.env.example`; `start-all.sh` does not provide hidden configuration defaults.

PostgreSQL and RabbitMQ are infrastructure dependencies and are not stopped by the script.

To stop any Rateboard listeners and free ports `3000`, `8000`, and `8081`:

```sh
./scripts/stop-all.sh
```

Open:

- UI: `http://127.0.0.1:3000`
- Backend Swagger: `http://127.0.0.1:8000/docs`
- Backend health: `http://127.0.0.1:8000/health/live`

## Manual start

Apply the migration and start History:

```sh
set -a
source .env
set +a
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f api-fetcher/migrations/001_init.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f api-fetcher/migrations/002_sampling.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f api-fetcher/migrations/003_backfill_timestamps.sql
cd api-fetcher
go mod download
go run ./cmd/server
```

In another terminal, start Backend:

```sh
set -a
source .env
set +a
cd backend-service
python3 -m venv .venv
. .venv/bin/activate
pip install -e '.[dev]'
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

In a third terminal, start UI:

```sh
cd ui-service/public
python3 -m http.server 3000 --bind 127.0.0.1
```

Start order: PostgreSQL → RabbitMQ → History → Backend → UI.

RabbitMQ carries durable observation writes from Backend to API Fetcher. The durable direct exchange is `rates.events`, the main queue is `rates.observations`, and failed redeliveries go to `rates.observations.dlq`. API Fetcher acknowledges a message only after PostgreSQL accepts the insert. If publishing fails, Backend falls back to the authenticated API Fetcher HTTP write endpoint.

## Automatic collection

Backend owns the scheduler. It aligns collection to absolute clock boundaries. With the default interval, cycles begin at `:00`, `:05`, `:10`, `:15`, and so on, regardless of when Backend was started:

```env
COLLECTOR_ENABLED=true
COLLECTOR_INTERVAL_SECONDS=300
```

Each cycle fetches all 20 configured instruments with fresh provider requests and sends successful observations to API Fetcher. Failures are isolated per instrument and logged without stopping the cycle. Values below 60 seconds are clamped to 60.

Every cycle is stored with its aligned `requested_at` sample time. Frankfurter can keep the same daily `source_timestamp` and value, but PostgreSQL still records each five-minute observation; this represents when Rateboard sampled the source, not a fabricated provider update.

## Annual backfill

With PostgreSQL, History, and Backend running:

```sh
./scripts/backfill-year.sh
```

Override dates when needed:

```sh
BACKFILL_FROM=2025-01-01 BACKFILL_TO=2025-12-31 ./scripts/backfill-year.sh
```

The script requests 10 configured cryptocurrencies in USD and 10 fiat pairs against UAH. Re-running is safe: backfill uses the point timestamp as `requested_at`, and uniqueness is enforced on `(source, instrument_id, source_timestamp, requested_at)`.

Provider granularity is not uniformly five minutes:

- CoinGecko: one-day requests use automatic ~5-minute data; 2–90 days are hourly; over 90 days are daily.
- CoinGecko forced `5m` history is limited by provider plan and cannot supply a full year.
- Frankfurter publishes daily reference rates only.

Backfill retains the providers' native historical granularity; only new collector samples are guaranteed every five minutes while the services are running.

## Tests

```sh
cd backend-service && .venv/bin/pytest -q
cd api-fetcher && go test ./...
node --test ui-service/tests/*.test.js
bash -n scripts/start-all.sh scripts/backfill-year.sh
```

Current automated coverage focuses on Python models/parsing/cache utilities and frontend formatting/theme utilities. Go packages compile through `go test`, but currently contain no dedicated test files. See `docs/architecture.md` and `docs/api.md` for implementation details.

## Assignment status and defense materials

The core three-service architecture, relational persistence, current-data retrieval, refresh, and stored-series charts are implemented. The History tab reads PostgreSQL observations through Backend and supports selectable aggregation steps. Normal Overview reads are intentionally not persisted; explicit refreshes, the five-minute collector, and backfill are persisted.

- `docs/assignment-compliance.md` maps every Assignment 1 requirement to the current implementation.
- `docs/defense-guide.md` contains the recommended defense narrative and 50 likely technical questions with concise answers.
