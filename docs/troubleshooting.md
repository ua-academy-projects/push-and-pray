# AirAware troubleshooting

## Start with the correct layer

Check Vagrant, containers, and application readiness separately:

```powershell
vagrant status
vagrant ssh database -c "cd /opt/airaware/deploy/infrastructure && sudo docker compose ps"
curl.exe http://192.168.18.211:8001/health/ready
```

A running VM does not guarantee healthy containers, and a running container does not guarantee dependency readiness.

## Vagrant cannot find the bridge adapter

```powershell
VBoxManage list bridgedifs
```

Set `AIRAWARE_BRIDGE_ADAPTER` in the root `.env` to the exact active physical-adapter name. Do not select a virtual adapter unless it is intentionally the LAN path.

## A VM does not receive its bridged address

```powershell
vagrant ssh frontend -c "ip -br address && ip route"
ipconfig
arp -a
```

Common causes include an incorrect prefix, an inactive bridge, a duplicate static address, Wi-Fi client isolation, or stale VirtualBox network configuration. Network adapter changes normally require VM recreation.

## Another LAN device cannot connect

```powershell
Test-NetConnection 192.168.18.210 -Port 5000
```

Confirm both devices are on the same non-guest LAN and that AP/client isolation is disabled. No router port forwarding is required.

## Provisioning appears stuck

Provisioning can spend time downloading packages or images, building Python images, stopping old containers, and waiting for health checks.

Check VM reachability in another terminal:

```powershell
vagrant status
vagrant ssh database -c "uptime"
```

Check host capacity before starting all four VMs:

```powershell
(Get-Counter '\Memory\Available MBytes').CounterSamples
Get-Process VBoxHeadless | Select-Object Id, CPU, WorkingSet
```

Inside the VM:

```bash
free -m
df -h
sudo docker stats --no-stream
```

Do not terminate VirtualBox processes while the database VM is writing. Allow the health-gated deployment to return diagnostics or stop the VM normally.

## Compose deployment fails health waiting

The deployer prints container status and the last 200 log lines automatically. Reinspect with:

```bash
cd /opt/airaware/deploy/infrastructure
sudo docker compose ps --all
sudo docker compose logs --tail 200
```

For one container:

```bash
sudo docker inspect --format '{{json .State.Health}}' airaware-rabbitmq
```

Inspect only `.State.Health`; full inspect output can expose credentials.

## RabbitMQ stays `health: starting`

RabbitMQ can finish application startup before its CLI health probe becomes fast enough to pass. The configured probe allows 20 seconds and runs every 60 seconds after startup.

```bash
sudo docker logs --tail 100 airaware-rabbitmq
sudo docker exec airaware-rabbitmq rabbitmq-diagnostics -q ping
```

Look for `Server startup complete`. Repeated timeouts, restarts, or OOM kills require resource inspection.

## Backend readiness returns 503

Backend readiness requires PostgreSQL and the enabled RabbitMQ consumer.

```bash
cd /opt/airaware/deploy/backend
sudo docker compose logs --tail 200 backend
curl --fail http://127.0.0.1:8001/health/ready
ping -c 2 192.168.18.213
```

From the infrastructure VM:

```bash
sudo docker inspect --format '{{.State.Health.Status}}' airaware-postgres
sudo docker inspect --format '{{.State.Health.Status}}' airaware-rabbitmq
```

Connection attempts are bounded by configured timeouts, so dependency failures should return rather than hang indefinitely.

## Fetcher readiness returns 503

Fetcher readiness requires the Backend and RabbitMQ:

```bash
cd /opt/airaware/deploy/fetcher
sudo docker compose logs --tail 200 fetcher
curl --fail http://192.168.18.211:8001/health/ready
```

Check RabbitMQ separately with `rabbitmq-diagnostics -q ping` on the database VM.

## Frontend readiness returns 503

The frontend checks only the Backend; Redis is not part of signed-cookie sessions.

```bash
cd /opt/airaware/deploy/frontend
sudo docker compose logs --tail 200 frontend
curl --fail http://192.168.18.211:8001/health/ready
```

If session preferences reset after deployment, confirm that the same `AIRAWARE_FLASK_SECRET_KEY` was used. Changing it invalidates existing signed cookies.

## Redis is unhealthy

```bash
sudo docker inspect --format '{{json .State.Health}}' airaware-redis
sudo docker logs --tail 100 airaware-redis
```

Do not print the generated infrastructure `.env` to obtain the password. Reprovision the database role if the generated configuration is suspected to be stale.

## RabbitMQ messages do not reach PostgreSQL

Inspect queue depth and consumer count:

```bash
sudo docker exec airaware-rabbitmq rabbitmqctl list_queues -p airaware \
  name messages_ready messages_unacknowledged consumers
```

Then inspect Backend logs. A healthy deployment normally reports one consumer. Invalid messages go to the dead-letter queue; transient SQL failures are requeued.

## Manual fetch produces no new row

Open-Meteo may return the same observation timestamp more than once. PostgreSQL's unique `(city_id, observed_at)` constraint prevents duplicate rows. This is expected.

## A database migration fails

Infrastructure provisioning exits on the first SQL error:

```bash
cd /opt/airaware/deploy/infrastructure
sudo docker compose logs --tail 100 postgres
sudo docker exec -it airaware-postgres sh -c \
  'psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"'
```

Inspect migration history:

```sql
SELECT version, applied_at
FROM airaware_schema_migrations
ORDER BY version;
```

Fix a new, unapplied migration and reprovision. Do not rewrite a migration already recorded in a shared or persistent environment; create the next numbered migration.

## Image pulls or package installation fail

Check guest routing and DNS:

```bash
ip route
ping -c 2 1.1.1.1
getent hosts download.docker.com
curl -I https://download.docker.com
```

`common.sh` retries `apt-get update`. After a temporary network failure, rerun only the affected provisioner.

## A published port is unreachable

Inside the VM:

```bash
sudo ss -lntp
sudo docker ps --format 'table {{.Names}}\t{{.Ports}}\t{{.Status}}'
```

Expected LAN ports are `5000`, `8001`, `8000`, `5432`, `6379`, `5672`, and `15672`. They are intentionally bound to all VM interfaces.

## Logs consume unexpected disk space

```bash
df -h
sudo docker system df
sudo find /var/lib/docker/containers -name '*-json.log' -printf '%s %p\n' | sort -n | tail
```

Compose limits every container to three 10 MB JSON log files. Old images and build cache may still require periodic review with `docker system df`; do not prune volumes containing required data.

## Data disappeared

Common destructive actions are:

- `docker compose down -v` on the infrastructure project;
- `docker volume rm airaware-postgres-data`;
- `vagrant destroy database -f`.

Restore from a verified backup. Container recreation without `-v` preserves named volumes.

## Shell provisioner reports syntax errors

Project shell scripts are forced to LF endings by `.gitattributes`:

```gitattributes
*.sh text eol=lf
Vagrantfile text eol=lf
```

Use `git diff --check` before committing provisioning changes. Avoid broad renormalization when unrelated user changes are present.
