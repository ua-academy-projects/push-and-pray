# AirAware operations guide

## Daily workflow

Start in dependency order:

```powershell
vagrant up database
vagrant up backend
vagrant up fetcher
vagrant up frontend
```

Check state and readiness:

```powershell
vagrant status
curl.exe http://192.168.18.210:5000/health/ready
curl.exe http://192.168.18.211:8001/health/ready
curl.exe http://192.168.18.212:8000/health/ready
```

Stop normally:

```powershell
vagrant halt
```

Do not use `vagrant destroy` for routine shutdown.

## VM and container access

```powershell
vagrant ssh frontend
vagrant ssh backend
vagrant ssh fetcher
vagrant ssh database
```

Compose directories:

| VM | Directory |
|---|---|
| Frontend | `/opt/airaware/deploy/frontend` |
| Backend | `/opt/airaware/deploy/backend` |
| Fetcher | `/opt/airaware/deploy/fetcher` |
| Database | `/opt/airaware/deploy/infrastructure` |

Inspect status:

```bash
cd /opt/airaware/deploy/backend
sudo docker compose ps
```

## Logs

```bash
sudo docker compose logs --tail 100
sudo docker compose logs --follow backend
sudo docker compose logs --follow fetcher
sudo docker compose logs --follow frontend
```

Infrastructure examples:

```bash
cd /opt/airaware/deploy/infrastructure
sudo docker compose logs --tail 100 postgres
sudo docker compose logs --tail 100 redis
sudo docker compose logs --tail 100 rabbitmq
```

Logs rotate automatically at 10 MB with three files per container.

## Restart and redeploy

Restart one existing container without rebuilding:

```bash
sudo docker compose restart backend
```

Deploy host-side source changes:

```powershell
vagrant provision backend --provision-with compose
```

Equivalent commands apply to `frontend`, `fetcher`, and `database`. Reprovisioning regenerates the role's `.env`; direct edits under `/opt/airaware` are temporary.

## Manual data collection

```powershell
curl.exe -X POST http://192.168.18.212:8000/fetch
curl.exe http://192.168.18.212:8000/fetch/status
```

Only one fetch can run at a time. A concurrent request returns `409`. Publishing the same provider observation more than once is safe because PostgreSQL enforces `(city_id, observed_at)` uniqueness.

## RabbitMQ operations

Check the broker:

```powershell
vagrant ssh database -c "sudo docker exec airaware-rabbitmq rabbitmq-diagnostics -q ping"
```

Inspect queues:

```powershell
vagrant ssh database -c "sudo docker exec airaware-rabbitmq rabbitmqctl list_queues -p airaware name messages_ready messages_unacknowledged consumers"
```

The persistence queue normally has one consumer. `messages_ready` may temporarily grow while the Backend is unavailable and should drain after the consumer reconnects.

## PostgreSQL inspection

On the database VM:

```bash
sudo docker exec -it airaware-postgres sh -c \
  'psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"'
```

Useful queries:

```sql
SELECT code, name, is_active
FROM cities
ORDER BY name;

SELECT
    c.code,
    m.observed_at,
    m.european_aqi,
    m.pm2_5,
    m.pm10
FROM air_quality_measurements AS m
JOIN cities AS c ON c.id = m.city_id
ORDER BY m.observed_at DESC
LIMIT 50;

SELECT version, applied_at
FROM airaware_schema_migrations
ORDER BY version;
```

## Redis status

Redis is retained as an independent infrastructure service. It is not the Flask session backend.

Check its authenticated Docker health result without printing the password:

```bash
sudo docker inspect --format '{{.State.Health.Status}}' airaware-redis
```

Expected output is `healthy`.

## Resource checks

Inside any VM:

```bash
free -m
df -h
sudo docker stats --no-stream
sudo docker system df
```

Infrastructure limits can be confirmed without displaying environment variables:

```bash
sudo docker inspect --format \
  '{{.Name}} memory={{.HostConfig.Memory}} cpu={{.HostConfig.NanoCpus}} pids={{.HostConfig.PidsLimit}}' \
  airaware-postgres airaware-redis airaware-rabbitmq
```

## PostgreSQL backup

Create a host-visible directory from the database VM:

```bash
mkdir -p /vagrant/backups
sudo docker exec airaware-postgres sh -c \
  'pg_dump --format=custom --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"' \
  > /vagrant/backups/airaware.dump
```

Verify that the dump is non-empty:

```bash
ls -lh /vagrant/backups/airaware.dump
```

Treat backups as sensitive and do not commit them.

## PostgreSQL restore

Stop writers first by stopping Backend and Fetcher containers. Then, on the database VM:

```bash
sudo docker exec -i airaware-postgres sh -c \
  'pg_restore --clean --if-exists --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"' \
  < /vagrant/backups/airaware.dump
```

Restart the application containers and verify readiness afterward.

## Persistent-volume safety

These operations retain volumes:

```bash
sudo docker compose restart
sudo docker compose down
sudo docker compose up -d
```

These operations remove data and require an intentional backup decision:

```bash
sudo docker compose down -v
```

```powershell
vagrant destroy database -f
```

## Secret-handling precautions

Generated `.env` files are mode `0600`. Avoid commands or screenshots that print:

- `/opt/airaware/deploy/*/.env`;
- full `docker inspect` output;
- unredacted `docker compose config` output;
- database or broker URLs.

When a secret is exposed, rotate it in the root `.env` and reprovision all roles that receive it.
