# Oil Price Tracker

Oil Price Tracker is a small research-oriented, multi-service application for collecting,
storing, and visualizing oil and gasoline market prices. It tracks WTI crude oil, Brent
crude oil, and RBOB gasoline through OilPriceAPI.

The system deliberately separates data collection from presentation. The browser never
calls the external market API or the Fetcher directly. It reads only observations that
have already been persisted in PostgreSQL.

## Features

- Scheduled collection at `00:00`, `06:00`, `12:00`, and `18:00` UTC.
- One OilPriceAPI batch request for WTI, Brent, and RBOB per collection slot.
- Asynchronous, durable delivery through PGMQ in self-hosted mode or RabbitMQ in
  managed-database mode.
- Idempotent PostgreSQL persistence with source and collection timestamps.
- Interactive React charts with instrument, date-range, scale, style, comparison,
  smoothing, and moving-average controls.
- Redis-backed UI preferences with a sliding 30-day TTL.
- Multi-stage Docker images and one Docker Compose project per VM.
- Passwordless project-specific SSH access and provider-native monitoring/log shipping.

## Screenshots

### Application overview

![Oil Price Tracker application overview](assets/screenshots/application-overview.png)

### Latest market snapshot

![Latest persisted WTI, Brent, and RBOB values](assets/screenshots/market-snapshot.png)

### Interactive market analysis

![Interactive chart controls and RBOB price history](assets/screenshots/market-analysis.png)

### Individual benchmark charts

| WTI Crude Oil                                                        | Brent Crude Oil                                                          |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| ![WTI Crude Oil price chart](assets/screenshots/wti-price-chart.png) | ![Brent Crude Oil price chart](assets/screenshots/brent-price-chart.png) |

### Persisted observation ledger

![PostgreSQL-backed market observation ledger](assets/screenshots/observation-ledger.png)

## Technology stack

| Area           | Technology                                    |
| -------------- | --------------------------------------------- |
| Fetcher        | Go 1.24                                       |
| History API    | Python 3.12, FastAPI, SQLAlchemy, psycopg, uv |
| UI backend     | Python 3.12, FastAPI, httpx, redis-py, uv     |
| UI frontend    | React 19, TypeScript, Vite, Apache ECharts    |
| Messaging      | PGMQ (self-hosted) or RabbitMQ 4 (managed)    |
| Persistence    | PostgreSQL 18 (self-hosted), PostgreSQL 16 managed |
| UI sessions    | Redis 8                                       |
| Packaging      | Docker Engine and Docker Compose              |

## Architecture

The deployment has two independent selectors. `default_cloud` chooses where the
whole deployment runs (`gcp` or `aws`); `database_mode` chooses how messaging and
PostgreSQL are provided (`self_hosted` or `managed`). One deployment uses one cloud.
Private AWS-to-GCP application routing is outside scope.

| Component       | Responsibility                                                                                    | Owns                                             |
| --------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| Go Fetcher      | Runs the UTC schedule, calls OilPriceAPI, validates the response, and publishes price events      | External API integration and collection schedule |
| History Service | Consumes queue events, validates batches, persists observations, and exposes read endpoints        | Market history and PostgreSQL access             |
| UI Service      | Serves the React application, proxies read-only requests to History, and manages user preferences | Browser-facing HTTP API and sessions             |
| PGMQ            | Provides a durable PostgreSQL-backed queue between Fetcher and History                            | Queue visibility, retries, and message archiving |
| RabbitMQ        | Provides durable Fetcher-to-History delivery in managed mode                                     | Managed-mode queue delivery                      |
| PostgreSQL      | Stores persistent market observations and queue-publication records                               | Durable market data                              |
| Redis           | Stores UI preferences with sliding expiration                                                      | Ephemeral session state                          |

### Runtime modes

```text
self_hosted                         managed
Fetcher -> PGMQ -> History          Fetcher -> RabbitMQ -> History
                 -> PostgreSQL                              -> RDS / Cloud SQL
UI -> Redis                         UI -> Redis
```

In `self_hosted`, the infra VM runs PostgreSQL 18 with PGMQ plus Redis. PGMQ
messages are archived only after persistence, and the visibility timeout makes failed
deliveries retryable. In `managed`, the infra VM runs RabbitMQ and Redis but no local
PostgreSQL service; the migration runner and History connect with TLS to private
PostgreSQL 16 in AWS RDS or GCP Cloud SQL. Migration `004_create_pgmq_queue.sql` is
therefore skipped only in managed mode.

