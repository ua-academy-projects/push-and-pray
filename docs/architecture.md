# Aegis architecture

## Purpose

Aegis is an educational multi-service IP reputation application. It validates
public IPv4 and IPv6 addresses, performs individual AbuseIPDB reputation
lookups, periodically retrieves AbuseIPDB blacklist snapshots, persists
authoritative business data, and renders the persisted results.

The architecture favors explicit ownership, independently configured service
boundaries, durable asynchronous delivery, and failure behavior that preserves
the latest successful data.

## Logical services and runtime processes

A logical service owns a cohesive boundary and its configuration, models,
tests, and dependencies. A runtime process is one independently supervised
executable belonging to a logical service.

| Logical service | Runtime process | Purpose |
| --- | --- | --- |
| UI Service | UI API | Renders pages, handles browser requests, calls History, and manages anonymous theme state |
| History Service | History API | Exposes `/api/v1/*`, orchestrates manual lookups, and reads and writes MariaDB |
| History Service | History blacklist consumer | Consumes and transactionally persists blacklist messages |
| Provider Service | Provider API | Exposes `/internal/v1/*` and adapts individual AbuseIPDB requests |
| Provider Service | Provider blacklist worker | Polls AbuseIPDB, owns the SQLite outbox, and publishes blacklist messages |

The API and background process within a logical service share service code and
configuration, but not process lifecycle. Running the Provider API does not
start polling. Running the History API does not start RabbitMQ consumption.

```text
Browser
  |
  v
UI Service (UI API) ------ HTTP ------> History Service (History API)
  |                                           |
  | Redis                                     | MariaDB
  v                                           v
Redis                                      MariaDB
                                              |
                                              | HTTP for manual lookups
                                              v
                                    Provider Service (Provider API)
                                              |
                                              v
                                          AbuseIPDB

Provider Service (Provider blacklist worker)
  | AbuseIPDB
  | SQLite outbox
  v
RabbitMQ ------> History Service (History blacklist consumer) ------> MariaDB
```

## Service boundaries

### UI Service

UI Service owns presentation and anonymous UI state.

Responsibilities:

- render forms, history, blacklist tables, analytics, and safe errors;
- submit manual lookups to History Service;
- read persisted blacklist data and status from History Service;
- poll History-backed status without triggering synchronization;
- create anonymous browser session IDs;
- load and save validated `light` or `dark` theme values in Redis;
- refresh the cookie and Redis inactivity TTL during relevant activity.

Restrictions:

- communicates only with History Service for application data;
- does not call Provider Service or AbuseIPDB;
- does not access MariaDB or RabbitMQ;
- does not store business data in Redis;
- does not treat the anonymous session ID as an authenticated identity.

### History Service

History Service is the application backend and sole MariaDB owner.

Responsibilities:

- expose the application API under `/api/v1/*`;
- validate and normalize public IPv4 and IPv6 addresses;
- enforce manual lookup request idempotency;
- call Provider API for normalized manual reputation data;
- persist successful manual lookup results;
- expose lookup history, blacklist snapshots, status, and analytics;
- own SQLAlchemy models, repositories, Alembic migrations, and transactions;
- consume, validate, and persist complete RabbitMQ blacklist messages;
- deduplicate snapshot delivery by `delivery_id`;
- preserve the latest successful snapshot when later processing fails.

Restrictions:

- does not call AbuseIPDB directly and does not receive its API key;
- does not expose MariaDB models directly across HTTP boundaries;
- does not accept blacklist snapshots from Provider through HTTP;
- does not put SQL in API handlers or RabbitMQ callbacks.

### Provider Service

Provider Service is the internal AbuseIPDB adapter.

Responsibilities:

- expose the internal Provider API under `/internal/v1/*`;
- authenticate to AbuseIPDB;
- apply explicit HTTPX timeouts;
- validate and normalize upstream data;
- map provider failures into safe service errors;
- extract rate-limit and `Retry-After` metadata;
- own periodic blacklist polling in the standalone Provider blacklist worker;
- commit complete messages to the SQLite outbox before publication;
- publish persistent messages to RabbitMQ with publisher confirms;
- retry retained outbox messages after broker or confirmation failures.

Restrictions:

- does not communicate with UI Service;
- does not access MariaDB or Redis;
- does not deliver blacklist snapshots to History through HTTP;
- does not implement application lookup idempotency;
- does not consume blacklist messages.

## Synchronous flows

### Manual lookup

