# Rateboard source of truth

This repository is a five-VM learning deployment for a crypto and fiat rates
dashboard. Keep the implementation understandable to a DevOps Academy student,
keep service boundaries explicit, and do not bypass RabbitMQ or PostgreSQL
ownership rules for convenience.

## Architecture

```text
CoinGecko / Frankfurter
          |
          v
Python API Fetcher -- observation events --> RabbitMQ
          ^                                      |
          | backfill commands                    v
          +---------------------------- Go History Service
                                                   |
                                                   v
Browser -> UI/Nginx -> History Service API -> PostgreSQL
```

Hard boundaries:

- UI obtains application data only from the Go History Service.
- UI never calls API Fetcher, providers, RabbitMQ, Redis, or PostgreSQL.
- API Fetcher calls providers, normalizes data, and publishes RabbitMQ events.
- API Fetcher has no PostgreSQL credentials or database client.
- API Fetcher must not use HTTP persistence fallback.
- History Service consumes RabbitMQ events and exclusively owns PostgreSQL.
- History Service must not call CoinGecko or Frankfurter.
- RabbitMQ is a transport, not historical storage.
- History queries read PostgreSQL; they do not replay RabbitMQ.
- A publisher confirmation means `queued`, not saved in PostgreSQL.
- History Service ACKs an observation only after a successful database commit.

## Five-VM deployment

Vagrant must preserve these five VMs:

| VM | Compose project |
|---|---|
| `ui` | UI/Nginx |
| `api-fetcher` | Python collector |
| `backend-service` | Go History Service |
| `database` | PostgreSQL 16 |
| `rabbitmq` | RabbitMQ and Redis |

Vagrant owns VM creation, QEMU, bridged networking, hostnames, Docker
installation, generated environment files, and Compose deployment.

Every VM has an independent Docker Compose project. Docker networks are local
to a VM. Cross-VM traffic uses bridged LAN hostnames or IP addresses.

Do not run Rateboard application services natively through systemd. Systemd may
manage only the Docker daemon and normal operating-system facilities.

Do not replace the five VMs with one Compose host, Docker Swarm, Kubernetes, or
an overlay network.

## Networking

Addresses come from `.env.vagrant.local`. Never hardcode deployment addresses
inside Python, Go, JavaScript, or Docker images.

Canonical VM hostnames:

```text
rates-ui
rates-api-fetcher
rates-backend-service
rates-db
rates-rabbitmq
```

Services exposed to another VM must bind `0.0.0.0`. `localhost` inside a
container refers only to that container.

The UI Nginx proxy routes `/api/v1/` to History Service. It must not route UI
traffic to API Fetcher.

## API Fetcher

Technology:

- Python 3.12+
- FastAPI and Uvicorn
- `httpx.AsyncClient`
- Pydantic Settings
- `aio-pika`

Responsibilities:

- provider HTTP clients and retries;
- instrument validation;
- decimal-safe normalization;
- five-minute wall-clock collector;
- RabbitMQ command consumption;
- current and historical provider retrieval;
- observation-event publication;
- internal health and explicit collection/backfill endpoints.

Public-provider constraints:

- CoinGecko IDs are identifiers, not symbols.
- Frankfurter rates are daily reference rates.
- Decimal values cross boundaries as JSON strings.
- Timestamps are UTC.
- Retry idempotent GET requests at most twice on timeout, 429, or 5xx.
- Respect `Retry-After`.
- Backfill is limited to 365 days.
- Never fabricate unavailable five-minute history.

API Fetcher exposes:

```text
GET  /health/live
GET  /health/ready
POST /internal/v1/collect
POST /internal/v1/backfill
```

Internal POST endpoints require `INTERNAL_API_TOKEN`. They collect and enqueue;
they never write PostgreSQL.

## RabbitMQ contracts

Required topology:

```text
rates.commands
  -> rates.fetch.commands
  -> rates.fetch.commands.dlq

rates.events
  -> rates.observations
  -> rates.observations.dlq
```

Use durable exchanges and queues, persistent messages, publisher confirms,
bounded consumer prefetch, explicit ACK/NACK, and dead-letter routing.

Backfill command fields:

```json
{
  "command_id": "stable-id",
  "command_type": "rates.backfill.requested",
  "schema_version": 1,
  "request_id": "correlation-id",
  "instrument_id": "crypto:bitcoin:usd",
  "from": "2026-01-01T00:00:00Z",
  "to": "2026-07-29T00:00:00Z"
}
```

Observation event fields:

