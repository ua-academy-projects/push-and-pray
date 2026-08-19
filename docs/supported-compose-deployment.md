# Supported Docker Compose deployment

This deployment pulls prebuilt application and PostgreSQL images. It does not
build application images on the target machine and it does not require or load
a `.env` file. Export every setting in the parent process environment before
running Compose. Secret retrieval and injection are handled outside Compose.

The supported configuration is
`infrastructure/docker/compose.deployment.yaml`. The older role-specific Compose
files are retained for the Vagrant development environment; they are not the
supported GHCR deployment configuration.

## Required settings

| Variable | Description |
| --- | --- |
| `APP_IMAGE_TAG` | Immutable Git commit SHA shared by the Fetcher, History and UI GHCR images. Do not use `latest`. |
| `POSTGRES_IMAGE` | Complete prebuilt PostgreSQL 18 image reference, preferably pinned by digest, for example `ghcr.io/ua-academy-projects/push-and-pray/database@sha256:...`. It must include PGMQ, `pgcrypto`, `pg_cron`, the SQL migrations and `petroscope-migrate`. |
| `POSTGRES_PASSWORD` | PostgreSQL password injected by the host secret mechanism. It is never stored in Compose. Use a URL-safe value because the application database URLs contain it. |
| `OILPRICEAPI_KEY` | Provider credential required when `DATA_PROVIDER=oilpriceapi`. It may be omitted when the mock provider is explicitly selected for a smoke test. |

Authenticate to the private registry before deployment. Supply a GitHub token
with `read:packages` to `docker login ghcr.io` through standard input; do not put
the token in Compose, this repository, or a shell argument.

## Optional settings

| Variable | Default | Purpose |
| --- | --- | --- |
| `POSTGRES_DB` | `oil_tracker` | Database name |
| `POSTGRES_USER` | `oil_tracker` | Database user |
| `DATABASE_HOST` | `postgres` | PostgreSQL hostname; set the database VM address for split-host deployment |
| `DATABASE_PORT` | `5432` | PostgreSQL service port |
| `DATABASE_SSLMODE` | `disable` | Client PostgreSQL TLS mode |
| `DATABASE_BIND_ADDRESS` | `0.0.0.0` | PostgreSQL host bind address |
| `DATABASE_HOST_PORT` | `5432` | Published PostgreSQL host port |
| `HISTORY_SERVICE_URL` | `http://history:8001` | UI-to-History endpoint; set the History VM address for split-host deployment |
| `HISTORY_BIND_ADDRESS` | `0.0.0.0` | History host bind address |
| `HISTORY_HOST_PORT` | `8001` | Published History host port |
| `FETCHER_BIND_ADDRESS` | `0.0.0.0` | Fetcher host bind address |
| `FETCHER_HOST_PORT` | `8002` | Published Fetcher host port |
| `FETCHER_LISTEN_ADDRESS` | `0.0.0.0:8002` | Fetcher listen endpoint inside its container |
| `UI_BIND_ADDRESS` | `0.0.0.0` | UI host bind address |
| `UI_HTTP_PORT` | `80` | Published UI HTTP port |
| `PGMQ_QUEUE` | `price_observations` | PostgreSQL queue name |
| `PGMQ_VISIBILITY_TIMEOUT_SECONDS` | `60` | History queue visibility timeout |
| `PGMQ_POLL_INTERVAL_SECONDS` | `1` | History queue polling interval |
| `PGMQ_MAX_ATTEMPTS` | `5` | History maximum delivery attempts |
| `DATA_PROVIDER` | `oilpriceapi` | Fetcher data provider |
| `FETCH_CRON_HOURS` | `0,6,12,18` | Fetch schedule hours |
| `FETCH_TIMEZONE` | `UTC` | Fetch schedule timezone |
| `FETCH_ON_STARTUP` | `true` | Fetch immediately after startup |
| `REQUEST_TIMEOUT_SECONDS` | `15` | Fetcher provider timeout |
| `SESSION_TTL_SECONDS` | `2592000` | PostgreSQL UI-session lifetime |
| `SESSION_COOKIE_SECURE` | `false` | Set to `true` when HTTPS terminates at the application host |
| `LOG_LEVEL` | `INFO` | History and UI log level |
| `APPLICATION_PLATFORM` | `linux/amd64` | Application image platform |
| `APPLICATION_PULL_POLICY` | `always` | Application image pull policy |
| `POSTGRES_PULL_POLICY` | `always` | PostgreSQL image pull policy |

## Complete stack on one machine

After exporting the required variables, use this single startup command:

```sh
docker compose -f infrastructure/docker/compose.deployment.yaml pull && docker compose -f infrastructure/docker/compose.deployment.yaml up -d --wait
```

Compose starts PostgreSQL, waits for it to become healthy, applies every
migration through the one-shot `migrate` service, starts Fetcher and History,
then starts UI after History is healthy. UI is published on host port 80 by
default.

Run the application smoke test:

```sh
infrastructure/docker/smoke-test.sh
```

Stop the deployment without deleting PostgreSQL data:

```sh
docker compose -f infrastructure/docker/compose.deployment.yaml down
```

## Independent VM roles

Cross-host ordering is handled by the deployment orchestrator, not by Compose.
Start PostgreSQL first, run the independently executable migration job, and
then start the application roles. Use `--no-deps` so a role does not try to
start its same-file dependencies on that VM:

```sh
docker compose -f infrastructure/docker/compose.deployment.yaml up -d --no-deps postgres
docker compose -f infrastructure/docker/compose.deployment.yaml run --rm --no-deps migrate
docker compose -f infrastructure/docker/compose.deployment.yaml up -d --no-deps history
docker compose -f infrastructure/docker/compose.deployment.yaml up -d --no-deps fetcher
docker compose -f infrastructure/docker/compose.deployment.yaml up -d --no-deps ui
```

Run `docker compose ... pull SERVICE` before each role command. On application
VMs, set `DATABASE_HOST` to the database VM endpoint. On the UI VM, also set
`HISTORY_SERVICE_URL` to the History VM endpoint. Network firewalls must permit
only the required cross-VM traffic; Compose dependencies do not coordinate
services across machines.