```text
Browser -> UI API -> History API -> Provider API -> AbuseIPDB
Browser <- UI API <- History API <- Provider API <- AbuseIPDB
```

Detailed sequence:

```text
Browser          UI API          History API       Provider API       AbuseIPDB
   |                |                 |                  |                 |
   | submit IP      |                 |                  |                 |
   |--------------->| lookup request  |                  |                 |
   |                |---------------->| validate IP and  |                 |
   |                |                 | request_id       |                 |
   |                |                 | check idempotency|                 |
   |                |                 | reputation check |                 |
   |                |                 |----------------->| HTTPS request   |
   |                |                 |                  |---------------->|
   |                |                 |                  | validate and    |
   |                |                 |                  | normalize       |
   |                |                 |<-----------------| normalized data |
   |                |                 | commit success   |                 |
   |                |<----------------| persisted result |                 |
   |<---------------| render response |                  |                 |
```

History persists a successful lookup before returning it. Failed provider
lookups are not persisted. Reusing a `request_id` with the same payload returns
the existing result; reusing it with a different payload returns
`409 IDEMPOTENCY_CONFLICT`.

### Persisted blacklist reads and analytics

```text
Browser -> UI API -> History API -> MariaDB
```

These reads use only persisted business data. Browser polling and page rendering
never call Provider Service or AbuseIPDB and never consume provider quota.

## Asynchronous blacklist synchronization

```text
Provider blacklist worker
  -> AbuseIPDB
  -> SQLite outbox
  -> RabbitMQ
  -> History blacklist consumer
  -> MariaDB
```

Detailed sequence:

```text
Provider worker     AbuseIPDB       SQLite outbox       RabbitMQ       History consumer       MariaDB
      |                  |                 |                 |                 |                  |
      | fetch snapshot   |                 |                 |                 |                  |
      |----------------->|                 |                 |                 |                  |
      | validate and normalize             |                 |                 |                  |
      |<-----------------|                 |                 |                 |                  |
      | commit complete message            |                 |                 |                  |
      |----------------------------------->|                 |                 |                  |
      | publish persistent message          |                 |                 |                  |
      |----------------------------------------------------->|                 |                  |
      | publisher confirmation              |                 |                 |                  |
      |<-----------------------------------------------------|                 |                  |
      | mark outbox row published           |                 | deliver         |                  |
      |----------------------------------->|                 |---------------->| validate         |
      |                  |                 |                 |                 | transaction      |
      |                  |                 |                 |                 |----------------->|
      |                  |                 |                 |                 | commit           |
      |                  |                 |                 |                 |<-----------------|
      |                  |                 |                 | ACK             |                  |
      |                  |                 |                 |<----------------|                  |
```

The Provider blacklist worker is singleton-protected. Polling and publication
retry schedules are stored independently, so a broker outage does not require
another AbuseIPDB fetch and does not discard a completed snapshot.

## Infrastructure responsibilities

### MariaDB

MariaDB is the authoritative application database. Only History Service may
connect to it.

It stores:

- successful manual lookup records and their request IDs;
- complete blacklist snapshots and entries;
- provider and delivery metadata;
- synchronization status used by blacklist reads;
- analytics source data;
- Alembic schema version state.

Blacklist persistence is transactional: a snapshot and all of its entries
commit together or roll back together. A failed delivery does not replace or
delete the latest successful snapshot.

### RabbitMQ

RabbitMQ is the durable transport for completed blacklist snapshots. It is not
used for browser requests, manual lookup responses, UI sessions, or database
access.

The configurable topology defaults to:

| Element | Default |
| --- | --- |
| Main direct exchange | `aegis.blacklist` |
| Main routing key | `blacklist.snapshot.complete` |
| Main durable queue | `aegis.history.blacklist.snapshots` |
| Retry direct exchange | `aegis.blacklist.retry` |
| Retry queues | `aegis.history.blacklist.snapshots.retry.300`, `.retry.900`, `.retry.1800`, `.retry.3600` |
| Retry routing keys | `blacklist.snapshot.retry.300`, `.retry.900`, `.retry.1800`, `.retry.3600` |
| Dead-letter direct exchange | `aegis.blacklist.dead` |
| Dead-letter routing key | `blacklist.snapshot.dead` |
| Dead-letter queue | `aegis.history.blacklist.snapshots.dead` |

