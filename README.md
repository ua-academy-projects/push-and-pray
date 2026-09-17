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
- Selectable durable delivery through PGMQ or RabbitMQ.
- Idempotent PostgreSQL persistence with source and collection timestamps.
- Interactive React charts with instrument, date-range, scale, style, comparison,
  smoothing, and moving-average controls.
- PostgreSQL- or Redis-backed UI preferences with a sliding 30-day TTL.
- Multi-stage Docker images and role-specific Docker Compose projects.
- Four-machine Vagrant deployment using QEMU and static bridged LAN addresses.
- Terraform deployments on AWS and GCP with Ansible-managed workloads and
  cloud-provider observability.

See [Cloud monitoring](docs/monitoring.md) for the Terraform-managed alerts,
log metrics, HTTPS checks, and manual notification prerequisites.

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
| Fetcher        | Go 1.25                                       |
| History API    | Python 3.12, FastAPI, SQLAlchemy, psycopg, uv |
| UI backend     | Python 3.12, FastAPI, httpx, psycopg, uv      |
| UI frontend    | React 19, TypeScript, Vite, Apache ECharts    |
| Messaging      | PGMQ or RabbitMQ                              |
| Persistence    | PostgreSQL 18                                 |
| UI sessions    | PostgreSQL extensions or Redis                |
| Packaging      | Docker Engine and Docker Compose              |
| Infrastructure | Terraform, AWS, Google Cloud                  |
| Automation     | Ansible                                       |
| Virtualization | Vagrant, QEMU, Ubuntu 24.04 ARM64             |

## Architecture

The runtime is divided into three application services and a selectable set of
infrastructure services.

Cloud deployments select one of two database architectures with `database.mode`
in `project-config.json`. A self-managed database deployment
(`self_managed`) runs PostgreSQL with PGMQ and the session extensions on the
infrastructure VM. A managed database deployment (`managed`) provisions private
Cloud SQL or RDS PostgreSQL, runs RabbitMQ and Redis on the infrastructure VM,
and uses no PostgreSQL extensions. GCP clients reach Cloud SQL through the Auth
Proxy with private IP; AWS clients use the private RDS endpoint.

| Component        | Responsibility                                                                                    | Owns                                             |
| ---------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| Go Fetcher       | Runs the UTC schedule, calls OilPriceAPI, validates the response, and publishes price events      | External API integration and collection schedule |
| History Service  | Consumes price events, validates batches, persists observations, and exposes read endpoints       | Market history and PostgreSQL access             |
| UI Service       | Serves the React application, proxies read-only requests to History, and manages user preferences | Browser-facing HTTP API and sessions             |
| PGMQ or RabbitMQ | Provides the selected event transport between Fetcher and History                               | Delivery, retries, and failed-message handling   |
| PostgreSQL       | Stores observations and, for a self-managed database, hashed UI sessions                         | Durable market data                              |
| Redis            | Stores expiring UI sessions for a managed database deployment                                   | Managed-database session state                   |

### Data flow

1. The Go Fetcher selects the current scheduled UTC slot.
2. It sends one HTTPS request to `https://api.oilpriceapi.com/v1/prices/latest` for all
   configured instruments.
3. The Fetcher publishes a versioned event through the selected messaging backend:
   PGMQ for a self-managed database or RabbitMQ for a managed database.
4. History consumes and validates the event, then persists its observations to
   PostgreSQL before acknowledging successful processing.
5. Failed events remain eligible for retry according to the selected backend's
   delivery behavior. Permanently invalid RabbitMQ messages are dead-lettered;
   PGMQ messages that exceed the retry limit are archived.
6. The UI Service requests saved observations from History over HTTP.
7. The browser receives only persisted data through the UI Service.
8. UI preferences are stored in PostgreSQL for a self-managed database deployment
   or Redis for a managed database deployment.

