# Local Linux Docker Compose deployment

This profile runs the complete AEGIS topology on one Linux host for smoke
testing. It does not replace the four-VM Vagrant deployment, change its private
IP addresses, or change any production service boundary.

All containers join the `aegis-local-private` Docker bridge network. Application
traffic uses the Compose DNS names `mariadb`, `rabbitmq`, `redis`,
`provider-api`, and `history-api`; it never uses a Vagrant address or host
loopback for container-to-container communication.

The committed passwords are disposable local smoke-test values shared with the
local RabbitMQ definitions and Redis ACL. Do not use this profile or these
credentials for a remotely reachable deployment. Only the AbuseIPDB API key
needs to be replaced in the copied `.env` file.

## Ubuntu prerequisites

Run these commands in an Ubuntu terminal:

```bash
sudo apt-get update
sudo apt-get install --yes ca-certificates curl docker.io docker-compose-v2
sudo systemctl enable --now docker
sudo usermod --append --groups docker "$USER"
```

Sign out and back in so the Docker group change takes effect. Then verify the
installation:

```bash
docker version
docker compose version
docker info
```

Clone or open the repository and change to its root before continuing.

## Configure and validate

Create the ignored runtime environment file:

```bash
cp deploy/local/.env.example deploy/local/.env
chmod 600 deploy/local/.env
```

Edit only the copied file and replace:

```text
ABUSEIPDB_API_KEY=replace-with-abuseipdb-api-key
```

Validate the committed example exactly as CI does:

```bash
docker compose --env-file deploy/local/.env.example \
  -f deploy/local/compose.yaml config
```

Validate the private runtime file:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml config --quiet
```

## Build the application images

The three application images reuse the service Dockerfiles and are shared by
the API/background containers:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml build ui history-api provider-api
```

## First start

Start the infrastructure containers:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml up --detach mariadb rabbitmq redis
```

Wait until all three report `healthy`:

```bash
until [ "$(docker inspect --format '{{.State.Health.Status}}' aegis-mariadb)" = "healthy" ]; do sleep 2; done
until [ "$(docker inspect --format '{{.State.Health.Status}}' aegis-rabbitmq)" = "healthy" ]; do sleep 2; done
until [ "$(docker inspect --format '{{.State.Health.Status}}' aegis-redis)" = "healthy" ]; do sleep 2; done
```

Run the one-shot History migration service before either History runtime:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml run --rm --no-deps history-migrate
```

Start the five application runtimes. `--no-deps` is intentional here because
infrastructure readiness and migrations were completed explicitly above:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml up --detach --no-deps \
  provider-api provider-worker history-api history-consumer ui
```

For subsequent starts, the dependency conditions can supervise the complete
sequence and the idempotent migration service:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml up --detach
```

The migration command is safe to run again when applying new History
migrations:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml run --rm --no-deps history-migrate
```

Do not start `history-api` or `history-consumer` while a migration is still
running.

## Published endpoints

Only loopback host ports are published:

| Endpoint | Host address |
|---|---|
| UI | `http://127.0.0.1:8000` |
| Provider API diagnostics | `http://127.0.0.1:8001` |
| History API diagnostics | `http://127.0.0.1:8002` |
| RabbitMQ Management | `http://127.0.0.1:15672` |

The local RabbitMQ administrator login is `aegis_admin` /
`local-rabbitmq-admin-password`. MariaDB, RabbitMQ AMQP, and Redis have no
published host ports.

## Smoke tests

Inspect status and health:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml ps
```

Check the application endpoints:

```bash
curl --fail http://127.0.0.1:8000/health/live
curl --fail http://127.0.0.1:8000/health/ready
curl --fail http://127.0.0.1:8001/health/live
curl --fail http://127.0.0.1:8001/health/ready
curl --fail http://127.0.0.1:8002/health/live
curl --fail http://127.0.0.1:8002/health/ready
```

Confirm the database schema is current:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml run --rm --no-deps \
  history-migrate alembic -c /app/alembic.ini current --check-heads
```

Inspect structured stdout logs:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml logs --tail 100 \
  provider-worker history-consumer history-api provider-api ui
```

## Stop or reset

Stop containers while preserving local data:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml down
```

Remove containers, the private network, and all three local data volumes:

```bash
docker compose --env-file deploy/local/.env \
  -f deploy/local/compose.yaml down --volumes --remove-orphans
```
