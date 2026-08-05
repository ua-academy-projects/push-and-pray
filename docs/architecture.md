# AirAware architecture

## System overview

AirAware is deployed across four Vagrant-managed Ubuntu VMs connected directly to the local network through VirtualBox bridged networking. Docker Compose runs one project per VM.

```text
                              Internet
                                 |
                                 v
                    Open-Meteo Air Quality API
                                 |
                                 v
                  API Fetcher VM 192.168.18.212
                     |                       |
                     | GET /api/cities       | publish durable event
                     v                       v
Backend VM 192.168.18.211 <------------- RabbitMQ
          |                                  |
          | consume, validate, acknowledge   |
          +----------------------------------+
          |
          v
PostgreSQL on infrastructure VM 192.168.18.213
          ^
          |
Frontend VM 192.168.18.210 ---> Backend API
```

The infrastructure VM also runs Redis. Redis is password protected, persistent, published on the bridged LAN, and health checked. It is intentionally retained as an infrastructure service but is not used for Flask sessions.

## Components

### Frontend

The Flask frontend:

- serves the dashboard and static assets;
- proxies city and dashboard requests to the Backend;
- stores selected city, metric, and period in a signed client cookie;
- checks Backend readiness before reporting itself ready;
- never connects to PostgreSQL, RabbitMQ, or Redis.

The cookie is signed with `AIRAWARE_FLASK_SECRET_KEY`, is HTTP-only, uses `SameSite=Lax`, and expires according to `SESSION_TTL_SECONDS`. It is not encrypted, so only non-sensitive UI preferences belong in it.

### Backend

The FastAPI Backend owns persistence and:

- lists configured cities and dashboard data;
- accepts measurement payloads through its public API;
- runs one RabbitMQ consumer inside the FastAPI lifespan;
- validates events and persists them through SQLAlchemy;
- reports ready only when PostgreSQL and the enabled consumer are connected.

The container intentionally runs one Uvicorn worker. Each additional worker would create another competing RabbitMQ consumer.

The consumer declares durable exchanges and queues, uses manual acknowledgements and `prefetch_count=1`, rejects permanent validation errors to the dead-letter path, and requeues transient database failures. Blocking SQLAlchemy work runs in a worker thread so it does not block the asyncio event loop.

### API Fetcher

The Fetcher:

- requests the active city list from the Backend;
- fetches current measurements from Open-Meteo concurrently;
- publishes persistent events to RabbitMQ;
- prevents overlapping fetch runs with an asynchronous lock;
- optionally fetches at startup;
- schedules collection hourly at minute `05` by default;
- reports ready only when the Backend and RabbitMQ are reachable.

The Fetcher does not write measurements directly to PostgreSQL.

### Infrastructure

One Compose project runs:

- PostgreSQL 18.4 for cities, measurements, and migration history;
- Redis 8.8.0 with AOF persistence and password authentication;
- RabbitMQ 4.2.9 with the management plugin and persistent data.

Named Docker volumes preserve data across container recreation:

```text
airaware-postgres-data
airaware-redis-data
airaware-rabbitmq-data
```

## Data flows

### Scheduled collection

1. APScheduler starts a fetch run.
2. The Fetcher requests active cities from the Backend.
3. The Fetcher retrieves Open-Meteo data for each city.
4. Each successful result is published to the durable RabbitMQ exchange.
5. The Backend consumer validates and persists the event.
6. PostgreSQL rejects duplicate `(city_id, observed_at)` values.
7. The consumer acknowledges the message only after persistence succeeds.

RabbitMQ decouples collection from persistence: published events can remain queued while the Backend consumer is unavailable.

### Dashboard

1. The browser loads the Frontend.
2. The Frontend proxies `/api/cities` and `/api/dashboard` to the Backend.
3. The Backend queries PostgreSQL.
4. The browser renders the latest measurement and requested history.
5. UI preferences are saved in the signed Flask session cookie.

The Refresh button reads stored data; it does not trigger Open-Meteo collection.

## Database design and migrations

`cities` contains stable location configuration. `air_quality_measurements` contains timestamped metric values and has a unique constraint on `(city_id, observed_at)`.

Schema changes are numbered SQL files in `backend-service/database/migrations`. Infrastructure deployment waits for PostgreSQL, creates `airaware_schema_migrations`, and applies each unrecorded migration transactionally under a PostgreSQL advisory lock. This works for both empty and existing named volumes.

## Network topology

Default addresses are:

| Role | Address | Published ports |
|---|---:|---|
| Frontend | `192.168.18.210` | `5000` |
| Backend | `192.168.18.211` | `8001` |
| Fetcher | `192.168.18.212` | `8000` |
| Infrastructure | `192.168.18.213` | `5432`, `6379`, `5672`, `15672` |

The network prefix and netmask can be changed in the root `.env`; VM suffixes remain `.210` through `.213`. Containers use their VM's published ports for cross-VM traffic. `localhost` is reserved for checks within the same VM or container.

All published ports are intentionally reachable from the bridged LAN. Use a trusted lab or home network and do not add public internet port forwarding unless separately secured.

## Deployment resilience

- Database and broker clients have bounded connection timeouts and retries.
- Compose deployment waits for container health and prints diagnostics on failure.
- Generated `.env` files are mode `0600`; URL credentials are percent encoded and Compose values are safely quoted.
- Build contexts and VM copies exclude local virtual environments, caches, bytecode, and local `.env` files.
- Container logs rotate at 10 MB with three files per container.
- Infrastructure containers have CPU, memory, PID, and graceful-stop limits sized for the 2 GB VM.
- PostgreSQL, Redis, and RabbitMQ health checks use slower steady-state intervals to reduce background VM load.

## Failure behavior

| Failure | Expected behavior |
|---|---|
| Backend unavailable | Frontend and Fetcher readiness return `503`; stored infrastructure data remains intact. |
| PostgreSQL unavailable | Backend readiness returns `503`; RabbitMQ retains unacknowledged or queued events. |
| RabbitMQ unavailable | Backend consumer and Fetcher readiness return `503`; dashboard reads can still use PostgreSQL. |
| Open-Meteo unavailable | Fetch run records per-city failures; existing dashboard data remains available. |
| Duplicate observation | PostgreSQL uniqueness prevents a second row. |

## Security boundaries

- Real `.env` files and SSH private keys are ignored by Git.
- Generated deployment `.env` files are readable only by root.
- Application containers run as the non-root `airaware` user.
- Only the Backend receives PostgreSQL credentials.
- The Frontend receives only its Backend URL and signing key.
- Vagrant's managed SSH account remains available even when optional personal-key access is configured.