The History blacklist consumer declares the exchanges, queues, bindings, retry
TTL, and dead-letter return routing. The main, retry, and dead-letter queues are
durable. Provider messages and consumer-generated retry/DLQ messages use
persistent delivery mode.

Provider enables publisher confirms and marks an outbox message published only
after RabbitMQ returns a positive confirmation. The History consumer also uses
confirmed publication when handing a failed message to a retry queue or DLQ.

On the successful path, the consumer ACKs only after MariaDB commit. A duplicate
is ACKed only after History resolves it to an already committed snapshot. On a
processing failure, the original message is ACKed only after a persistent retry
or DLQ copy receives publisher confirmation. If that handoff cannot be
confirmed, the original is left unacknowledged so the broker can redeliver it.

### Provider SQLite outbox

The SQLite outbox is durable local state owned only by the Provider blacklist
worker. It is not shared application storage and is not queried by UI or
History.

Before the first RabbitMQ publication attempt, the worker stores:

- the versioned complete message;
- `delivery_id` and correlation metadata;
- creation and next-attempt timestamps;
- publication attempt state;
- polling schedule state.

SQLite uses write-ahead logging and full synchronous commits. Pending messages
survive worker restart and broker failure. A row is compacted only after a
positive RabbitMQ publisher confirmation. MariaDB remains the authoritative
store after consumption.

### Redis

Redis stores ephemeral UI state only. The implemented value is an anonymous
session's validated `light` or `dark` theme.

```text
Browser              UI API                  Redis
   |                    |                       |
   | cookie/session ID  |                       |
   |------------------->| GET theme:<session>   |
   |                    |---------------------->|
   |                    | theme or missing      |
   |                    |<----------------------|
   | rendered theme     | refresh inactivity TTL|
   |<-------------------|---------------------->|
   | POST light/dark    |                       |
   |------------------->| SET with TTL           |
   |                    |---------------------->|
   | 303 redirect and refreshed cookie          |
   |<-------------------|                       |
```

The browser cookie contains only a random UUID4 session ID. Redis values have an
inactivity TTL and contain no credentials, blacklist snapshots, analytics,
manual lookup records, or other authoritative business data. Redis loss cannot
corrupt MariaDB data.

## Snapshot delivery contract and idempotency

A blacklist message contains a versioned schema, message type, `delivery_id`,
correlation ID, producer, provider, creation timestamp, request metadata,
rate-limit metadata, and the complete normalized snapshot required for
persistence. Provider and History define separate boundary models.

Delivery is at least once:

- Provider assigns a stable UUID `delivery_id` before writing the outbox row.
- The same ID is used in the message body and AMQP `message_id`.
- History stores `delivery_id` under a unique database constraint.
- A first delivery commits one snapshot and its entries.
- A repeated delivery with an already committed `delivery_id` returns the
  existing snapshot with `created=false`.
- The accepted duplicate creates no second snapshot and is ACKed.
- Delivery identity is immutable and first-commit-wins: if the same
  `delivery_id` later carries different content, History still resolves it to
  the original committed snapshot.
- A concurrent duplicate that loses the unique-constraint race rolls back,
  reloads the winning row, and is handled as an accepted duplicate.

A different `delivery_id` for the same provider generation is a conflict rather
than an accepted duplicate.

## Failure behavior

### Manual lookup failures

- Invalid request data or a non-global IP is rejected by History before Provider
  is called.
- Provider unavailability, AbuseIPDB timeout, authentication failure, or invalid
  upstream data returns a safe application error.
- Failed lookups are not persisted.
- If MariaDB persistence fails after a provider success, History fails the
  request rather than returning an uncommitted result.

### AbuseIPDB unavailable

The Provider blacklist worker retains existing outbox messages and schedules a
bounded later polling attempt. No failed fetch is sent to RabbitMQ, and no
MariaDB snapshot is replaced or deleted.

### Rate limiting

Provider owns rate-limit behavior. It extracts supported limit, remaining,
reset, and `Retry-After` metadata. The worker honors `Retry-After`, waits for a
known reset when quota is empty, applies bounded delays, and avoids continuous
retry. The next polling decision is retained in SQLite.

### RabbitMQ unavailable

The completed message remains in the SQLite outbox. Publication is rescheduled
with bounded backoff, independently of the next AbuseIPDB polling time. Worker
restart reopens the outbox and resumes pending publication.

### Publish confirmation failure

A timeout, negative acknowledgement, returned/unroutable message, connection
failure, or other missing positive confirmation does not remove the outbox row.
The worker increments its attempt state and reschedules publication.

