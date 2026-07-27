# 0005 — Use RabbitMQ and a Provider-side SQLite outbox for blacklist delivery

## Status

**Accepted**

The worker, outbox, publisher, message models, consumer, transactional
persistence, retries, dead-letter handling, and idempotency behavior are present
and verified by repository tests.

## Context

AbuseIPDB blacklist snapshots may contain up to 1000 normalized IPv4 and IPv6
entries. Fetching them is periodic work and must be independent of FastAPI
request handling and API worker count.

A completed fetch must not be lost when RabbitMQ, the History blacklist
consumer, or MariaDB is temporarily unavailable. Provider must also remain
isolated from application persistence: History Service is the sole MariaDB
owner.

The former direct HTTP push coupled Provider delivery to History API
availability. It did not provide a durable local handoff between a successful
AbuseIPDB fetch and delivery to History.

## Decision

Use a standalone Provider blacklist worker, a Provider-local SQLite outbox,
RabbitMQ, and a standalone History blacklist consumer.

The delivery sequence is:

1. Provider blacklist worker polls AbuseIPDB and validates a complete snapshot.
2. Provider assigns a stable `delivery_id` and commits the complete versioned
   message to its local SQLite outbox.
3. Provider publishes the message to a durable RabbitMQ exchange using a
   persistent delivery mode and mandatory routing.
4. RabbitMQ publisher confirms are required before Provider marks the outbox
   message as published and compacts its pending row.
5. History blacklist consumer validates the independent History boundary model
   and writes the snapshot and all entries to MariaDB in one transaction.
6. A newly accepted message is ACKed only after the MariaDB commit. An already
   committed duplicate is ACKed after History resolves the existing row.
7. Retryable processing failures use bounded durable retry queues. Permanent
   failures and exhausted retries use a durable dead-letter queue. The original
   message is ACKed after a publisher-confirmed retry or dead-letter handoff; if
   that handoff is not confirmed, it remains unacknowledged.

Delivery is at least once. History stores `delivery_id` under a unique
constraint and treats a repeated committed ID as an accepted duplicate without
creating another snapshot or entry rows. Delivery identity is
first-commit-wins.

Provider and History keep separate Pydantic models for the same versioned wire
contract. Provider is the RabbitMQ producer, History is the consumer, and only
History accesses MariaDB.

## Alternatives considered

### Direct HTTP push from Provider to History

Rejected. It couples delivery to History API availability and provides no
durable broker handoff. HTTP remains appropriate for synchronous manual
lookups, not completed blacklist snapshot delivery.

### Provider writes directly to MariaDB

Rejected. It violates History's exclusive database ownership, duplicates
persistence logic and credentials, and weakens service boundaries.

### In-process FastAPI background tasks

Rejected. Task ownership would vary with API worker count, process restarts
could lose work, and periodic polling would be coupled to HTTP process
lifecycle. The Provider blacklist worker and History blacklist consumer must be
separately supervised processes.

### Redis as the message broker

Rejected. Redis is owned by UI for ephemeral theme state. Reusing it for
authoritative snapshot delivery would mix infrastructure responsibilities and
would not use the RabbitMQ durability, acknowledgement, routing, retry, and
dead-letter semantics implemented for this flow.

### Publish without an outbox

Rejected. A worker or broker failure between a successful AbuseIPDB response
and confirmed publication could lose the completed snapshot. The SQLite outbox
makes the local commit the durable boundary before publication.

## Consequences

### Positive

- Completed snapshots survive temporary RabbitMQ and History outages.
- Provider remains independent of MariaDB and History remains its sole owner.
- Polling is independent of Provider API worker count and request traffic.
- Publisher confirms, persistent messages, explicit acknowledgements, bounded
  retries, and a DLQ make delivery failure behavior explicit.
- `delivery_id` makes at-least-once redelivery safe.
- The latest successful MariaDB snapshot remains available when later fetching
  or delivery fails.

### Negative and operational

- RabbitMQ adds infrastructure, credentials, monitoring, durable storage, and
  operational complexity.
- Provider blacklist worker and History blacklist consumer require separate
  process supervision and health checks from their APIs.
- The SQLite database and its WAL-related files require a private, writable,
  durable local directory, disk-space monitoring, backup or recovery policy
  appropriate to the environment, and cleanup of delivered-message metadata.
- A lost or corrupted outbox can lose messages that have not yet received a
  publisher confirmation.
- Retry queues and the DLQ require monitoring and an operational replay or
  disposal procedure.
- The RabbitMQ schema is a service boundary. It requires explicit versioning,
  compatibility decisions, and coordinated Provider and History changes.

## References

Implementation:

- [Provider blacklist worker](../../services/provider-service/src/provider_service/blacklist_worker.py)
- [Provider SQLite outbox](../../services/provider-service/src/provider_service/outbox.py)
- [Provider RabbitMQ publisher](../../services/provider-service/src/provider_service/rabbitmq_publisher.py)
- [Provider message models](../../services/provider-service/src/provider_service/schemas.py)
- [History blacklist consumer](../../services/history-service/src/history_service/blacklist_consumer.py)
- [History transactional ingestion](../../services/history-service/src/history_service/blacklist_ingestion.py)
- [History message models](../../services/history-service/src/history_service/schemas.py)

Tests:

- [Provider worker tests](../../services/provider-service/tests/test_blacklist_worker.py)
- [Provider outbox tests](../../services/provider-service/tests/test_outbox.py)
- [Provider publisher tests](../../services/provider-service/tests/test_rabbitmq_publisher.py)
- [Provider RabbitMQ contract tests](../../services/provider-service/tests/test_rabbitmq_contract.py)
- [History consumer tests](../../services/history-service/tests/test_blacklist_consumer.py)
- [History ingestion tests](../../services/history-service/tests/test_blacklist_ingestion.py)
- [History RabbitMQ contract tests](../../services/history-service/tests/test_rabbitmq_contract.py)
- [RabbitMQ integration tests](../../services/history-service/tests/test_rabbitmq_integration.py)
- [RabbitMQ-to-MariaDB integration tests](../../services/history-service/tests/test_rabbitmq_mariadb_integration.py)