```json
{
  "event_id": "stable-id",
  "event_type": "rate.observation.collected",
  "schema_version": 1,
  "request_id": "correlation-id",
  "idempotency_key": "stable-key",
  "observation": {
    "instrument_id": "crypto:bitcoin:usd",
    "kind": "crypto",
    "base": "BTC",
    "quote": "USD",
    "name": "Bitcoin",
    "price": "67187.33589366",
    "change_1h_percent": "0.421",
    "change_24h_percent": "3.63727848",
    "market_cap": "1317800000000.00",
    "rank": 1,
    "source": "coingecko",
    "source_timestamp": "2026-07-17T09:30:00Z",
    "requested_at": "2026-07-17T09:30:03Z",
    "request_id": "uuid"
  }
}
```

Never place API keys, authorization headers, or credentials in messages.

## History Service

Technology:

- Go 1.23+
- `net/http`
- `pgx/v5`
- RabbitMQ AMQP client

Responsibilities:

- consume and validate normalized observation events;
- insert observations idempotently;
- expose all UI read APIs;
- aggregate PostgreSQL series;
- calculate market-cap changes from stored market-cap observations;
- inspect latest timestamps per instrument;
- publish startup backfill commands.

UI-facing API:

```text
GET /health/live
GET /health/ready
GET /api/v1/instruments
GET /api/v1/overview
GET /api/v1/rates/current
GET /api/v1/rates/stored-current
GET /api/v1/rates/history
GET /api/v1/requests/history
GET /api/v1/market-map
```

Readiness includes PostgreSQL and RabbitMQ consumer readiness.

## PostgreSQL and persistence

PostgreSQL 16 runs only on the `database` VM in Docker.

Use `NUMERIC` for rates and market values and `TIMESTAMPTZ` in UTC. Migrations
belong to `backend-service/migrations`.

PostgreSQL data uses a Docker volume backed by a dedicated host-side qcow2
disk:

```text
host .vagrant-data/database/postgresql.qcow2
  -> database VM ext4 /srv/rateboard-data/postgresql
  -> container /var/lib/postgresql/data
```

Source-code `rsync` is not valid database persistence. `vagrant-qemu` 0.6.x
reports NFS synced folders unusable in the target environment, so the live
PostgreSQL data uses a dedicated persistent disk instead of an unsafe network
filesystem. The qcow2 file is outside `.vagrant` and must not be deleted during
normal lifecycle operations.

Normal lifecycle commands must never use:

```text
docker compose down -v
docker volume rm
rm -f .vagrant-data/database/postgresql.qcow2
DROP DATABASE
TRUNCATE observations
```

If the cluster is absent, initialize it and apply every migration. If it
exists, apply only idempotent migrations and preserve all observations.

## Startup backfill

History Service queries the latest `source_timestamp` separately for every
configured instrument.

- Missing instrument: request up to `STARTUP_BACKFILL_MAX_DAYS`, maximum 365.
- Existing instrument: request only from its latest timestamp to now.
- Never use one global timestamp for all instruments.
- Repeated inclusive provider points are safe because persistence is
  idempotent.

History Service publishes backfill commands. API Fetcher consumes them and
publishes observation events. History Service consumes those events and writes
PostgreSQL.

A failed backfill must preserve existing data and remain retryable.

## UI

The UI is HTML, CSS, and vanilla JavaScript. Chart.js dependencies remain
pinned. It reads only History Service through same-origin Nginx `/api/v1/`.

UI state may use browser `localStorage`; Redis must not store rate data.

Keep the existing Overview, History, Capitalization, theme, accessibility,
dynamic cards, chart refresh, zoom, and print-to-PDF behavior. Empty database
states must be explicit and must not clear the last valid value.

## Configuration and secrets

Real local values come from `.env` and `.env.vagrant.local`. Generated
per-service files under `infra/vagrant/generated` are mode `0600` and ignored.

- API Fetcher does not receive `DATABASE_URL`.
- UI does not receive provider, RabbitMQ, Redis, or database credentials.
- History Service is the only application receiving `DATABASE_URL`.
- Never log tokens, passwords, URLs containing credentials, or provider keys.

## Verification

Static checks do not prove runtime deployment.

Minimum static verification:

```bash
python3 -m compileall -q api-fetcher/app
api-fetcher/.venv/bin/pytest -q
GOCACHE=/private/tmp/rateboard-go-cache go test ./...
npm --prefix ui-service test
ruby -c Vagrantfile
bash -n infra/vagrant/provision/*.sh scripts/*.sh
git diff --check
```

Runtime verification requires all five running VM Compose projects, healthy
containers, History/API health endpoints, queue state, PostgreSQL ranges, and a
real observation traversing provider -> MQ -> History -> PostgreSQL -> UI.

Never call persistence after `vagrant destroy` verified unless that destructive
test was explicitly authorized and actually executed.
