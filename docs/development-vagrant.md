# Vagrant development environment

This guide covers the repository's five-VM VirtualBox environment. RabbitMQ,
Redis, and MariaDB are native Ubuntu services; Docker commands do not apply to
this deployment.

## Prerequisites

Install:

- Vagrant;
- VirtualBox, the provider configured by the `Vagrantfile`;
- Git.

The base box is `bento/ubuntu-24.04`. The configured guests allocate six virtual
CPUs and 6 GB RAM in total. Allow at least 8 GB free host RAM so VirtualBox and
the host remain usable, six logical CPU threads, and approximately 20 GB free
disk for dynamically allocated guest disks, package caches, and database data.
The repository does not set a fixed virtual-disk size.

The only forwarded host port is TCP 15672 on `127.0.0.1` for RabbitMQ
management. It must be free. The host-only network uses
`192.168.100.0/24`; make sure it does not conflict with an existing host or VPN
route. Redis, AMQP, and MariaDB have no host-forwarded ports.

## First start

Clone the repository and enter it:

```bash
git clone <repository-url> Aegis
cd Aegis
```

Create development secrets outside the repository:

```bash
umask 077
mkdir -p ~/.config/aegis
printf '%s\n' 'your-real-abuseipdb-key' \
  > ~/.config/aegis/abuseipdb-api-key
printf '%s\n' 'choose-a-development-database-password' \
  > ~/.config/aegis/mariadb-password
printf '%s\n' 'choose-a-provider-rabbitmq-password' \
  > ~/.config/aegis/rabbitmq-provider-password
printf '%s\n' 'choose-a-history-rabbitmq-password' \
  > ~/.config/aegis/rabbitmq-history-password
printf '%s\n' 'choose-a-management-rabbitmq-password' \
  > ~/.config/aegis/rabbitmq-admin-password
```

These values are development-only. Do not reuse production credentials.

Start and verify the environment:

```bash
vagrant up
scripts/smoke-test-vagrant.sh
```

The first run downloads the box, installs operating-system and Python
dependencies, and builds three virtual environments. A typical first provision
takes roughly 10–30 minutes, but network speed and package mirrors can make it
longer. Subsequent provisioning is normally faster.

Open:

- UI: `http://192.168.100.10:8000/`
- RabbitMQ management: `http://127.0.0.1:15672/`

Log in to RabbitMQ management as `aegis_admin` with the local admin password.
History and Provider diagnostics are intentionally reached from their guests,
not through forwarded host ports.

## Topology and ports

| VM | Address | Processes and infrastructure |
| --- | --- | --- |
| `ui-vm` | `192.168.100.10` | UI API |
| `history-vm` | `192.168.100.11` | History API and History blacklist consumer |
| `provider-vm` | `192.168.100.12` | Provider API, Provider blacklist worker, and SQLite outbox |
| `db-vm` | `192.168.100.13` | MariaDB |
| `infra-vm` | `192.168.100.14` | RabbitMQ, management plugin, and Redis |

| Endpoint | Guest binding | Allowed caller or host mapping |
| --- | --- | --- |
| UI HTTP | `192.168.100.10:8000` | Host-only subnet |
| History HTTP | `192.168.100.11:8002` | UI and local History diagnostics |
| Provider HTTP | `192.168.100.12:8001` | History and local Provider diagnostics |
| MariaDB | `192.168.100.13:3306` | History only |
| RabbitMQ AMQP | `192.168.100.14:5672` | Provider and History only |
| RabbitMQ management | guest `15672` | host `127.0.0.1:15672` |
| Redis | `127.0.0.1:6379`, `192.168.100.14:6379` | UI only |

The synchronous path is Browser → UI → History → Provider → AbuseIPDB.
Blacklist delivery is Provider Worker → SQLite outbox → RabbitMQ → History
Consumer → MariaDB. Browser theme state is UI → Redis. Only History receives
MariaDB credentials.

## Runtime processes

| Unit | VM | Working directory | Environment |
| --- | --- | --- | --- |
| `aegis-ui.service` | `ui-vm` | `/opt/aegis/ui-service` | `/etc/aegis/ui.env` |
| `aegis-history-api.service` | `history-vm` | `/opt/aegis/history-service` | `/etc/aegis/history.env` |
| `aegis-history-blacklist-consumer.service` | `history-vm` | `/opt/aegis/history-service` | `/etc/aegis/history.env` |
| `aegis-provider-api.service` | `provider-vm` | `/opt/aegis/provider-service` | `/etc/aegis/provider.env` |
| `aegis-provider-blacklist-worker.service` | `provider-vm` | `/opt/aegis/provider-service` | `/etc/aegis/provider.env` |

