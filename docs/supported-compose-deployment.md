# Supported Docker Compose deployment

This deployment pulls prebuilt application and PostgreSQL images. It does not
build application images on the target machine. The Ansible role installs a
non-secret `deployment.env` file containing the application image SHA from the
external project configuration JSON. Secret retrieval and injection are handled
outside Compose through the parent process environment.

There is no single combined Compose file anymore. `oilscope.platform.
compose_project` always renders exactly one per-role template for a given
VM — `compose.database.yaml.j2`, `compose.fetcher.yaml.j2`,
`compose.history.yaml.j2`, or `compose.ui.yaml.j2` at
`infrastructure/ansible/oilscope/platform/roles/compose_project/templates/`,
selected by that VM's own role — installed as `/opt/oilscope/app/compose.yaml`.
There is no "run everything on one machine" option: every workload VM runs
exactly one role's Compose project. RabbitMQ and Redis are **not** rendered by
`compose_project` at all — they're each their own dedicated role and Compose
project (`oilscope-rabbitmq` on the History VM, `oilscope-redis` on the UI
VM); see [RabbitMQ and Redis deployment](../infrastructure/ansible/oilscope/platform/README.md#rabbitmq-and-redis-deployment)
and [Database modes and coordinated cutover](database-modes.md).

## Required settings

| Variable | Description |
| --- | --- |
| `APP_IMAGE_TAG` | Immutable Git commit SHA installed from the external JSON by the Ansible role. Do not use `latest`. |
| `POSTGRES_IMAGE` | Complete prebuilt PostgreSQL 18 image reference, preferably pinned by digest, for example `ghcr.io/ua-academy-projects/push-and-pray/database@sha256:...`. It must include the SQL migrations and `petroscope-migrate`; it no longer needs PGMQ or `pg_cron` — those extensions were retired when the application moved to RabbitMQ and Redis. |
| `POSTGRES_PASSWORD` | PostgreSQL password injected by the host secret mechanism. It is never stored in Compose. Use a URL-safe value because the application database URLs contain it. |
| `OILPRICEAPI_KEY` | Provider credential required when `DATA_PROVIDER=oilpriceapi`. It may be omitted when the mock provider is explicitly selected for a smoke test. |

Fetcher and History additionally require, with no compiled-in default —
Compose fails to start rather than falling back to a previous value if any
of these are unset: `POSTGRES_USER`, `POSTGRES_PASSWORD_URL` (the
URL-encoded form of `POSTGRES_PASSWORD` used inside the connection string),
`DATABASE_HOST`, `DATABASE_PORT`, `POSTGRES_DB`, `DATABASE_SSLMODE`
(`disable` in application mode, `verify-full` plus a required
`DATABASE_SSLROOTCERT` in cloud mode), `RABBITMQ_URL`, `RABBITMQ_CA_FILE`,
`RABBITMQ_EXCHANGE`, `RABBITMQ_ROUTING_KEY`, `RABBITMQ_QUEUE`,
`RABBITMQ_TIMEOUT_SECONDS`, `RABBITMQ_RECONNECT_SECONDS`,
`RABBITMQ_MAX_ATTEMPTS`, `OUTBOX_POLL_SECONDS`, `OUTBOX_BATCH_SIZE`. UI
instead requires `REDIS_URL`, `REDIS_KEY_PREFIX`, and `SESSION_TTL_SECONDS` —
it has no PostgreSQL connection at all. The `oilscope.platform.
database_connection` and `broker_connection` Ansible roles derive all of
these from inventory/Terraform outputs and project configuration; they are
not meant to be hand-typed for a real deployment, only for a manual/local
Compose invocation like the ones below.

Authenticate to the private registry before deployment. Supply a GitHub token
with `read:packages` to `docker login ghcr.io` through standard input; do not put
the token in Compose, this repository, or a shell argument.

## Optional settings

| Variable | Default | Purpose |
| --- | --- | --- |
| `POSTGRES_DB` | `oil_tracker` | Database name (the `postgres` container's own default; Fetcher/History must still be given it explicitly, see above) |
| `POSTGRES_USER` | `oil_tracker` | Database user (same caveat) |
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
| `DATA_PROVIDER` | `oilpriceapi` | Fetcher data provider |
| `FETCH_CRON_HOURS` | `0,6,12,18` | Fetch schedule hours |
| `FETCH_TIMEZONE` | `UTC` | Fetch schedule timezone |
| `FETCH_ON_STARTUP` | `true` | Fetch immediately after startup |
| `REQUEST_TIMEOUT_SECONDS` | `15` | Fetcher provider timeout |
| `SESSION_COOKIE_SECURE` | `false` | Set to `true` when HTTPS terminates at the application host |
| `LOG_LEVEL` | `INFO` | History and UI log level |
| `APPLICATION_PLATFORM` | `linux/amd64` | Application image platform |
| `POSTGRES_PLATFORM` | `linux/amd64` | PostgreSQL image platform |
| `APPLICATION_PULL_POLICY` | `always` | Application image pull policy |
| `POSTGRES_PULL_POLICY` | `always` | PostgreSQL image pull policy |

`SESSION_TTL_SECONDS` (the Redis session TTL) has no default and is listed as
required above, not here — UI fails to start without it, matching every
other connection-shaped setting in this deployment.

## Starting each role

Cross-host ordering is handled by the deployment orchestrator, not by
Compose — there's no single file where `depends_on` could coordinate this
across VMs even if every role happened to run on one machine. Run
`docker compose ... pull` before each role's `up`/`run` command:

```sh
docker compose --env-file /opt/oilscope/app/deployment.env -f /opt/oilscope/app/compose.yaml up -d postgres   # database VM, application mode only
docker compose --env-file /opt/oilscope/app/deployment.env -f /opt/oilscope/app/compose.yaml run --rm migrate # database VM, application mode only
# start RabbitMQ (History VM) and Redis (UI VM) here — see the cross-references above
docker compose --env-file /opt/oilscope/app/deployment.env -f /opt/oilscope/app/compose.yaml up -d history     # History VM
docker compose --env-file /opt/oilscope/app/deployment.env -f /opt/oilscope/app/compose.yaml up -d fetcher     # Fetcher VM
docker compose --env-file /opt/oilscope/app/deployment.env -f /opt/oilscope/app/compose.yaml up -d ui          # UI VM
```

Cloud mode runs migrations from a **separate** Compose project — never from
`/opt/oilscope/app/compose.yaml`, and never as a hand-typed invocation with
this document's `--env-file`. The `oilscope.platform.database_migrate` role
renders its own project at `/opt/oilscope/migrate/compose.yaml` (project name
`oilscope-migrate`) on the first History host, and runs it itself with
transient administrator/runtime credentials it reads from Secrets Manager
using the *controller operator's* identity:

```sh
docker compose --project-name oilscope-migrate --file /opt/oilscope/migrate/compose.yaml pull migrate
docker compose --project-name oilscope-migrate --file /opt/oilscope/migrate/compose.yaml run --rm --no-deps -T migrate
```

These two commands are shown for reference/troubleshooting only — there is no
supported manual invocation of cloud-mode migrations; the credentials are
process-transient Ansible facts, not a file an operator can export and reuse.
See [`database_migrate`'s README](../infrastructure/ansible/oilscope/platform/roles/database_migrate/README.md)
for the credential-retrieval and grant sequence.

On application VMs, set `DATABASE_HOST` to the database VM endpoint (or the
managed endpoint in cloud mode) and `RABBITMQ_URL`/`RABBITMQ_CA_FILE` to the
History VM's broker. On the UI VM, also set `HISTORY_SERVICE_URL` to the
History VM endpoint and `REDIS_URL` to its own co-located Redis. Network
firewalls must permit only the required cross-VM traffic.

Run the application smoke test once every role is up:

```sh
infrastructure/docker/smoke-test.sh
```

Stop a role without deleting its data:

```sh
docker compose --env-file /opt/oilscope/app/deployment.env -f /opt/oilscope/app/compose.yaml down
```

RabbitMQ and Redis use their own separate `docker compose ... down` (project
names `oilscope-rabbitmq`/`oilscope-redis`) and are **not** stopped by this
command — see [Database modes and coordinated cutover](database-modes.md)
for when their data should, and should not, be reset.