In both modes, the browser reads persisted data through UI and History, UI preferences
live only in authenticated Redis, and uniqueness on `(instrument_code, scheduled_for)`
keeps redelivery idempotent.

AWS deployments use EC2, security groups, Secrets Manager, and CloudWatch; managed
mode adds private RDS PostgreSQL 16. GCP deployments use Compute Engine, firewall rules,
Secret Manager, Cloud Logging, and Cloud Monitoring; managed mode adds private Cloud SQL
PostgreSQL 16. Traefik JSON access logs feed each provider's logging service, HTTP 5xx
metric, and alert path without replacing CPU, VM-health, or lifecycle monitoring.

## Tracked instruments

| Internal code           | OilPriceAPI code  | Instrument      | Unit       |
| ----------------------- | ----------------- | --------------- | ---------- |
| `WTI_USD_BBL`           | `WTI_USD`         | WTI Crude Oil   | USD/barrel |
| `BRENT_USD_BBL`         | `BRENT_CRUDE_USD` | Brent Crude Oil | USD/barrel |
| `RBOB_GASOLINE_USD_GAL` | `GASOLINE_USD`    | RBOB Gasoline   | USD/gallon |

RBOB is a wholesale exchange-traded gasoline product, not the retail price at a specific
fuel station. Source timestamps come from OilPriceAPI; collection timestamps do not imply
that the upstream market value changed four times per day.

The Fetcher performs up to four HTTP attempts with exponential backoff. A deterministic
`mock` provider is available for offline development, but mock observations are not a
scientific data source.

## Repository layout

```text
.
├── assets/
│   └── screenshots/                Application screenshots
├── database/
│   └── migrations/                 PostgreSQL migrations
├── infrastructure/
│   ├── ansible/                    Multi-cloud deployment automation
│   ├── docker/                     Dockerfiles and local Compose configuration
│   ├── legacy/vagrant/             Archived earlier-sprint Vagrant deployment
│   ├── ssh/                        SSH configuration example
│   └── terraform/                  GCP and AWS infrastructure
├── services/
│   ├── fetcher/                    Go scheduler and PGMQ/RabbitMQ publisher
│   ├── history/                    Python History API and PGMQ/RabbitMQ consumer
│   └── ui/
│       ├── backend/                Python UI gateway and Redis sessions
│       └── frontend/               React and TypeScript application
├── .env.example                    Local application configuration template
├── pyproject.toml                  Python dependencies and tooling
└── uv.lock                         Locked Python dependencies
```

## Docker deployment details

The supported production-style deployment pulls prebuilt GHCR images through
the `oilscope.platform.compose_project` Ansible role. See
[the supported Compose deployment guide](docs/supported-compose-deployment.md) for the
required parent-process environment, the one-command startup, independent VM roles,
shutdown, and smoke test.

### Published application images

GitHub Actions builds and publishes every application image to GitHub Container Registry:

| Application | Image                                   |
| ----------- | --------------------------------------- |
| Fetcher     | `ghcr.io/<owner>/push-and-pray/fetcher` |
| History     | `ghcr.io/<owner>/push-and-pray/history` |
| UI          | `ghcr.io/<owner>/push-and-pray/ui`      |

Replace `<owner>` with the lowercase GitHub account or organization that owns the
repository. Every published image receives the full commit SHA as an immutable tag.
Additional moving tags identify the delivery channel:

- pushes to `develop`: `develop` and `integration`;
- pushes to `main`: `main` and `latest`;
- release tags matching `v*`: the Git tag and, for semantic versions, normalized version
  and `major.minor` tags (for example `v1.4.2`, `1.4.2`, and `1.4`).

Images are pushed only after a successful Buildx build. The registry login uses the
workflow-scoped `GITHUB_TOKEN`, which GitHub Actions masks in logs; workflows do not print
or pass the token as a Docker build argument.

## Local development

Local development requires Python 3.12+, uv, Go 1.24+, Node.js, PostgreSQL 18 with
hstore, pgcrypto, pg_cron, and PGMQ.

Install Python dependencies and build the frontend:

```bash
uv sync
npm ci --prefix services/ui/frontend
npm run build --prefix services/ui/frontend
```

Apply the database migrations:

