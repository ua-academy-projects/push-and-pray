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
- Mode-aware durable delivery through RabbitMQ or PostgreSQL-backed PGMQ.
- Idempotent PostgreSQL persistence with source and collection timestamps.
- Interactive React charts with instrument, date-range, scale, style, comparison,
  smoothing, and moving-average controls.
- Redis- or PostgreSQL-backed UI preferences with a sliding 30-day TTL.
- Multi-stage Docker images and one Docker Compose project per VM.
- Four-machine Vagrant deployment using QEMU and static bridged LAN addresses.
- Passwordless project-specific SSH access and journald-based container logging.

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
| UI backend     | Python 3.12, FastAPI, httpx, psycopg, uv      |
| UI frontend    | React 19, TypeScript, Vite, Apache ECharts    |
| Messaging      | RabbitMQ (managed DB) or PGMQ (self-managed)  |
| Persistence    | PostgreSQL 18                                 |
| UI sessions    | Redis (managed DB) or PostgreSQL extensions   |
| Packaging      | Docker Engine and Docker Compose              |
| Virtualization | Vagrant, QEMU, Ubuntu 24.04 ARM64             |

## Architecture

The runtime is divided into three application services and two infrastructure
components.

| Component       | Responsibility                                                                                    | Owns                                             |
| --------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| Go Fetcher      | Runs the UTC schedule, calls OilPriceAPI, validates the response, and publishes price events      | External API integration and collection schedule |
| History Service | Consumes queue events, validates batches, persists observations, and exposes read endpoints       | Market history and PostgreSQL access             |
| UI Service      | Serves the React application, proxies read-only requests to History, and manages user preferences | Browser-facing HTTP API and sessions             |
| RabbitMQ/PGMQ   | Provides durable delivery between Fetcher and History according to database mode                  | Queue visibility, retries, and dead letters      |
| PostgreSQL      | Stores observations and, in self-managed mode, hashed UI sessions                                | Durable market data                              |

### Data flow

1. The Go Fetcher selects the current scheduled UTC slot.
2. It sends one HTTPS request to `https://api.oilpriceapi.com/v1/prices/latest` for all
   configured instruments.
3. The Fetcher publishes a versioned event to RabbitMQ in managed mode or to
   `price_observations` in PGMQ in self-managed mode.
4. In self-managed mode, the Fetcher records each event key in
   `published_queue_events` in the same transaction as the PGMQ publish.
5. History consumes from the selected durable queue with explicit acknowledgement.
6. History validates and commits observations to PostgreSQL before acknowledging or
   archiving the message.
7. Failed processing leaves the message available for retry.
8. Permanently invalid messages and exhausted retries are archived or dead-lettered.
9. The UI Service requests saved observations from History over HTTP.
10. The browser receives only persisted data through the UI Service.
11. UI preferences are stored in Redis in managed mode or PostgreSQL in self-managed mode.

Both queue implementations acknowledge messages only after successful observation
persistence. Database uniqueness on
`(instrument_code, scheduled_for)` keeps redelivery idempotent.