All run as the unprivileged `aegis` user. APIs, worker, and consumer are
separate processes; neither background process runs inside FastAPI.

## Configuration and secrets

The host secret paths can be overridden before invoking Vagrant:

| Default host path | Override |
| --- | --- |
| `~/.config/aegis/abuseipdb-api-key` | `AEGIS_PROVIDER_SECRET_FILE` |
| `~/.config/aegis/mariadb-password` | `AEGIS_DATABASE_SECRET_FILE` |
| `~/.config/aegis/rabbitmq-provider-password` | `AEGIS_RABBITMQ_PROVIDER_SECRET_FILE` |
| `~/.config/aegis/rabbitmq-history-password` | `AEGIS_RABBITMQ_HISTORY_SECRET_FILE` |
| `~/.config/aegis/rabbitmq-admin-password` | `AEGIS_RABBITMQ_ADMIN_SECRET_FILE` |

Provisioning uploads secrets temporarily, writes the relevant protected
`/etc/aegis/*.env` file, and removes the temporary upload. Redis has no
development password: it is bound to the infrastructure VM and UFW permits
only `ui-vm`. Production should use a restricted Redis ACL account.

Do not print, copy into tickets, or commit `/etc/aegis/*.env`.

## Common commands

List and enter guests:

```bash
vagrant status
vagrant ssh ui-vm
vagrant ssh history-vm
vagrant ssh provider-vm
vagrant ssh db-vm
vagrant ssh infra-vm
```

Inspect application status and logs:

```bash
vagrant ssh ui-vm -c 'sudo systemctl status aegis-ui.service'
vagrant ssh history-vm -c 'sudo systemctl status aegis-history-api.service aegis-history-blacklist-consumer.service'
vagrant ssh provider-vm -c 'sudo systemctl status aegis-provider-api.service aegis-provider-blacklist-worker.service'
vagrant ssh history-vm -c 'sudo journalctl -u aegis-history-blacklist-consumer.service -n 100 --no-pager'
vagrant ssh provider-vm -c 'sudo journalctl -u aegis-provider-blacklist-worker.service -f'
```

Check MariaDB and the History-owned schema:

```bash
vagrant ssh db-vm -c 'sudo mysqladmin --protocol=socket ping'
vagrant ssh history-vm -c \
  "sudo -u aegis bash -c 'set -a; source /etc/aegis/history.env; cd /opt/aegis/history-service; .venv/bin/alembic -c alembic.ini current --check-heads'"
```

Check RabbitMQ:

```bash
vagrant ssh infra-vm -c 'sudo rabbitmq-diagnostics -q ping'
vagrant ssh infra-vm -c \
  'sudo rabbitmqctl list_queues -p /aegis name messages_ready messages_unacknowledged consumers'
vagrant ssh infra-vm -c 'sudo rabbitmqctl list_bindings -p /aegis'
```

Inside `infra-vm`, the native-service form requested by RabbitMQ tooling is:

```bash
sudo rabbitmqctl list_queues -p /aegis \
  name messages_ready messages_unacknowledged consumers
```

A Docker-hosted RabbitMQ uses a command such as
`docker exec <container> rabbitmqctl ...`. That is not the Vagrant command:
there is no RabbitMQ container in this environment.

Check Redis without revealing theme session keys:

```bash
vagrant ssh infra-vm -c 'redis-cli -h 127.0.0.1 ping'
vagrant ssh infra-vm -c 'redis-cli -h 127.0.0.1 DBSIZE'
```

Inspect the Provider outbox without changing it:

```bash
vagrant ssh provider-vm -c \
  "sudo -u aegis sqlite3 /var/lib/aegis-provider/blacklist-outbox.sqlite3 '.tables'"
vagrant ssh provider-vm -c \
  "sudo -u aegis sqlite3 /var/lib/aegis-provider/blacklist-outbox.sqlite3 'SELECT COUNT(*) FROM blacklist_outbox;'"
```

## Theme verification

Use the theme control in the UI to switch between light and dark, refresh the
page, and confirm the selected theme remains. The automated equivalent also
checks TTL, Redis restart, UI restart, and the default-theme fallback:

```bash
scripts/verify-redis-theme-vagrant.sh
```

For manual inspection, obtain the `theme_session` cookie locally from browser
developer tools. Do not paste it into shared logs. In a private terminal:

```bash
vagrant ssh infra-vm
redis-cli -h 127.0.0.1 --raw GET "theme:<local-session-id>"
redis-cli -h 127.0.0.1 TTL "theme:<local-session-id>"
```