### Consumer database failure

History rolls back the MariaDB transaction. Operational and explicitly
retryable failures are copied to the next durable retry queue. The original
message is ACKed only if that copy is publisher-confirmed; otherwise it remains
unacknowledged.

### Retry exhaustion and DLQ

Temporary consumer failures use delayed retry tiers of 300, 900, 1800, and 3600
seconds. After those tiers are exhausted, the message is copied to the durable
dead-letter queue. Permanent validation or application failures go directly to
the DLQ. The original is ACKed only after confirmed DLQ publication. Malformed
messages therefore do not retry forever.

### Redis unavailable

Theme reads fall back to the default dark theme. Theme writes and deletes fail
softly after logging a safe warning; the page remains usable. UI readiness
reports not-ready when Redis `PING` fails. Redis failure does not affect
authoritative business data, though UI readiness also depends on History.

## Data ownership

| Owner | Data |
| --- | --- |
| UI Service | Templates, presentation models, anonymous session handling, and theme behavior |
| History Service | Application API models, idempotency, MariaDB schema and migrations, lookups, blacklist snapshots, entries, and analytics |
| Provider Service | AbuseIPDB models and normalization, polling decisions, versioned outbound message model, and local outbox |
| MariaDB | Authoritative persisted application records |
| RabbitMQ | In-flight durable snapshot deliveries, retries, and dead letters |
| Redis | Expiring anonymous UI theme values only |
| Provider SQLite outbox | Pending Provider publication and worker scheduling state |

Each service validates inputs at its own HTTP, AMQP, Redis, provider, or
database boundary. Raw AbuseIPDB responses and ORM models do not cross service
boundaries.

## Security boundaries and secrets

- Secrets are supplied through environment variables or protected runtime
  environment files; real values are not committed.
- Provider owns `ABUSEIPDB_API_KEY` and RabbitMQ publisher credentials.
- History owns MariaDB and RabbitMQ consumer credentials.
- UI owns History connection and Redis credentials.
- Provider never receives MariaDB or Redis credentials.
- UI never receives AbuseIPDB, MariaDB, or RabbitMQ credentials.
- History never receives the AbuseIPDB API key.
- RabbitMQ producer and consumer accounts should be separate and restricted to
  their required virtual-host permissions.
- Redis must be reachable only by UI and must contain no secrets or business
  records.
- MariaDB must be reachable only by History.
- AbuseIPDB URLs are configuration-owned, require HTTPS, and cannot be selected
  by request data.
- API keys, passwords, authorization headers, connection strings, complete
  blacklist payloads, SQL details, and raw upstream errors must not be logged.
- Public errors do not expose stack traces, credentials, internal URLs, or
  provider payloads.
- Default tests mock AbuseIPDB and do not require live credentials.

## Observability and health

Manual requests use a UUID request ID propagated through:

```text
UI Service -> History Service -> Provider Service
```

Blacklist logs include correlation and delivery IDs where relevant without
logging complete payloads.

Each API process exposes:

- `GET /health/live` for process liveness;
- `GET /health/ready` for its owned dependencies.

UI readiness checks History and Redis. History API readiness checks MariaDB.
Provider API readiness validates local configuration without consuming
AbuseIPDB quota. API health endpoints do not prove that the History blacklist
consumer or Provider blacklist worker is running; supervisors must check those
processes independently.

## Current deployment status

The implemented application architecture requires all five runtime processes,
MariaDB, RabbitMQ, Redis, and the Provider SQLite outbox.

The Vagrant deployment defines UI, History, Provider, database, and
infrastructure VMs. RabbitMQ runs natively on the infrastructure VM with a
dedicated `/aegis` virtual host, separate Provider and History accounts, and a
host-loopback-only management port. Broker data uses the package-managed
`/var/lib/rabbitmq` directory. The History blacklist consumer is deployed as a
separate systemd process and declares the messaging topology.

Redis also runs natively on the infrastructure VM and is reachable only from
UI through the private network firewall. It is not forwarded to the host.
Development uses no Redis password because the listener and UFW rules isolate
the only remote client to `ui-vm`; production should use a restricted ACL user.
Redis stores only TTL-bound theme values, uses periodic RDB snapshots without
AOF, and is bounded to 128 MB with `allkeys-lru` eviction. Losing Redis still
leaves UI pages available with the dark default theme. See the root
[README](../README.md) for quick-start and diagnostic commands.