In managed mode, History is the only application VM granted the managed PostgreSQL
credential and network path. Fetcher reaches RabbitMQ, UI reaches History and Redis,
and neither needs a direct managed-database connection. In self-managed mode, the
Fetcher, History, and UI VMs can reach PostgreSQL on the infra VM because PGMQ and
PostgreSQL-backed sessions require it.

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
│   ├── docker/                     Dockerfiles and per-VM Compose files
│   └── vagrant/
│       ├── commands/               Host-side deployment commands
│       ├── config/                 Vagrant configuration template
│       └── provisioning/           Idempotent guest provisioning scripts
├── services/
│   ├── fetcher/                    Go scheduler, provider, and queue publishers
│   ├── history/                    Python History API and queue consumers
│   └── ui/
│       ├── backend/                Python UI gateway and pluggable sessions
│       └── frontend/               React and TypeScript application
├── .env.example                    Local application configuration template
├── pyproject.toml                  Python dependencies and tooling
├── uv.lock                         Locked Python dependencies
└── Vagrantfile                     Four-VM QEMU definition
```

## Vagrant deployment

Legacy Vagrant provisioning files remain in the repository, but cloud deployment is the
supported mode-aware path. Self-managed deployments use PGMQ; managed database
deployments use RabbitMQ and Redis on the infra VM.

## Docker deployment details

The supported production-style deployment pulls prebuilt GHCR images through
the `oilscope.platform.compose_project` Ansible role. See
[the supported Compose deployment guide](docs/supported-compose-deployment.md) for the
required parent-process environment, the one-command startup, independent VM roles,
shutdown, and smoke test.

The older role-specific files below remain for the Vagrant development topology:

| Compose file            | Project               | Services   |
| ----------------------- | --------------------- | ---------- |
| `compose.database.yaml` | `petroscope-database` | `postgres` |
| `compose.history.yaml`  | `petroscope-history`  | `history`  |
| `compose.fetcher.yaml`  | `petroscope-fetcher`  | `fetcher`  |
| `compose.ui.yaml`       | `petroscope-ui`       | `ui`       |

Containers on the same VM use their Compose network and service names. Communication
between VMs uses the configured bridged LAN addresses. PostgreSQL uses a named Docker volume. All containers use `restart: unless-stopped` and the journald
logging driver.

Journald is limited by provisioning to 200 MB and seven days per VM. Grafana and Loki are
not part of this project.

### Published application images

GitHub Actions builds and publishes every application image to GitHub Container Registry:

| Application | Image                                   |
| ----------- | --------------------------------------- |
| Fetcher     | `ghcr.io/<owner>/push-and-pray/fetcher` |
| History     | `ghcr.io/<owner>/push-and-pray/history` |
| UI          | `ghcr.io/<owner>/push-and-pray/ui`      |

Replace `<owner>` with the lowercase GitHub account or organization that owns the
repository. Every published image is tagged `xintaro`; this is a moving tag and
is replaced by the next successful CI run. The commit SHA remains in the OCI
revision label for tracing a published image back to its source revision.

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
| `GET`  | `/health`                 | PostgreSQL and selected queue status |
| `POST` | `/v1/observations/batch`  | Direct idempotent batch ingestion |
| `GET`  | `/v1/observations`        | Filtered and paginated history    |
| `GET`  | `/v1/observations/latest` | Latest observation per instrument |
| `GET`  | `/v1/instruments`         | Available instruments             |
| `GET`  | `/docs`                   | OpenAPI documentation             |

### UI Service (`:8080`)

| Method | Path                       | Purpose                                           |
| ------ | -------------------------- | ------------------------------------------------- |
| `GET`  | `/`                        | React application                                 |
| `GET`  | `/health`                  | History and selected session-store status          |
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

In self-managed mode, the `ui_sessions` table stores validated preferences in an hstore column, a 30-day
expiration timestamp, and only the SHA-256 digest of the browser session ID. Each preference
value is JSON-encoded inside the key/value hstore so lists, booleans, integers, nulls, and
strings retain the existing API representation. The digest is calculated inside PostgreSQL
by pgcrypto for every lookup and write. Atomic UPSERTs refresh the expiration on reads and
updates, while expired rows are replaced with defaults immediately. The pg_cron background
worker deletes expired rows every minute; its named job and the hstore, pgcrypto, and pg_cron
extensions are created idempotently by migration `003_create_ui_sessions.sql`. In managed
mode, the same validated preference document and sliding TTL are stored in Redis instead;
the managed PostgreSQL database receives only the extension-free core migrations.

## Configuration

| Variable                          | Default                 | Purpose                                  |
| --------------------------------- | ----------------------- | ---------------------------------------- |
| `OILPRICEAPI_KEY`                 | none                    | OilPriceAPI token                        |
| `DATA_PROVIDER`                   | `oilpriceapi`           | `oilpriceapi` or `mock`                  |
| `FETCH_CRON_HOURS`                | `0,6,12,18`             | Four distinct schedule hours             |
| `FETCH_TIMEZONE`                  | `UTC`                   | Schedule timezone                        |
| `FETCH_ON_STARTUP`                | `true`                  | Collect the latest slot after startup    |
| `REQUEST_TIMEOUT_SECONDS`         | `15`                    | External HTTP timeout                    |
| `DATABASE_URL`                    | see `.env.example`      | History and UI PostgreSQL connection     |
| `MESSAGING_PROVIDER`              | `pgmq`                  | `pgmq` or `rabbitmq` queue implementation |
| `RABBITMQ_URL`                    | none                    | RabbitMQ AMQP URL in managed mode        |
| `RABBITMQ_EXCHANGE`               | `oil.price.events`      | Durable direct exchange                  |
| `RABBITMQ_QUEUE`                  | `price_observations`    | RabbitMQ queue consumed by History       |
| `RABBITMQ_ROUTING_KEY`            | `prices.observed`       | RabbitMQ routing key                     |
| `RABBITMQ_MAX_ATTEMPTS`           | `5`                     | RabbitMQ processing attempts             |
| `PGMQ_QUEUE`                      | `price_observations`    | PostgreSQL queue name                    |
| `PGMQ_VISIBILITY_TIMEOUT_SECONDS` | `60`                    | Message visibility timeout               |
| `PGMQ_POLL_INTERVAL_SECONDS`      | `1`                     | Consumer polling interval                |
| `PGMQ_MAX_ATTEMPTS`               | `5`                     | Maximum processing attempts              |
| `HISTORY_SERVICE_URL`             | `http://127.0.0.1:8001` | UI-to-History base URL                   |
| `SESSION_PROVIDER`                | `postgresql`            | `postgresql` or `redis` session store    |
| `REDIS_URL`                       | none                    | Redis URL in managed mode                |
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

- Never commit `.env` or `infrastructure/vagrant/config/vagrant.env`. Run
  `pre-commit install` after cloning so this is enforced locally, not just by review.
- Replace all example passwords before deployment.
- Reserve the VM addresses and restrict sensitive LAN ports at the router or firewall when
  the network is not trusted.
- `SESSION_COOKIE_SECURE=false` is suitable only for local HTTP. Enable it behind HTTPS.
- PostgreSQL is exposed to the configured LAN for this lab deployment; production
  deployments should restrict its network exposure.