```bash
for migration in database/migrations/*.sql; do
  PGPASSWORD=change-me psql \
    -h 127.0.0.1 \
    -U oil_tracker \
    -d oil_tracker \
    -v ON_ERROR_STOP=1 \
    -f "${migration}"
done
```

Start the History Service:

```bash
uv run --frozen --env-file .env \
  uvicorn --app-dir services/history/src \
  history_service.main:app --host 127.0.0.1 --port 8001
```

Start the Fetcher in a second terminal:

```bash
set -a
source .env
set +a
cd services/fetcher
go run ./cmd/fetcher
```

Start the UI Service in a third terminal:

```bash
uv run --frozen --env-file .env \
  uvicorn --app-dir services/ui/backend/src \
  ui_service.main:app --host 127.0.0.1 --port 8080
```

Open `http://localhost:8080`.

`uv` manages the local `.venv` automatically. Do not create or activate it manually;
run Python tools through `uv run`.

## HTTP API

### Fetcher (`:8002`)

| Method | Path        | Purpose                                                  |
| ------ | ----------- | -------------------------------------------------------- |
| `GET`  | `/health`   | Provider, schedule, next run, and last collection status |
| `POST` | `/v1/fetch` | Run the latest scheduled slot manually                   |

### History Service (`:8001`)

| Method | Path                      | Purpose                           |
| ------ | ------------------------- | --------------------------------- |
| `GET`  | `/health`                 | PostgreSQL and selected messaging status |
| `POST` | `/v1/observations/batch`  | Direct idempotent batch ingestion |
| `GET`  | `/v1/observations`        | Filtered and paginated history    |
| `GET`  | `/v1/observations/latest` | Latest observation per instrument |
| `GET`  | `/v1/instruments`         | Available instruments             |
| `GET`  | `/docs`                   | OpenAPI documentation             |

### UI Service (`:8080`)

| Method | Path                       | Purpose                                           |
| ------ | -------------------------- | ------------------------------------------------- |
| `GET`  | `/`                        | React application                                 |
| `GET`  | `/health`                  | History and Redis status                           |
| `GET`  | `/api/observations`        | Read-only proxy to persisted history              |
| `GET`  | `/api/latest`              | Read-only proxy to latest persisted values        |
| `GET`  | `/api/instruments`         | Read-only proxy to instruments                    |
| `GET`  | `/api/session/preferences` | Read or create UI preferences                     |
| `PUT`  | `/api/session/preferences` | Update UI preferences                             |

## Data model

The `price_observations` table stores exact decimal prices, normalized instrument data,
source metadata, and four different time concepts:

| Column               | Meaning                           |
| -------------------- | --------------------------------- |
| `source_period`      | Source calendar date              |
| `source_observed_at` | Exact upstream market timestamp   |
| `scheduled_for`      | Fetcher's scheduled UTC slot      |
| `fetched_at`         | Actual external HTTP request time |
| `created_at`         | PostgreSQL insertion time         |

The original upstream price object is retained in `raw_data` as JSONB. SQL migrations are
ordered in `database/migrations/` and are safe to apply repeatedly.

UI session preferences use Redis keys named `ui:session:<session-id>`. Reads refresh a
30-day TTL, malformed values reset to validated defaults, and the Redis server requires
authentication. The legacy `ui_sessions` schema and its pg_cron cleanup remain migration
compatible, but the application no longer writes session state to PostgreSQL. The hstore,
pgcrypto, and pg_cron
extensions are created idempotently by migration `003_create_ui_sessions.sql`.

## Configuration

Copy the single tracked template `project-config.example.json` to the ignored local
`project-config.json`. Terraform and Ansible receive that path through
`project_config_path`; no provider- or mode-specific filename has special meaning. Change
`default_cloud` to select AWS or GCP and `database_mode` to select `self_hosted` or
`managed`. See [configuration ownership](docs/configuration.md).