With a self-managed database, PGMQ provides durable queue storage inside
PostgreSQL. Messages are archived only after successful observation persistence;
otherwise, the visibility timeout makes them available again. With a managed
database, RabbitMQ provides event delivery and dead-letter handling. Database
uniqueness on `(instrument_code, scheduled_for)` keeps redelivery idempotent in
both architectures.

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
│   ├── ansible/                    Cloud inventory and workload automation
│   ├── docker/                     Dockerfiles and local Compose files
│   ├── ssh/                        Example SSH client configuration
│   ├── terraform/                  AWS and GCP infrastructure modules
│   └── vagrant/
│       ├── commands/               Host-side deployment commands
│       ├── config/                 Vagrant configuration template
│       └── provisioning/           Idempotent guest provisioning scripts
├── services/
│   ├── fetcher/                    Go scheduler, provider, and event publisher
│   ├── history/                    Python History API and event consumer
│   └── ui/
│       ├── backend/                Python UI gateway and session persistence
│       └── frontend/               React and TypeScript application
├── .env.example                    Local application configuration template
├── project-config.*.example.json   Self-managed and managed database examples
├── project-config.schema.json      Deployment configuration schema
├── pyproject.toml                  Python dependencies and tooling
├── uv.lock                         Locked Python dependencies
└── Vagrantfile                     Four-VM QEMU definition
```

## Vagrant deployment

Legacy Vagrant provisioning files remain in the repository, but they are not part
of the currently supported cloud deployment paths. The current application
architectures are validated through Docker and cloud-oriented deployments using
either a self-managed PostgreSQL database with PGMQ or a managed PostgreSQL
database with RabbitMQ and Redis.

## Docker deployment details

The supported production-style deployment uses the `oilscope.platform`
Ansible collection to install one role-specific Compose definition on each
workload VM and pull prebuilt registry images. See
[the supported Compose deployment guide](docs/supported-compose-deployment.md)
for the deployment order, secrets flow, and operating commands.

The older role-specific files below remain for the Vagrant development topology:

| Compose file            | Project               | Services   |
| ----------------------- | --------------------- | ---------- |
| `compose.database.yaml` | `petroscope-database` | `postgres` |
| `compose.history.yaml`  | `petroscope-history`  | `history`  |
| `compose.fetcher.yaml`  | `petroscope-fetcher`  | `fetcher`  |
| `compose.ui.yaml`       | `petroscope-ui`       | `ui`       |

Containers on the same VM use their Compose network and service names.
Communication between cloud VMs uses their configured private addresses, and
PostgreSQL uses a named Docker volume. The current Ansible deployment leaves
Docker's JSON logging enabled so the GCP Ops Agent or AWS CloudWatch Agent can
collect workload logs. The legacy Vagrant Compose files use journald.

### Published application images

GitHub Actions builds and publishes every application image to GitHub Container Registry:

| Application | Image                                   |
| ----------- | --------------------------------------- |
| Database    | `ghcr.io/<owner>/push-and-pray/database` |
| Fetcher     | `ghcr.io/<owner>/push-and-pray/fetcher` |
| History     | `ghcr.io/<owner>/push-and-pray/history` |
| UI          | `ghcr.io/<owner>/push-and-pray/ui`      |

Replace `<owner>` with the lowercase GitHub account or organization that owns the
repository. Every published image receives the full commit SHA as an immutable tag.
Branch pushes to `develop` or `main` publish the full commit SHA only. A pushed
Git tag matching `v*` or `andrii-miroshnyk-*` publishes both the full commit SHA
and that exact Git tag. The workflow does not create moving branch, `latest`, or
normalized semantic-version tags.

Images are pushed only after a successful Buildx build. The registry login uses the
workflow-scoped `GITHUB_TOKEN`, which GitHub Actions masks in logs; workflows do not print
or pass the token as a Docker build argument.

For isolated development, push a personal Git tag matching
`andrii-miroshnyk-*` and select that exact tag through `registry.image_tag` in
`project-config.json`. Prefer immutable release tags for shared deployments.

## Local development

Local development requires Python 3.12+, uv, Go 1.25+, Node.js, PostgreSQL 18 with
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
| `GET`  | `/health`                 | PostgreSQL and selected messaging-backend status |
| `POST` | `/v1/observations/batch`  | Direct idempotent batch ingestion |
| `GET`  | `/v1/observations`        | Filtered and paginated history    |
| `GET`  | `/v1/observations/latest` | Latest observation per instrument |
| `GET`  | `/v1/instruments`         | Available instruments             |
| `GET`  | `/docs`                   | OpenAPI documentation             |

### UI Service (`:8080`)

| Method | Path                       | Purpose                                           |
| ------ | -------------------------- | ------------------------------------------------- |
| `GET`  | `/`                        | React application                                 |
| `GET`  | `/health`                  | History and selected session-backend status      |
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

For a self-managed database deployment, the `ui_sessions` table stores validated
preferences in an hstore column, a 30-day
expiration timestamp, and only the SHA-256 digest of the browser session ID. Each preference
value is JSON-encoded inside the key/value hstore so lists, booleans, integers, nulls, and
strings retain the existing API representation. The digest is calculated inside PostgreSQL
by pgcrypto for every lookup and write. Atomic UPSERTs refresh the expiration on reads and
updates, while expired rows are replaced with defaults immediately. The pg_cron background
worker deletes expired rows every minute; its named job and the hstore, pgcrypto, and pg_cron
extensions are created idempotently by migration `003_create_ui_sessions.sql`.

## Configuration

| Variable                          | Default              | Purpose                                      |
| --------------------------------- | -------------------- | -------------------------------------------- |
| `OILPRICEAPI_KEY`                 | none                 | OilPriceAPI token                            |
| `DATA_PROVIDER`                   | `oilpriceapi`        | `oilpriceapi` or `mock`                      |
| `FETCH_CRON_HOURS`                | `0,6,12,18`          | Four distinct schedule hours                 |
| `FETCH_TIMEZONE`                  | `UTC`                | Schedule timezone                            |
| `FETCH_ON_STARTUP`                | `true`               | Collect the latest slot after startup        |
| `REQUEST_TIMEOUT_SECONDS`         | `15`                 | External HTTP timeout                        |
| `DATABASE_URL`                    | see `.env.example`   | History and UI PostgreSQL connection         |
| `MESSAGING_BACKEND`               | `pgmq`               | `pgmq` or `rabbitmq`                         |
| `RABBITMQ_URL`                    | none                 | RabbitMQ connection for a managed database   |
| `SESSION_BACKEND`                 | `postgresql`         | `postgresql` or `redis`                      |
| `REDIS_URL`                       | none                 | Redis connection for a managed database      |
| `PGMQ_QUEUE`                      | `price_observations` | PostgreSQL queue name                        |
| `PGMQ_VISIBILITY_TIMEOUT_SECONDS` | `60`                 | Message visibility timeout                   |
| `PGMQ_POLL_INTERVAL_SECONDS`      | `1`                  | Consumer polling interval                    |
| `PGMQ_MAX_ATTEMPTS`               | `5`                  | Maximum processing attempts                  |
| `HISTORY_SERVICE_URL`             | `http://127.0.0.1:8001` | UI-to-History base URL                |
| `SESSION_TTL_SECONDS`             | `2592000`            | Sliding session TTL, 30 days                 |
| `SESSION_COOKIE_SECURE`           | `false`              | Secure-cookie flag for HTTPS deployments     |
| `LISTEN_ADDRESS`                  | `:8002`              | Fetcher diagnostic API address               |
| `LOG_LEVEL`                       | `INFO`               | Python service log level                     |

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
