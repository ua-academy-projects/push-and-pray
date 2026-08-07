# weather-app

A small weather-tracking system split into independent microservices, each deployed to its own VM via Vagrant and run as a Docker Compose stack.

## Architecture

```
                         ┌──────────────┐
        browser ───────► │  ui-service   │  static frontend (search, history, trends)
                         └──────┬───────┘
                                │ HTTP
                                ▼
                       ┌────────────────┐        ┌──────────┐
                       │ history-service │◄──────►│ Postgres │  weather readings, tracked cities
                       └───────┬────────┘        └──────────┘
                                │ AMQP (weather.fetch.requests / .responses)
                                ▼
                       ┌────────────────┐
                       │  rabbitmq       │  message broker
                       └───────┬────────┘
                                │
                                ▼
                       ┌────────────────┐        ┌──────────────────┐
                       │  proxy-service  │───────►│ WeatherAPI (external)│
                       └────────────────┘        └──────────────────┘

                       ┌────────────────┐
                       │  redis          │  user preferences cache (Redis-backed)
                       └────────────────┘

                       ┌────────────────┐
                       │  logserver      │  centralized syslog, TLS (rsyslog + gnutls)
                       └────────────────┘
```

`history-service` is the main API consumed by the UI: it tracks requested cities, serves cached/historical readings from Postgres, and asks `proxy-service` (over RabbitMQ) to fetch fresh data from the external weather API when needed. `redis` stores per-user preferences separately. `logserver` collects logs from every other VM over a TLS-secured syslog channel.

## Services

| Service | Tech | Port | Purpose |
|---|---|---|---|
| `ui-service` | static HTML/JS, `http-server` | 80 | Frontend: search current weather, view history, view trend charts |
| `history-service` | Spring Boot, Postgres, Java 25 | 8081 | Weather query API, city tracking, on-demand + scheduled ingestion |
| `proxy-service` | Spring Boot, Java 25 | 8082 | Fetches from the external weather API, exposes it over HTTP and RabbitMQ |
| `redis` | Spring Boot + Redis, Java 25 | 8083 | User preferences store |
| `rabbitmq-service` | RabbitMQ 3 (management image) | 5672 / 15672 | Message broker used by `history-service` ↔ `proxy-service` |

### API endpoints

**history-service** (`/api/v1`)
- `GET /weather/current?city=&country=&force=` — current reading (cached, or fetched on demand)
- `GET /weather/history?city=&country=&from=&to=` — historical readings
- `GET /cities` — cities currently tracked
- `GET /preferences` / `PUT /preferences` — user preferences (proxied through to `redis` service)

**proxy-service** (`/proxy/v1`)
- `GET /weather` — direct passthrough to the external weather API

**redis** (`/api/v1`)
- `GET /preferences` / `PUT /preferences` — preferences storage

## Running locally (Docker Compose)

Each service directory has its own `docker-compose.yml` and can be run independently:

```bash
cd history-service && docker compose up -d --build
```

Every service reads secrets from a `.env` file in its own directory (gitignored, not included in this repo). Create one per service before starting it:

**`history-service/.env`**
```
DB_USERNAME=
DB_PASSWORD=
RABBITMQ_USERNAME=
RABBITMQ_PASSWORD=
```

**`proxy-service/.env`**
```
WEATHER_API_KEY=
RABBITMQ_USERNAME=
RABBITMQ_PASSWORD=
```

**`rabbitmq-service/.env`**
```
RABBITMQ_USERNAME=
RABBITMQ_PASSWORD=
```

`redis` and `ui-service` don't require a `.env` file.

Services expect to reach each other at fixed IPs (`192.168.0.5x`) by default — see the [Full deployment](#full-deployment-vagrant) section, or override the relevant `*_URL`/`*_HOST` environment variables in each `docker-compose.yml` for a different topology.

## Full deployment (Vagrant)

The root `Vagrantfile` provisions six VirtualBox VMs on a bridged network, each running one service's Docker Compose stack:

| VM | IP | Role |
|---|---|---|
| `proxy` | 192.168.0.50 | proxy-service |
| `history` | 192.168.0.51 | history-service |
| `ui` | 192.168.0.52 | ui-service |
| `redis` | 192.168.0.53 | redis |
| `rabbitmq` | 192.168.0.54 | rabbitmq-service |
| `logserver` | 192.168.0.55 | centralized syslog (TLS) |

```bash
vagrant up
```

Provisioning does the following per VM:
1. `provision/setup-docker.sh` — installs Docker CE and brings up the service's Compose stack (skipped for `logserver`)
2. `provision/setup-ssh.sh` — creates a dedicated per-service SSH user and installs your `~/.ssh/id_ed25519.pub` for key-only auth
3. `provision/setup-tls.sh` — installs `rsyslog-gnutls` and configures TLS syslog forwarding to `logserver` (mutual TLS via certs in `provision/certs/`)

Requires a local SSH keypair at `~/.ssh/id_ed25519` and a `provision/certs/` directory with `CA.pem` plus `{server,client}-{cert,key}.pem` — these are generated locally and are not committed to the repo.

## Notes

- Java 25 / Spring Boot across all three Java services.
- Inter-service auth for RabbitMQ and Postgres is credential-based (via `.env`), not mutual TLS — TLS is only used for the syslog pipeline.
- `history-service`'s `.mvnw`/`pom.xml` etc. follow the standard Maven wrapper layout; no local Maven install is required to build.
