# Rateboard architecture

## Service flow

```text
CoinGecko / Frankfurter
          |
          v
API Fetcher -- persistent AMQP event --> rates.events
     ^                                      |
     | rates.commands                       v
     +----------------------------- History Service
                                               |
                                               v
Browser -> UI/Nginx -> History API -> PostgreSQL
```

API Fetcher is a write-only data producer from the application perspective. It
has no database credentials and is not reachable by UI. History Service is the
RabbitMQ observation consumer, the only PostgreSQL owner, and the only API used
by UI.

## VM and container layout

| Vagrant VM | Compose project | Containers |
|---|---|---|
| `ui` | `rateboard-ui` | Nginx/static UI |
| `api-fetcher` | `rateboard-api-fetcher` | FastAPI collector |
| `backend-service` | `rateboard-history` | Go History Service |
| `database` | `rateboard-database` | PostgreSQL 16 |
| `rabbitmq` | `rateboard-messaging` | RabbitMQ, Redis |

Each Compose network is local to its VM. `/etc/hosts` and bridged LAN addresses
provide cross-VM resolution.

## Observation delivery

1. API Fetcher retrieves and normalizes a provider value.
2. It publishes a persistent event to `rates.events` with publisher confirms.
3. History Service validates the event and inserts it idempotently.
4. History Service ACKs only after the database operation succeeds.
5. Invalid or repeatedly failing messages are dead-lettered.
6. UI reads the saved value through History API.

There is no synchronous HTTP write fallback.

## Startup reconciliation

History Service groups PostgreSQL data by instrument and finds each maximum
`source_timestamp`. It publishes a bounded command per instrument to
`rates.commands`. API Fetcher retrieves only that instrument’s missing tail,
then publishes normal observation events.

An empty database receives an initial backfill of at most 365 days. An existing
database is never cleared or fully imported again.

## Persistent database

The PostgreSQL Docker volume is a bind-backed volume:

```text
.vagrant-data/database/postgresql.qcow2
  -> ext4 /srv/rateboard-data/postgresql
  -> /var/lib/postgresql/data
```

Container restart, Compose down/up, Vagrant halt/up, and reprovision preserve
the data. The qcow2 disk sits outside `.vagrant`, while source-code `rsync`
remains separate. NFS was rejected by `vagrant validate` on the target setup and
is not used for live PostgreSQL files.

## UI state

The browser saves anonymous presentation state in `localStorage`. Redis remains
an independently deployed infrastructure container but is not a rate store.
