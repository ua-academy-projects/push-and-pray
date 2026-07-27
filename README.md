# Aegis

Aegis is an educational multi-service IP reputation application. It validates
public IPv4 and IPv6 addresses, checks them through AbuseIPDB, persists successful
manual lookups, periodically retrieves blacklist snapshots, and presents the
persisted data through a server-rendered web interface.

## Architecture

Aegis has three independently configured application services:

- **UI Service** renders pages, calls History for application data, and stores
  anonymous browser theme preferences in Redis.
- **History Service** provides the application API, orchestrates manual lookups,
  exclusively owns MariaDB persistence, and consumes blacklist messages from
  RabbitMQ.
- **Provider Service** adapts the AbuseIPDB API. Its standalone worker polls for
  blacklist snapshots, writes them to a local SQLite outbox, and publishes them
  to RabbitMQ.

The supporting infrastructure is:

- **MariaDB**, the authoritative business-data store, accessed only by History;
- **RabbitMQ**, used by Provider and History for asynchronous blacklist snapshot
  delivery;
- **Redis**, used by UI only for expiring theme state;
- **SQLite**, used locally by the Provider worker as its durable delivery outbox.

Provider never accesses MariaDB. UI talks only to History for application data;
it does not call Provider or AbuseIPDB. RabbitMQ is not used for synchronous
browser requests or manual lookup responses.

### Data flows

Manual lookup remains synchronous:

```text
Browser
  → UI
  → History
  → Provider
  → AbuseIPDB
  → History
  → UI
```

Blacklist synchronization is asynchronous:

```text
Provider Worker
  → AbuseIPDB
  → SQLite Outbox
  → RabbitMQ
  → History Consumer
  → MariaDB
```

Theme persistence is UI-local:

```text
Browser session cookie
  → UI Service
  → Redis
```

See [Architecture](docs/architecture.md), [API contracts](docs/api-contracts.md),
[Vagrant development](docs/development-vagrant.md), and
[architecture decisions](docs/adr/) for detailed design information.

## Repository layout

```text
services/
├── ui-service/
├── history-service/
└── provider-service/

provision/             Vagrant provisioning scripts
scripts/               Repository verification helpers
docs/                  Architecture and contract documentation
```

Each service owns its dependencies, configuration, boundary models, and tests.
There is no shared application package.

## Runtime processes

After installing the workspace, the five application processes can be started
from the repository root in separate terminals:

```bash
# UI API
.venv/bin/uvicorn ui_service.main:app \
  --app-dir services/ui-service/src --host 127.0.0.1 --port 8000

# History API
.venv/bin/uvicorn history_service.main:app \
  --app-dir services/history-service/src --host 127.0.0.1 --port 8002

# History blacklist consumer
.venv/bin/aegis-history-blacklist-consumer

# Provider API
.venv/bin/uvicorn provider_service.main:app \
  --app-dir services/provider-service/src --host 127.0.0.1 --port 8001

# Provider blacklist worker
.venv/bin/aegis-provider-blacklist-worker
```

The API ports above match the current service-local environment examples.
Exactly one Provider blacklist worker should run. Set
`BLACKLIST_POLLING_ENABLED=true` only where periodic polling is intended.

## Configuration

Each service loads its own `.env` file. Copy the tracked examples for local
development:

```bash
cp services/ui-service/.env.example services/ui-service/.env
cp services/history-service/.env.example services/history-service/.env
cp services/provider-service/.env.example services/provider-service/.env
```

Configuration references:

- [UI environment example](services/ui-service/.env.example): History and Redis;
- [History environment example](services/history-service/.env.example): MariaDB,
  Provider, and RabbitMQ consumer settings;
- [Provider environment example](services/provider-service/.env.example):
  AbuseIPDB, polling, SQLite outbox, and RabbitMQ publisher settings.

Replace placeholders locally and never commit real credentials. Provider owns
the AbuseIPDB and RabbitMQ publisher credentials, History owns MariaDB and
RabbitMQ consumer credentials, and UI owns Redis connection settings.

## Local development

Install the supported `uv` version and synchronize the locked workspace:

```bash
uv sync --locked --all-packages --all-extras
```