Allowed values are `light` and `dark`. Redis failure does not stop UI pages;
theme reads fall back to dark, although `/health/ready` reports the dependency
failure.

## Blacklist synchronization verification

The offline smoke test checks the worker, outbox path, broker topology,
registered consumer, database migration, and History blacklist status without
calling AbuseIPDB:

```bash
scripts/smoke-test-vagrant.sh
vagrant ssh provider-vm -c \
  'sudo journalctl -u aegis-provider-blacklist-worker.service -n 100 --no-pager'
vagrant ssh history-vm -c \
  'sudo journalctl -u aegis-history-blacklist-consumer.service -n 100 --no-pager'
```

An explicitly live trace performs at most one blacklist request, reports the
remaining rate limit when AbuseIPDB supplies it, and follows one `delivery_id`
through outbox, confirmed publication, MariaDB commit, and ACK:

```bash
scripts/smoke-test-vagrant.sh --live-abuseipdb
```

Do not use live mode casually. The independently scheduled Provider worker also
owns normal polling and consumes quota according to its persisted schedule.

## Reprovisioning and lifecycle

Re-run all idempotent provisioners:

```bash
vagrant provision
```

Reprovision one role after source, dependency, unit, or configuration changes:

```bash
vagrant provision provider-vm
vagrant provision history-vm
vagrant provision ui-vm
vagrant provision infra-vm
vagrant provision db-vm
```

Use `vagrant reload <vm>` after changing VM-level networking or VirtualBox
settings. A service-only configuration change normally needs provisioning or a
`systemctl restart`, not a VM reload.

Destroy and recreate an individual VM when its base operating-system state or
virtual disk must be rebuilt:

```bash
vagrant destroy provider-vm
vagrant up provider-vm
```

This deletes that guest's local data. Avoid `vagrant destroy` for ordinary
application updates.

## Troubleshooting

### Port or network conflicts

If `127.0.0.1:15672` is occupied, identify and stop the conflicting host
process; the Vagrantfile deliberately disables automatic port correction.
If `192.168.100.0/24` overlaps a VPN or existing route, change the complete
private-network plan consistently in the Vagrantfile, provisioning
configuration, firewall rules, and documentation before recreating the VMs.

### Missing console scripts

```bash
vagrant ssh history-vm -c \
  'test -x /opt/aegis/history-service/.venv/bin/aegis-history-blacklist-consumer'
vagrant ssh provider-vm -c \
  'test -x /opt/aegis/provider-service/.venv/bin/aegis-provider-blacklist-worker'
```

If either fails, reprovision that application VM and inspect the provisioning
output for `pip` installation errors.

### Migration failure

Check MariaDB, History configuration permissions, and Alembic output:

```bash
vagrant ssh db-vm -c 'sudo systemctl status mariadb.service'
vagrant ssh history-vm -c \
  "sudo -u aegis bash -c 'set -a; source /etc/aegis/history.env; cd /opt/aegis/history-service; .venv/bin/alembic -c alembic.ini upgrade head'"
```

### RabbitMQ authentication or no consumer

```bash
vagrant ssh infra-vm -c 'sudo rabbitmqctl list_permissions -p /aegis'
vagrant ssh history-vm -c 'sudo systemctl restart aegis-history-blacklist-consumer.service'
vagrant ssh infra-vm -c \
  'sudo rabbitmqctl list_queues -p /aegis name consumers messages_ready messages_unacknowledged'
```

Confirm the Provider and History password files used by Vagrant still match
their generated `/etc/aegis/*.env` configuration; do not print either value.
Reprovision `infra-vm`, then the affected application VM, after rotating one.

### Messages in the DLQ

Inspect without deleting:

```bash
vagrant ssh infra-vm -c \
  "sudo rabbitmqctl list_queues -p /aegis name messages | grep 'aegis.history.blacklist.snapshots.dead'"
vagrant ssh history-vm -c \
  'sudo journalctl -u aegis-history-blacklist-consumer.service --since today --no-pager'
```

Do not purge or replay DLQ messages until their validation or persistence
failure is understood.

### Redis unavailable

```bash
vagrant ssh infra-vm -c 'sudo systemctl status redis-server.service'
vagrant ssh infra-vm -c 'redis-cli -h 127.0.0.1 ping'
vagrant ssh ui-vm -c 'curl --fail http://192.168.100.10:8000/health/live'
```

UI liveness and pages should remain available with the dark default;
readiness may fail until Redis returns.

### AbuseIPDB 401 or 429

A 401 normally means the host API-key file is invalid; replace it and
reprovision `provider-vm`. A 429 means the worker must honor `Retry-After` or
the reset time. Do not repeatedly restart or force live tests:

