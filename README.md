# Rateboard

Rateboard displays current and historical cryptocurrency and fiat rates through
a five-VM Vagrant/QEMU deployment.

```text
Providers -> API Fetcher -> RabbitMQ -> History Service -> PostgreSQL
Browser   -> UI/Nginx ----------------> History Service -> PostgreSQL
```

API Fetcher only retrieves and normalizes provider data. History Service
consumes RabbitMQ observations, owns PostgreSQL, and serves every UI read.

## Repository

```text
api-fetcher/                 Python provider collector and MQ producer
backend-service/             Go History API, MQ consumer, PostgreSQL owner
ui-service/                  Static UI and Nginx image
infra/docker/                One Compose project per VM
infra/vagrant/provision/     Docker bootstrap and per-role deploy scripts
backend-service/migrations/  PostgreSQL migrations
scripts/                     Deploy, verify, stop, and manual backfill helpers
```

## Five-VM layout

| VM | Default LAN address | Workload |
|---|---:|---|
| `ui` | `192.168.0.221` | UI/Nginx container |
| `api-fetcher` | `192.168.0.222` | FastAPI collector container |
| `backend-service` | `192.168.0.223` | Go History Service container |
| `database` | `192.168.0.224` | PostgreSQL container |
| `rabbitmq` | `192.168.0.225` | RabbitMQ and Redis containers |

Choose unused addresses in the real LAN and reserve them before booting.

Every VM has its own Docker daemon, Compose project, network, logs, and
lifecycle. Cross-VM connections use bridged LAN names:

```text
rates-ui
rates-api-fetcher
rates-backend-service
rates-db
rates-rabbitmq
```

## Prerequisites on macOS

Install QEMU, Vagrant, and the QEMU provider:

```bash
brew install qemu
brew install --cask vagrant
vagrant plugin install vagrant-qemu
```

The bridged `vmnet` lifecycle requires `sudo`.

## Configuration

Create the main environment file:

```bash
cp .env.example .env
```

Create the ignored Vagrant-local file:

```bash
cp infra/vagrant/.env.vagrant.example .env.vagrant.local
```

Set:

- five unused LAN IP addresses;
- the actual macOS network interface, normally `en0`;
- API Fetcher internal token;
- PostgreSQL password;
- RabbitMQ username, password, and vhost;
- Redis password;
- optional CoinGecko key.

Do not commit `.env`, `.env.vagrant.local`, or generated files.

## Deploy

The deployment order is:

```text
PostgreSQL -> RabbitMQ/Redis -> History Service -> API Fetcher -> UI
```

Run:

```bash
sudo ./scripts/deploy-vagrant-compose.sh
```

The script:

1. starts all five VMs in dependency order;
2. synchronizes source files;
3. installs Docker Engine and the Compose plugin;
4. starts the independent Compose project on each VM;
5. applies idempotent PostgreSQL migrations;
6. checks Compose and HTTP health.

Direct equivalent:

```bash
sudo vagrant up database rabbitmq backend-service api-fetcher ui --provider=qemu
sudo vagrant rsync
sudo vagrant provision database
sudo vagrant provision rabbitmq
sudo vagrant provision backend-service
sudo vagrant provision api-fetcher
sudo vagrant provision ui
```

Open:

```text
https://<RATEBOARD_UI_IP>/
https://rateboard.test/
```

Use `scripts/update-local-hosts.sh` to reconcile `rateboard.test` with
`.env.vagrant.local`.

## Verify

```bash
sudo ./scripts/check-vm-deployment.sh
```

Inspect an individual project:

```bash
sudo vagrant ssh api-fetcher -c \
  'sudo docker compose -f /vagrant/infra/docker/api-fetcher/compose.yml ps'

sudo vagrant ssh backend-service -c \
  'sudo docker compose -f /vagrant/infra/docker/backend-service/compose.yml logs --tail=100'

sudo vagrant ssh rabbitmq -c \
  'sudo docker compose -f /vagrant/infra/docker/rabbitmq/compose.yml ps'
```

Health endpoints:

```text
http://<RATEBOARD_API_FETCHER_IP>:8000/health/ready
http://<RATEBOARD_BACKEND_SERVICE_IP>:8081/health/ready
```

API Fetcher readiness requires its RabbitMQ publisher and command consumer.
History readiness requires PostgreSQL and its observation consumer.

## Stop without deleting data

```bash
sudo ./scripts/stop-vagrant-compose.sh
sudo vagrant halt
```

The stop script intentionally uses `docker compose down` without `-v`.

Never use this during normal operation:

```bash
docker compose down -v
```

## PostgreSQL persistence

Database files follow this path:

```text
host .vagrant-data/database/postgresql.qcow2
  -> database VM ext4 /srv/rateboard-data/postgresql
  -> Docker volume postgresql_data
  -> container /var/lib/postgresql/data
```

The source tree remains an `rsync` synced folder. PostgreSQL data is separate.
The installed `vagrant-qemu` supports extra disks, while `vagrant validate`
reports NFS as unusable on the target Mac. The database therefore uses a
host-side qcow2 disk rather than placing live PostgreSQL files on NFS/SMB.

The normal lifecycle preserves database state across:

- PostgreSQL container restart;
- Compose down/up without `-v`;
- Vagrant halt/up;
- repeated provision;
- image rebuild.

The disk file is outside `.vagrant`, so it is designed to survive
`vagrant destroy`. Do not claim that destructive scenario as runtime-verified
unless it was explicitly authorized and executed.

## Initial and incremental backfill

On History Service startup:

1. PostgreSQL is queried for the latest `source_timestamp` per instrument.
2. A missing instrument receives a backfill command for at most 365 days.
3. An existing instrument receives a command from its own latest timestamp.
4. Commands are published to `rates.commands`.
5. API Fetcher consumes commands and publishes observations to `rates.events`.
6. History Service inserts observations and ACKs after the database operation.

Repeated deliveries are safe because PostgreSQL insertion is idempotent.

Manual full-year collection:

```bash
./scripts/backfill-year.sh
```

The script calls API Fetcher’s authenticated internal endpoint. API Fetcher
still writes only RabbitMQ; it does not bypass History Service or PostgreSQL
ownership.

## RabbitMQ topology

```text
rates.commands
  -> rates.fetch.commands
  -> rates.fetch.commands.dlq

rates.events
  -> rates.observations
  -> rates.observations.dlq
```

Messages and queues are durable. API Fetcher uses publisher confirms. History
Service ACKs an observation only after an idempotent PostgreSQL insert.

There is no direct API Fetcher -> History HTTP write fallback.

## UI API

UI calls only History Service through same-origin Nginx:

```text
GET /api/v1/instruments
GET /api/v1/overview
GET /api/v1/rates/current
GET /api/v1/rates/stored-current
GET /api/v1/rates/history
GET /api/v1/market-map
```

Anonymous presentation state is stored in browser `localStorage`. Redis is not
used for rate data.

## Static verification

```bash
python3 -m compileall -q api-fetcher/app
api-fetcher/.venv/bin/pytest -q

cd backend-service
GOCACHE=/private/tmp/rateboard-go-cache go test ./...
cd ..

npm --prefix ui-service test
ruby -c Vagrantfile
bash -n infra/vagrant/provision/*.sh scripts/*.sh
git diff --check
```

Static checks do not prove that QEMU, NFS, bridged networking, containers, or
external providers work at runtime. Use the five-VM verification script on the
target Mac for that proof.

## More documentation

- [Architecture](docs/architecture.md)
- [API](docs/api.md)
- [Compliance matrix](docs/assignment-compliance.md)