This creates one repository development environment containing the three
independently declared service projects. MariaDB, RabbitMQ, and Redis must be
available and the three service `.env` files must point to them before running
the complete application locally. Ordinary unit tests mock external
infrastructure and AbuseIPDB.

Database schema changes belong to History and are applied with Alembic:

```bash
.venv/bin/alembic -c services/history-service/alembic.ini upgrade head
```

More service-specific setup is documented in the
[UI](services/ui-service/README.md),
[History](services/history-service/README.md), and
[Provider](services/provider-service/README.md) READMEs.

## Vagrant quick start

The Vagrantfile uses VirtualBox with `bento/ubuntu-24.04` and defines five VMs
on the host-only `192.168.100.0/24` network:

| VM | Address | Currently provisioned |
| --- | --- | --- |
| `ui-vm` | `192.168.100.10` | UI API |
| `history-vm` | `192.168.100.11` | History API, consumer, and Alembic migrations |
| `provider-vm` | `192.168.100.12` | Provider API and Provider worker |
| `db-vm` | `192.168.100.13` | MariaDB |
| `infra-vm` | `192.168.100.14` | Native RabbitMQ, management plugin, and Redis |

Create the host-local secret files expected by the Vagrantfile, then run:

```bash
umask 077
mkdir -p ~/.config/aegis
printf '%s\n' 'replace-with-a-local-database-password' \
  > ~/.config/aegis/mariadb-password
# Store the real development AbuseIPDB key in abuseipdb-api-key the same way.
printf '%s\n' 'replace-with-a-provider-broker-password' \
  > ~/.config/aegis/rabbitmq-provider-password
printf '%s\n' 'replace-with-a-history-broker-password' \
  > ~/.config/aegis/rabbitmq-history-password
printf '%s\n' 'replace-with-an-admin-broker-password' \
  > ~/.config/aegis/rabbitmq-admin-password

vagrant up
vagrant status
scripts/smoke-test-vagrant.sh
```

The default secret locations are:

```text
~/.config/aegis/abuseipdb-api-key
~/.config/aegis/mariadb-password
~/.config/aegis/rabbitmq-provider-password
~/.config/aegis/rabbitmq-history-password
~/.config/aegis/rabbitmq-admin-password
```

They can be overridden with `AEGIS_PROVIDER_SECRET_FILE` and
`AEGIS_DATABASE_SECRET_FILE`, or the corresponding
`AEGIS_RABBITMQ_*_SECRET_FILE` variables. Keep these files outside the
repository.

MariaDB listens only on `db-vm`'s private address. Its schema owner accepts
connections only from `history-vm`. History provisioning waits for an
authenticated database connection, runs `alembic upgrade head`, and verifies
the current migration head before starting History API. Reprovisioning does not
automatically import `init_data.sql` or seed blacklist snapshots.

RabbitMQ runs as a native systemd service, not a container. Applications use
the `/aegis` virtual host with separate `aegis_provider` and `aegis_history`
accounts; they never use `guest`. History declares queues, retry queues, and
the DLQ. Broker state persists in RabbitMQ's native `/var/lib/rabbitmq`
directory on `infra-vm`. The management UI is host-loopback only at
`http://127.0.0.1:15672`; AMQP remains private at `192.168.100.14:5672`.

Useful broker diagnostics are:

```bash
vagrant ssh infra-vm -c 'sudo rabbitmq-diagnostics -q ping'
vagrant ssh infra-vm -c 'sudo rabbitmqctl list_queues -p /aegis name consumers messages'
vagrant ssh infra-vm -c 'sudo rabbitmqctl list_bindings -p /aegis'
vagrant ssh history-vm -c 'sudo systemctl status aegis-history-blacklist-consumer'
```

Redis also runs as a native service on `infra-vm`. It binds to loopback and
`192.168.100.14`; UFW permits port 6379 only from `ui-vm`, and no host port is
forwarded. Development Redis has no password because this endpoint is isolated
to that private application path. Production deployments should use a
restricted ACL user and runtime-supplied credentials.

Theme state is non-authoritative and expiring. Development Redis uses periodic
RDB snapshots, no AOF, a 128 MB memory limit, and `allkeys-lru` eviction.
Administrative and bulk-destructive commands are disabled on the endpoint.

