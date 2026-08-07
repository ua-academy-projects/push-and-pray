# SkyIvano

A small multi-service weather dashboard for **Ivano-Frankivsk, Ukraine**, built as a DevOps Academy assignment. It demonstrates clean service boundaries, scheduled background synchronization, relational persistence, and a Dockerized multi-VM deployment — without Kubernetes, CI/CD, or cloud deployment (that's future work, see [docs/architecture.md](docs/architecture.md) §14).

Weather data comes from the free [Open-Meteo](https://open-meteo.com/) API (no key/auth required).

The project was originally built as three services (UI, Backend, History) and has since been refactored into four (UI, Backend, a Weather Fetcher, PostgreSQL); the History Service no longer exists. See [docs/prompts/refactor-0-discovery-and-plan.md](docs/prompts/refactor-0-discovery-and-plan.md) for the full staged plan.

Redis was added after that refactor, purely for ephemeral **UI session state** (selected graph period, filters, toggles) — never business/weather data, and never authentication. See [docs/architecture.md](docs/architecture.md) §16.

RabbitMQ was added after that to decouple the Fetcher from the Backend: a completed (or failed) sync is now published to a durable queue instead of being pushed over a synchronous HTTP call, and a separate worker process on the Backend consumes it and persists it. See "Architecture at a glance" below.

## Architecture at a glance

```
Scheduled sync:  Fetcher Scheduler -> Weather Fetcher Service -> Open-Meteo -> Weather Fetcher Service -> RabbitMQ -> Backend Worker -> PostgreSQL
User reads:      Browser -> UI Service -> Backend Service -> PostgreSQL
Manual refresh:  Browser -> UI Service -> Backend Service -> Weather Fetcher Service -> Open-Meteo -> Weather Fetcher Service -> RabbitMQ -> Backend Worker -> PostgreSQL
```

The Fetcher never waits for that last hop to complete -- publishing to RabbitMQ is fire-and-forget, so "Manual refresh" confirms the request was queued, not that it's been persisted yet; the UI picks up the actual result on its next poll of `/api/weather` or `/api/sync/history`.

Four independently runnable services, each with a single responsibility, plus PostgreSQL and RabbitMQ:

| Service | Responsibility |
|---|---|
| **ui-service** | React/TypeScript dashboard. Talks only to the Backend's public API. |
| **backend-service** | FastAPI. Owns PostgreSQL directly — the public API, plus (as a background task in the same process) consuming synced weather data from RabbitMQ and persisting it. Never calls Open-Meteo; never calls the Fetcher except to proxy one manual-refresh action. |
| **fetcher-service** | FastAPI. The only service that calls Open-Meteo. Runs the sync scheduler independently of user traffic, normalizes the response, and publishes it to RabbitMQ for the Backend to consume. Never touches PostgreSQL, never calls the Backend to push data. |

The UI never calls Open-Meteo or the Fetcher directly, and never triggers a *scheduled* sync — it only ever reads data the Backend has already persisted, plus one explicit "Refresh now" action that still routes through the Backend. Full rules and diagrams: [docs/architecture.md](docs/architecture.md).

## Technology stack

- **UI**: React, TypeScript, Vite, CSS Modules, Recharts, Vitest + React Testing Library
- **Backend**: Python 3.12, FastAPI, Pydantic, httpx, SQLAlchemy 2, PostgreSQL, aio-pika, pytest
- **Fetcher**: Python 3.12, FastAPI, Pydantic, httpx, APScheduler, aio-pika, pytest
- **Database**: PostgreSQL (no SQLite anywhere — including tests), owned exclusively by the Backend
- **Session storage**: Redis, owned exclusively by the Backend — UI preferences only, never business data
- **Messaging**: RabbitMQ — the Fetcher publishes completed/failed syncs; a separate Backend worker process consumes and persists them

## Local setup overview

Prerequisites: Python 3 (3.12 recommended; 3.14 also verified working with the `psycopg` v3 driver — see `docs/troubleshooting.md`), Node.js (LTS), a local PostgreSQL instance, a local Redis instance, and a local RabbitMQ instance.

PostgreSQL, Redis, and RabbitMQ can each be a native install or run in a plain, throwaway Docker container purely as a local dev convenience for this **native** workflow — the four application services below still run directly with `venv`/`npm`, unrelated to the project's own `Dockerfile`s/`docker-compose.yml`s (one per service, plus `infra/postgres/`), which containerize everything for the Vagrant multi-VM deployment instead — see "Running with Vagrant" below and `docs/architecture.md` §18. The commands below use the throwaway-container approach; swap in `createdb`/a native Redis or RabbitMQ install if you prefer.

```bash
docker run -d --name skyivano-postgres \
  -e POSTGRES_USER=skyivano -e POSTGRES_PASSWORD=skyivano -e POSTGRES_DB=skyivano \
  -p 5432:5432 -v skyivano-pgdata:/var/lib/postgresql/data postgres:16
docker exec skyivano-postgres createdb -U skyivano skyivano_test

docker run -d --name skyivano-redis -p 6379:6379 redis:7-alpine

docker run -d --name skyivano-rabbitmq -p 5672:5672 -p 15672:15672 rabbitmq:3-management
```

The default `guest`/`guest` credentials work fine for local dev (unlike over the LAN in the Vagrant setup below, RabbitMQ's restriction on `guest` only applies to non-localhost connections). Management UI at `http://localhost:15672` once the container's up.

1. Databases created above (`skyivano` for dev, `skyivano_test` for tests), Redis, and RabbitMQ running.
2. Copy each service's `.env.example` to `.env` and adjust if needed.
3. Set up and run each service (see commands below).

Detailed setup and environment variables: [docs/architecture.md](docs/architecture.md) and each service's own README.

## Running the services

Order doesn't strictly matter — `backend-service` serves stored data even with the Fetcher stopped (stale but not broken), and `fetcher-service` logs a failed publish locally if RabbitMQ is unreachable rather than crashing.

**Backend Service** (the public API; also consumes synced weather data from RabbitMQ in the background and persists it — see `app/main.py`'s lifespan):
```bash
cd backend-service
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

**Weather Fetcher Service**:
```bash
cd fetcher-service
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8002
```

**UI Service**:
```bash
cd ui-service
npm install
npm run dev
```

Then open the UI (default `http://localhost:5173`).

## Running with Vagrant

An alternative to the native setup above: [`Vagrantfile`](Vagrantfile) brings up all four components (`postgres`, `backend`, `fetcher`, `ui`) as separate VMs under the QEMU provider (`vagrant-qemu` plugin — required on Apple Silicon, since VirtualBox's arm64 support isn't reliable). Every VM is bridged onto the same home-network LAN as the host Mac (and reachable from other devices on it, e.g. a phone), each with a fixed IP. Each VM's provisioning script installs Docker Engine + the Compose plugin and runs `docker compose up -d --build` against that component's own `docker-compose.yml` — see `docs/architecture.md` §18 for the full containerization writeup.

| VM | LAN IP | Port | Containers (`docker compose ps`) |
|---|---|---|---|
| postgres | 192.168.0.220 | 5432 (Postgres), 6379 (Redis), 5672 (RabbitMQ), 15672 (RabbitMQ management UI) | `postgres`, `redis`, `rabbitmq` (`infra/postgres/docker-compose.yml`) |
| backend | 192.168.0.221 | 8000 (API service) | `migrate` (one-shot, runs first), `api`, `worker` (the RabbitMQ consumer — no port of its own) (`backend-service/docker-compose.yml`) |
| fetcher | 192.168.0.222 | 8002 | `fetcher` (`fetcher-service/docker-compose.yml`) |
| ui | 192.168.0.223 | 5173 | `ui` — nginx serving the production Vite build (`ui-service/docker-compose.yml`) |

Every container uses `network_mode: host`, so it binds directly to its VM's bridged IP above — no port-mapping/NAT layer sits between a container and the LAN. Useful commands from inside a VM (`vagrant ssh <name>`, then `cd /app`): `docker compose ps`, `docker compose logs -f <service>`, `docker compose restart <service>`.

**RabbitMQ management UI**: `http://192.168.0.220:15672`, logged in as `skyivano`/`skyivano` (created via `RABBITMQ_DEFAULT_USER`/`RABBITMQ_DEFAULT_PASS` in `infra/postgres/docker-compose.yml` — the default `guest`/`guest` login only works from `localhost` on the broker's own host, which this isn't). Shows both queues (`weather.sync`, `weather.sync_failure`), their message rates and consumer counts, and the two dead-letter queues (`weather.sync.dead`, `weather.sync_failure.dead`) a poison message ends up on — see `docs/architecture.md` §17.

**Pausing/resuming the Backend Worker (consumer)**, e.g. to inspect a message in the management UI's "Get messages" panel before it gets consumed and acked: the worker uses a robust RabbitMQ connection that auto-reconnects, so there's no reliable way to pause it from the management UI itself (force-closing its connection there just triggers an immediate reconnect) — stop/start its container instead:

```bash
sudo env OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES vagrant ssh backend -c "cd /app && docker compose stop worker"
# ...trigger a sync, inspect the message via the management UI (Queues -> weather.sync -> Get messages,
# ack mode "Nack message requeue true" so it isn't lost)...
sudo env OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES vagrant ssh backend -c "cd /app && docker compose start worker"
```

Bridged networking (`vmnet_bridged`) needs root, and a separate macOS Objective-C runtime quirk (`+[NSNumber initialize] ... fork()`) crashes QEMU on some machines unless one extra environment variable is set. Always bring the environment up with:

```bash
sudo env OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES vagrant up
sudo env OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES vagrant halt

```

Use that same `sudo env OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` prefix for every other lifecycle command too (`reload`, `halt`, `destroy`, `status`, `ssh <name>`) — mixing sudo and non-sudo runs leaves root-owned files behind that break the non-sudo commands.

Once up, open `http://192.168.0.223:5173` from this Mac or any other device on the LAN — there's no `localhost` fallback, since the VMs have no forwarded ports, only the bridged LAN addresses above.

## Running tests

```bash
cd backend-service && DATABASE_URL=postgresql+psycopg://skyivano:skyivano@localhost:5432/skyivano_test pytest
cd fetcher-service && pytest
cd ui-service && npm test
```

Backend Service tests run against real PostgreSQL — point `DATABASE_URL` at `skyivano_test` before running them (the whole suite, not just persistence tests, refuses to run otherwise). They also need a real Redis reachable at `REDIS_URL` (session tests use logical DB 15, flushed after every test, so they never touch DB 0's dev data). The RabbitMQ consumer (`app/broker/consumer.py`) is tested against a real test-database session but without a live broker — the message-handling functions are called directly with an in-memory body, the same way the API used to be exercised via its old PUT/POST endpoints. Fetcher Service tests mock Open-Meteo and RabbitMQ publishing — no live network calls, no broker, no database.

## Documentation

- [docs/architecture.md](docs/architecture.md) — architecture, service boundaries, API contracts, database schema, sync/read/manual-refresh flows, decisions (source of truth)
- [docs/implementation-plan.md](docs/implementation-plan.md) — the original 4 build stages (pre-refactor)
- [docs/troubleshooting.md](docs/troubleshooting.md) — known issues and fixes
- [docs/project-status.md](docs/project-status.md) — current progress checklist
- [docs/prompts/](docs/prompts/) — self-contained AI-agent prompts, one per refactor stage


