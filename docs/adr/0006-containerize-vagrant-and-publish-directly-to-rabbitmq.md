# 0006 — Containerize Vagrant and publish directly to RabbitMQ

## Status

**Accepted**

## Context

Aegis has three logical application services and five application runtimes:
UI Service, History API, History Consumer, Provider API, and Provider Worker.
The former Vagrant deployment ran application processes directly on VM hosts,
placed MariaDB on a separate database VM, and used a Provider-local durable
staging store before RabbitMQ publication.

The next deployment phase requires every application runtime to run inside a
container. MariaDB, RabbitMQ, and Redis must share one infrastructure VM.
Logical ownership and asynchronous message delivery must remain unchanged.

## Decision

Use four Vagrant VMs:

| VM | Containers |
| --- | --- |
| `ui-vm` | UI Service |
| `history-vm` | History API; History Consumer |
| `provider-vm` | Provider API; Provider Worker |
| `infra-vm` | MariaDB; RabbitMQ with management plugin; Redis |

Each runtime has its own container and process lifecycle. The API and background
runtime of one logical service may share an image but not a container.
Application Python processes do not execute directly on VM hosts.

History remains the sole logical owner of MariaDB data even though the MariaDB
container runs on `infra-vm`. Only History runtimes receive MariaDB credentials
and network access.

Provider Worker polls AbuseIPDB, validates and normalizes a complete snapshot,
constructs a versioned message, and publishes it directly to RabbitMQ using:

- persistent delivery mode;
- mandatory routing;
- publisher confirms;
- a stable delivery identity during publication retry.

History Consumer receives the message, validates its History-owned boundary
model, and invokes History application-layer ingestion logic. It does not place
SQL in the RabbitMQ callback. It ACKs only after a successful MariaDB commit or
after resolving an already committed duplicate.

RabbitMQ remains the asynchronous transport. Provider does not deliver
blacklist snapshots to History through HTTP.

The target has no Provider-side durable staging database. RabbitMQ becomes the
first durable boundary after a positive publisher confirmation.

## Consequences

### Positive

- VM topology is reduced from five VMs to four without merging application
  service VMs.
- Every application runtime has a reproducible image and isolated container
  lifecycle.
- History API/Consumer and Provider API/Worker remain independently supervised.
- Infrastructure products share one VM while retaining separate containers,
  credentials, volumes, and health checks.
- History remains the sole MariaDB owner.
- RabbitMQ publisher confirms, durable queues, explicit acknowledgements,
  bounded consumer retries, and dead-letter handling remain in place.

### Negative and operational

- A fetched snapshot exists only in Provider Worker memory until RabbitMQ
  confirms publication.
- Provider Worker or VM failure before confirmation can lose that completed
  fetch.
- Publication retry state does not survive loss of the Worker container unless
  it has already reached RabbitMQ.
- Operations must not describe the pre-confirmation path as durable or
  end-to-end at least once.
- Infrastructure VM capacity and failure affect all three infrastructure
  products, so volumes, resource limits, health checks, backups, and recovery
  must be explicit.
- Compose stacks and VM firewall rules must preserve cross-VM service
  boundaries.

## Alternatives considered

### Keep the separate MariaDB VM

Rejected because the fixed topology requires MariaDB, RabbitMQ, and Redis on
`infra-vm`.

### Run application processes directly under host systemd

Rejected because every application runtime must execute in a container. Host
systemd may supervise a Compose project but may not run application entry
points.

### Combine API and background runtimes

Rejected. History API and History Consumer need independent lifecycles, as do
Provider API and Provider Worker.

### Combine application VMs

Rejected. `ui-vm`, `history-vm`, and `provider-vm` remain separate deployment
and network boundaries.

### Provider writes MariaDB

Rejected because it violates History's exclusive logical ownership and exposes
database credentials outside History.

### Direct HTTP snapshot delivery

Rejected because RabbitMQ remains the required asynchronous delivery transport.
HTTP remains appropriate only for synchronous manual lookups.

### Redis as the broker

Rejected because Redis is restricted to ephemeral UI state and does not replace
RabbitMQ's delivery, acknowledgement, retry, and dead-letter responsibilities.

## References

- [Target architecture](../architecture.md)
- [Target Vagrant deployment](../development-vagrant.md)
- [API and message contracts](../api-contracts.md)