```bash
vagrant ssh infra-vm -c 'redis-cli -h 127.0.0.1 ping'
scripts/verify-redis-theme-vagrant.sh
```

The complete smoke test is offline by default: it checks every process,
dependency, health endpoint, migration, queue consumer, UI theme persistence,
outbox path, console entry point, and a focused test selection without calling
AbuseIPDB:

```bash
scripts/smoke-test-vagrant.sh
```

Live blacklist delivery is explicitly opt-in and performs at most one
AbuseIPDB blacklist request. It stops the periodic worker to retain sole polling
ownership, records the generated delivery ID through the SQLite outbox and
confirmed RabbitMQ publication, then verifies MariaDB commit and the consumer
ACK before restoring the worker. It reports available remaining-quota metadata
and never purges the DLQ:

```bash
scripts/smoke-test-vagrant.sh --live-abuseipdb
```

The compatibility command `scripts/verify-vagrant.sh` accepts the same options.

The five application processes run as separate systemd units:

```text
aegis-ui.service
aegis-history-api.service
aegis-history-blacklist-consumer.service
aegis-provider-api.service
aegis-provider-blacklist-worker.service
```

Use the same unit name with `status`, `restart`, or `stop`, and inspect logs
through the journal:

```bash
vagrant ssh history-vm -c \
  'sudo systemctl status aegis-history-api.service'
vagrant ssh history-vm -c \
  'sudo journalctl -u aegis-history-blacklist-consumer.service -f'
vagrant ssh provider-vm -c \
  'sudo systemctl restart aegis-provider-blacklist-worker.service'
vagrant ssh ui-vm -c 'sudo systemctl stop aegis-ui.service'
```

For foreground diagnostics, stop the corresponding unit first and run its
installed executable as `aegis` with the protected environment file:

```bash
# UI API (ui-vm)
sudo -u aegis bash -c 'set -a; source /etc/aegis/ui.env; cd /opt/aegis/ui-service; exec .venv/bin/uvicorn ui_service.main:app --app-dir src --host 192.168.100.10 --port 8000'

# History API or consumer (history-vm)
sudo -u aegis bash -c 'set -a; source /etc/aegis/history.env; cd /opt/aegis/history-service; exec .venv/bin/uvicorn history_service.main:app --app-dir src --host 192.168.100.11 --port 8002'
sudo -u aegis bash -c 'set -a; source /etc/aegis/history.env; cd /opt/aegis/history-service; exec .venv/bin/aegis-history-blacklist-consumer'

# Provider API or worker (provider-vm)
sudo -u aegis bash -c 'set -a; source /etc/aegis/provider.env; cd /opt/aegis/provider-service; exec .venv/bin/uvicorn provider_service.main:app --app-dir src --host 192.168.100.12 --port 8001'
sudo -u aegis bash -c 'set -a; source /etc/aegis/provider.env; cd /opt/aegis/provider-service; exec .venv/bin/aegis-provider-blacklist-worker'
```

## Testing

Run the standard repository checks:

```bash
make check
scripts/typecheck.sh
```

Or run individual checks:

```bash
.venv/bin/uv lock --check
.venv/bin/ruff check .
.venv/bin/ruff format --check .
.venv/bin/pytest
scripts/typecheck.sh
```

Opt-in MariaDB and RabbitMQ integration tests require dedicated infrastructure
and their documented `RUN_MARIADB_TESTS` or `RUN_RABBITMQ_TESTS` configuration.
The default test suite does not require live MariaDB, RabbitMQ, Redis, or
AbuseIPDB.

## Current limitations

- AbuseIPDB is the only reputation provider.
- There is no authentication or user management.
- The Provider worker retrieves at most 1000 entries per blacklist snapshot.
- Redis currently stores only anonymous UI theme preferences.
- Blacklist delivery is at least once; History deduplicates deliveries by
  delivery ID.
- There is no Docker, Kubernetes, cloud deployment, or reverse proxy setup.

The browser reads only persisted blacklist data through UI and History.
Displaying or polling blacklist pages does not call Provider or consume
AbuseIPDB quota.