```bash
vagrant ssh provider-vm -c \
  "sudo journalctl -u aegis-provider-blacklist-worker.service --since today --no-pager | grep -E 'rate_limited|next_poll_at'"
```

### UTC interpretation

Provider timestamps require an explicit offset. History stores normalized UTC
values in MariaDB's timezone-neutral `DATETIME(6)` columns. Check guest clocks
and database UTC separately:

```bash
vagrant ssh provider-vm -c 'timedatectl'
vagrant ssh history-vm -c 'timedatectl'
vagrant ssh db-vm -c \
  "sudo mariadb --protocol=socket -e 'SELECT @@system_time_zone, @@session.time_zone, UTC_TIMESTAMP(6);'"
```

Do not reinterpret stored UTC values as the host's local timezone.

### Outbox lock or permissions

Only one worker may hold the adjacent SQLite lock:

```bash
vagrant ssh provider-vm -c \
  'sudo systemctl status aegis-provider-blacklist-worker.service'
vagrant ssh provider-vm -c \
  "sudo stat -c '%U:%G:%a %n' /var/lib/aegis-provider /var/lib/aegis-provider/blacklist-outbox.sqlite3"
```

The directory must be `aegis:aegis` mode `750`. Stop the supervised worker
before any foreground worker diagnostic. Do not delete a lock while a worker
process is running.

## Data reset procedures

These operations are destructive. Back up anything needed first and reset only
the owning subsystem.

### Application database

The cleanest complete database reset is an exact-VM replacement:

```bash
vagrant ssh history-vm -c \
  'sudo systemctl stop aegis-history-api.service aegis-history-blacklist-consumer.service'
vagrant destroy db-vm
vagrant up db-vm
vagrant provision history-vm
```

This removes MariaDB application data only; it does not clear RabbitMQ, Redis,
or the Provider outbox.

### RabbitMQ queues

Deleting queues destroys ready, unacknowledged-after-requeue, retry, and DLQ
messages. Stop the consumer first. Delete only the named `/aegis` queues, then
restart the consumer so application-declared topology is recreated:

```bash
vagrant ssh history-vm -c \
  'sudo systemctl stop aegis-history-blacklist-consumer.service'
vagrant ssh infra-vm -c \
  'for queue in aegis.history.blacklist.snapshots aegis.history.blacklist.snapshots.retry.300 aegis.history.blacklist.snapshots.retry.900 aegis.history.blacklist.snapshots.retry.1800 aegis.history.blacklist.snapshots.retry.3600 aegis.history.blacklist.snapshots.dead; do sudo rabbitmqctl delete_queue -p /aegis "$queue"; done'
vagrant ssh history-vm -c \
  'sudo systemctl start aegis-history-blacklist-consumer.service'
```

This does not reset MariaDB delivery IDs or the Provider outbox. Re-delivering
an already committed `delivery_id` remains an accepted duplicate.

### Redis UI preferences

Delete one locally known anonymous session key:

```bash
vagrant ssh infra-vm -c \
  "redis-cli -h 127.0.0.1 DEL 'theme:<local-session-id>'"
```

Redis bulk flush commands are disabled. Theme keys also expire after 30 days
and use `allkeys-lru` eviction. Do not expose session identifiers in shared
logs.

### Provider SQLite outbox

The outbox may contain fetched but unpublished snapshots. Preserve it unless a
deliberate data-loss reset is required:

```bash
vagrant ssh provider-vm -c \
  'sudo systemctl stop aegis-provider-blacklist-worker.service'
vagrant ssh provider-vm -c \
  "sudo -u aegis sqlite3 /var/lib/aegis-provider/blacklist-outbox.sqlite3 'PRAGMA wal_checkpoint(TRUNCATE);'"
vagrant ssh provider-vm -c \
  'sudo -u aegis mkdir /var/lib/aegis-provider/outbox-reset-backup'
vagrant ssh provider-vm -c \
  'sudo -u aegis mv /var/lib/aegis-provider/blacklist-outbox.sqlite3* /var/lib/aegis-provider/outbox-reset-backup/'
vagrant ssh provider-vm -c \
  'sudo systemctl start aegis-provider-blacklist-worker.service'
```

The move is recoverable, but it discards the active polling schedule and
pending-delivery state. The worker creates a fresh database. Move or rename an
existing `outbox-reset-backup` directory before repeating this reset.

## Security warning

The Vagrant users, passwords, network policy, and HTTP-only cookies are for an
isolated development machine. They are not production secret management,
transport security, or Internet-edge firewall configuration. Never commit the
host secret files, guest environment files, API keys, database passwords, or
RabbitMQ passwords.
