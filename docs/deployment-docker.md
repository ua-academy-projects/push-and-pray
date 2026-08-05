# Docker Compose deployment

Vagrant owns VM creation and networking. Docker Compose owns service processes, health checks, logs, restart policies, and persistent volumes inside each VM.

## Compose projects

| VM | Project | Containers |
|---|---|---|
| Frontend | `airaware-frontend` | `airaware-frontend` |
| Backend | `airaware-backend` | `airaware-backend` |
| Fetcher | `airaware-fetcher` | `airaware-fetcher` |
| Database | `airaware-infrastructure` | `airaware-postgres`, `airaware-redis`, `airaware-rabbitmq` |

Each application build context contains only `requirements.txt` and `app/**`. Local `.env` files, virtual environments, caches, bytecode, Git metadata, documentation, and editor artifacts are excluded.

## Deployment locations

Provisioning copies files to:

```text
/opt/airaware/deploy/frontend
/opt/airaware/deploy/backend
/opt/airaware/deploy/fetcher
/opt/airaware/deploy/infrastructure
```

The role's generated `.env` is mode `0600`. Secrets are never copied from a service-local `.env`; they come from Vagrant's root configuration. User-provided dotenv values are escaped, and credentials embedded in database or AMQP URLs are percent encoded.

## Deployment behavior

The Compose provisioner runs:

1. `docker compose pull --ignore-buildable`;
2. `docker compose build --pull`;
3. `docker compose up -d --remove-orphans --wait --wait-timeout 180`;
4. database migrations on the infrastructure role;
5. `docker compose ps`.

If container health does not settle before the deployment timeout, provisioning prints `docker compose ps --all` and the last 200 log lines, then exits with failure.

## Health model

- Frontend health checks `/health`; readiness also checks the Backend.
- Backend health checks `/health/ready`, which checks PostgreSQL and the RabbitMQ consumer.
- Fetcher health checks `/health`; readiness checks the Backend and RabbitMQ.
- PostgreSQL uses `pg_isready`.
- Redis uses authenticated `PING`.
- RabbitMQ uses `rabbitmq-diagnostics ping`.

Infrastructure checks run frequently during startup but less often after startup to reduce steady-state VM overhead.

## Persistence

The infrastructure project creates:

```text
airaware-postgres-data
airaware-redis-data
airaware-rabbitmq-data
```

Container recreation and `docker compose down` preserve these volumes. `docker compose down -v` deletes them and must be used only when data loss is intentional.

Redis uses AOF persistence with `appendfsync everysec`. RabbitMQ data and PostgreSQL data live in their respective named volumes.

## Database migrations

Migration files are stored in:

```text
backend-service/database/migrations/*.sql
```

After PostgreSQL is healthy, the deployment runner:

- creates `airaware_schema_migrations` if necessary;
- processes migrations in filename order;
- obtains a transaction-scoped advisory lock;
- skips recorded filenames;
- applies each new file and records it in the same transaction;
- stops deployment immediately on SQL errors.

Do not edit an already-applied migration. Add a new zero-padded file such as `002_add_station_metadata.sql`.

## Sessions and Redis

Frontend UI preferences use Flask's signed-cookie session implementation. A stable `FLASK_SECRET_KEY` is required so cookies survive container recreation. Redis remains deployed, authenticated, persisted, and health checked, but frontend readiness does not depend on it.

## RabbitMQ topology

The Fetcher publishes durable measurement events to `airaware.measurements`. The Backend lifespan runs one robust consumer for `airaware.measurements.persist` and acknowledges only after successful persistence.

Malformed or permanently invalid events are rejected without requeueing and are routed to the configured dead-letter exchange. Transient database failures are negatively acknowledged with requeueing.

## Resource and log controls

Every container uses the `json-file` logging driver with:

```yaml
max-size: "10m"
max-file: "3"
```

Infrastructure limits are:

| Service | CPU | Memory | Reservation | PID limit | Stop grace |
|---|---:|---:|---:|---:|---:|
| PostgreSQL | 0.75 | 640 MB | 128 MB | 200 | 30 s |
| Redis | 0.25 | 128 MB | 32 MB | 100 | 30 s |
| RabbitMQ | 1.0 | 640 MB | 256 MB | 300 | 60 s |

These limits prevent one infrastructure process from consuming the entire 2 GB VM while leaving capacity for the guest OS and Docker daemon.

## Common commands

Run inside the corresponding VM and Compose directory:

```bash
sudo docker compose ps
sudo docker compose logs --tail 100
sudo docker compose logs --follow backend
sudo docker compose config --quiet
```

Do not paste unredacted `docker compose config`, `docker inspect`, generated `.env`, or command lines containing credentials into tickets or chat. They can expose secrets.

## RabbitMQ backlog check

```powershell
vagrant ssh database -c "sudo docker exec airaware-rabbitmq rabbitmqctl list_queues -p airaware name messages_ready messages_unacknowledged consumers"
```

To temporarily stop consumption while leaving the Backend API available, edit `RABBITMQ_CONSUMER_ENABLED` in the generated Backend `.env` and recreate the Backend container. Reprovisioning Backend restores the generated default of `true`.