| Variable                          | Default                 | Purpose                                  |
| --------------------------------- | ----------------------- | ---------------------------------------- |
| `OILPRICEAPI_KEY`                 | none                    | OilPriceAPI token                        |
| `DATA_PROVIDER`                   | `oilpriceapi`           | `oilpriceapi` or `mock`                  |
| `FETCH_CRON_HOURS`                | `0,6,12,18`             | Four distinct schedule hours             |
| `FETCH_TIMEZONE`                  | `UTC`                   | Schedule timezone                        |
| `FETCH_ON_STARTUP`                | `true`                  | Collect the latest slot after startup    |
| `REQUEST_TIMEOUT_SECONDS`         | `15`                    | External HTTP timeout                    |
| `DATABASE_URL`                    | see `.env.example`      | History, plus Fetcher only with PGMQ |
| `MESSAGING_BACKEND`               | `pgmq`                  | `pgmq` or `rabbitmq` |
| `RABBITMQ_HOST` / `RABBITMQ_PORT` | empty / `5672`          | Managed-mode broker endpoint |
| `REDIS_URL`                       | `redis://localhost:6379/0` | UI session storage                     |
| `PGMQ_QUEUE`                      | `price_observations`    | PostgreSQL queue name                    |
| `PGMQ_VISIBILITY_TIMEOUT_SECONDS` | `60`                    | Message visibility timeout               |
| `PGMQ_POLL_INTERVAL_SECONDS`      | `1`                     | Consumer polling interval                |
| `PGMQ_MAX_ATTEMPTS`               | `5`                     | Maximum processing attempts              |
| `HISTORY_SERVICE_URL`             | `http://127.0.0.1:8001` | UI-to-History base URL                   |
| `SESSION_TTL_SECONDS`             | `2592000`               | Sliding session TTL, 30 days             |
| `SESSION_COOKIE_SECURE`           | `false`                 | Secure-cookie flag for HTTPS deployments |
| `LISTEN_ADDRESS`                  | `:8002`                 | Fetcher diagnostic API address           |
| `LOG_LEVEL`                       | `INFO`                  | Python service log level                 |

## Pre-commit hooks

Local checks that run at `git commit`, so a leaked credential is caught while it
is still only in your working copy. Once a secret reaches a public repository,
deleting the commit does not undo it — the value has to be treated as
compromised and rotated at its source. This is the cheapest place to stop that.

Install `pre-commit` once (any of these):

```bash
brew install pre-commit          # macOS
uv tool install pre-commit       # anywhere uv is available
pipx install pre-commit
```

Then, once per clone:

```bash
pre-commit install
```

Check the current working tree straight away — the first run also downloads the
hook environments, so it takes a minute:

```bash
pre-commit run --all-files
```

What runs on every commit:

| Hook                  | Catches                                                                                                                                   |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `gitleaks`            | Credentials in the staged diff, by pattern. Scans only what you are committing, not the whole history                                     |
| `detect-private-key`  | PEM and OpenSSH private key blocks, by structure rather than by pattern                                                                   |
| `forbid-secret-files` | Whole file classes that must never be committed: `.env*`, `*.tfvars`, `*.tfstate*`, `*.pem`, `*.key`, `id_rsa`/`id_ed25519`, `*-key.json` |

The last one exists because `.gitignore` is bypassed by `git add -f`, by a path
nobody thought to add, and by anyone who edits their local copy. `.env.example`
and `*.pub` are allowed through.

Two honest caveats:

- **These hooks are local and skippable.** `git commit --no-verify` walks past
  all of them. They are a first line of defence, not the enforcement point —
  the `Secret scan` job in `.github/workflows/security.yml` is what actually
  blocks a merge.
- **If a secret is already committed**, removing it in a later commit is not
  enough; it stays in the history. Rotate the credential at its source first,
  then clean up. See [`docs/secrets.md`](docs/secrets.md).

If the `gitleaks` hook fails to build on your machine, swap it for the
container-based variant in `.pre-commit-config.yaml`:

```yaml
- id: gitleaks-docker
```

## Tests and checks

```bash
uv run pytest
uv run ruff check .
(cd services/fetcher && go test ./...)
(cd services/ui/frontend && npm run typecheck && npm run build)
```

## Security notes

- Never commit `.env` or local deployment configuration containing credentials. Run
  `pre-commit install` after cloning so this is enforced locally, not just by review.
- Replace all example passwords before deployment.
- Reserve the VM addresses and restrict sensitive LAN ports at the router or firewall when
  the network is not trusted.
- `SESSION_COOKIE_SECURE=false` is suitable only for local HTTP. Enable it behind HTTPS.
- Self-hosted PostgreSQL is private to the workload network. Managed RDS and Cloud SQL
  use private endpoints only; the infra VM does not publish PostgreSQL in managed mode.
