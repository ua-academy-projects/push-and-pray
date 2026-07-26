# AGENTS.md
## 1. Project Overview
Aegis is an educational multi-service IP reputation application.
It checks public IPv4/IPv6 addresses through AbuseIPDB, periodically retrieves
blacklist snapshots, persists business data in MariaDB, stores ephemeral UI
preferences in Redis, and uses RabbitMQ for asynchronous snapshot delivery.
Priorities: strict boundaries, explicit ownership, clear code, reliable tests,
minimal infrastructure, and incremental changes.
## 2. Architecture
Application services:
- `ui-service`;
- `history-service`;
- `provider-service`.
Infrastructure:
- MariaDB;
- Redis;
- RabbitMQ.
Each service must be independently runnable with its own dependencies,
configuration, tests, and boundary models. Do not create shared Python packages.
### Manual lookup
```text
Browser -> UI -> History -> Provider -> AbuseIPDB
```
Manual lookups remain synchronous.
### Blacklist synchronization
```text
Provider Worker -> AbuseIPDB -> SQLite Outbox
                -> RabbitMQ -> History Consumer -> MariaDB
```
Blacklist delivery is asynchronous. Provider must not deliver snapshots to
History through REST.
### Display and session flows
```text
Browser -> UI -> History -> MariaDB
Browser cookie -> UI -> Redis
```
UI reads only persisted business data. Redis stores only UI session state.
## 3. UI Service
UI renders FastAPI/Jinja2 pages and communicates only with History.
Responsibilities:
- render forms, tables, graphs, and errors;
- display persisted snapshots and analytics;
- create anonymous browser sessions;
- save and restore UI preferences in Redis.
Preferences may include graph period, filters, sorting, page size, auto-refresh,
and toggle or selector values.
Restrictions:
- no direct Provider or AbuseIPDB calls;
- no MariaDB access;
- no RabbitMQ publishing or consumption;
- no business-data caching in Redis;
- no authentication or user management unless approved.
## 4. History Service
History is the main backend and sole MariaDB owner.
Public API: `/api/v1/*`
Responsibilities:
- application API;
- manual lookup orchestration;
- public-IP validation and normalization;
- request idempotency;
- MariaDB persistence and Alembic migrations;
- RabbitMQ message consumption and validation;
- transactional blacklist persistence;
- blacklist query APIs and analytics;
- safe application errors.
History may run separate API and consumer processes. Message callbacks must call
services and repositories; do not place SQL directly in callbacks.
## 5. Provider Service
Provider is the internal AbuseIPDB adapter and blacklist fetcher.
Internal API: `/internal/v1/*`
Responsibilities:
- AbuseIPDB authentication;
- individual reputation and blacklist requests;
- upstream validation and normalization;
- rate-limit metadata extraction;
- provider error mapping;
- periodic blacklist polling;
- SQLite outbox persistence;
- RabbitMQ publishing.
Restrictions:
- no UI communication;
- no MariaDB or Redis access;
- no direct snapshot delivery to History through REST;
- no application lookup idempotency;
- no blacklist message consumption.
The manual lookup HTTP API remains available to History.
## 6. Infrastructure Ownership
### MariaDB
MariaDB is the authoritative persistent store. Only History may connect to it.
It stores manual lookup results, snapshots, entries, summary metadata, delivery
identifiers, and analytics source data.
### Redis
Redis is an ephemeral session store used only by UI.
Rules:
- session records have a TTL;
- session IDs are random and unguessable;
- cookies contain only the session ID;
- values contain no secrets or business records;
- different browser sessions have independent state;
- Redis must not cache AbuseIPDB, blacklist, analytics, or MariaDB data.
Redis loss must not corrupt persistent business data.
### RabbitMQ
Provider is the producer. History Consumer is the consumer.
Rules:
- durable queues and persistent messages;
- explicit acknowledgements;
- ACK only after successful MariaDB commit;
- failed transactions are not acknowledged;
- duplicate delivery must not create duplicate snapshots;
- malformed messages must not retry forever;
- use bounded retries and a dead-letter path where practical.
Do not use RabbitMQ for browser requests, UI sessions, manual lookup responses,
or database access.
## 7. Approved Stack
Python 3, FastAPI, HTTPX, Pydantic v2, SQLAlchemy 2.x, Alembic, MariaDB,
Redis, RabbitMQ, SQLite for Provider outbox, Jinja2, pytest, Ruff,
mypy/Pyright, and standard `pip`/`venv`.
Do not add infrastructure, frameworks, dependency managers, or shared packages
without approval.
## 8. Coding Rules
- Keep route handlers and message callbacks thin.
- Put logic in services, repositories, clients, and adapters.
- Use `APIRouter` and dependency injection.
- Use explicit Pydantic models for HTTP, RabbitMQ, Redis, and provider data.
- Never return ORM models directly.
- Never pass raw provider responses across service boundaries.
- Do not place SQL in handlers or callbacks.
- Do not block the async event loop with synchronous SQLAlchemy work.
- Each service validates its own boundary inputs.
## 9. IP and Provider Rules
Use Python `ipaddress`, never regex.
Accept global public IPv4/IPv6. Reject private, loopback, link-local, multicast,
unspecified, reserved, and other non-global addresses. Normalize to compressed
form.
Provider must use HTTPX timeouts, validate upstream JSON with Pydantic, return
normalized models, map errors safely, extract rate-limit metadata, and never log
API keys or expose raw upstream errors.
## 10. Manual Lookup
1. History validates IP and `request_id`.
2. History checks idempotency.
3. History calls Provider.
4. Provider calls AbuseIPDB.
5. Provider returns normalized data.
6. History persists success and returns it.
Do not persist failed lookups. If persistence fails, the request fails.
Idempotency:
- `request_id` is required;
- same ID and payload returns the existing result;
- same ID with different payload returns `409 IDEMPOTENCY_CONFLICT`.
Blacklist synchronization must not write to the legacy lookup table.
## 11. Blacklist Synchronization
Defaults:
- maximum entries: 1000;
- minimum confidence: 90;
- base interval: 21600 seconds;
- UI status polling: 30 seconds.
The standalone Provider worker is the only periodic polling owner. It must be
independent of API worker count, singleton-protected, disabled by default in
ordinary tests, and support clean shutdown.
Successful flow:
1. fetch and normalize the blacklist;
2. create a stable delivery ID;
3. commit the message to SQLite outbox;
4. publish to RabbitMQ;
5. receive publisher confirmation;
6. mark or remove the outbox record;
7. validate in History Consumer;
8. persist transactionally in MariaDB;
9. ACK only after commit.
Failures must not replace or delete the latest successful snapshot.
## 12. Message Contract
Blacklist messages use an explicit versioned schema containing at least:
- schema version and message type;
- delivery and correlation IDs;
- producer, provider, and creation timestamp;
- complete payload required for persistence.
Provider and History keep separate boundary models.
Delivery is at least once. History enforces idempotency through a unique delivery
ID. Duplicate messages are acknowledged without duplicate persistence. Unknown
schema versions must not be silently accepted.
## 13. Rate Limits and Retries
Provider owns AbuseIPDB polling and publishing retry decisions.
Extract when available:
- `X-RateLimit-Limit`;
- `X-RateLimit-Remaining`;
- `X-RateLimit-Reset`;
- `Retry-After`.
Use the configured interval after success, wait until reset when quota is empty,
honor `Retry-After`, use bounded retries, avoid continuous retries, add jitter,
retain outbox data, and do not retry permanent validation failures indefinitely.
## 14. Session Management
Every new browser session receives a random anonymous session ID.
The cookie stores only the ID. Redis stores validated UI preferences.
Required behavior:
- return defaults when no state exists;
- persist selector and toggle values;
- restore state after refresh;
- isolate different browser sessions;
- refresh TTL during activity;
- expire inactive sessions automatically.
Do not treat session IDs as identities or store credentials, API keys, or
business records in session data.
## 15. Configuration and Secrets
Use environment variables and safe `.env.example` files.
Ownership:
- Provider: AbuseIPDB and RabbitMQ publisher credentials;
- History: MariaDB and RabbitMQ consumer credentials;
- UI: History URL and Redis settings.
Use `SecretStr`. Never leak credentials in logs, errors, Alembic configuration,
health responses, RabbitMQ messages, or Redis values. Prefer separate RabbitMQ
producer and consumer users.
## 16. Errors, Logs, and Health
History returns safe JSON errors with code, message, and request ID.
Never expose stack traces, SQL details, connection strings, secrets, or raw
provider payloads.
Use structured stdout logs. Include request ID, correlation ID, delivery ID,
duration, status, service, and message type where relevant. Do not log complete
blacklist payloads.
Each application service provides `/health/live` and `/health/ready`.
Readiness checks must not consume AbuseIPDB quota.
Dependencies:
- UI: History and Redis;
- History API: MariaDB;
- History Consumer: MariaDB and RabbitMQ;
- Provider API: valid configuration;
- Provider Worker: outbox, RabbitMQ, and AbuseIPDB configuration.
## 17. Testing
All changes require relevant unit, endpoint, database, contract, and integration
tests. Default tests mock AbuseIPDB. Ordinary unit tests must not require live
Redis, RabbitMQ, or MariaDB unless marked as integration tests.
Blacklist tests cover success, complete persistence, duplicate delivery,
IPv4/IPv6, malformed data, timeout, HTTP 429, zero quota, bounded retry,
rollback, shutdown, outbox recovery, publish failure, confirmation, consumer
restart, DB failure, ACK after commit, malformed messages, and retention of the
latest successful snapshot.
Session tests cover cookie creation, defaults, persistence, refresh restoration,
independent sessions, TTL, invalid preferences, and Redis failure handling.
## 18. Verification and Agent Workflow
Run the repository's relevant equivalents of:
```text
ruff check .
ruff format --check .
pytest
mypy
alembic check
```
Review diffs for unrelated changes, leaked secrets, stale HTTP snapshot delivery,
direct MariaDB access outside History, business data in Redis, and missing tests.
Before editing:
1. Read this file.
2. Inspect relevant code and tests.
3. Identify affected boundaries.
4. Propose a short plan.
During implementation:
1. Make the smallest coherent change.
2. Preserve existing functionality.
3. Avoid full rewrites.
4. Add tests with each change.
5. Keep infrastructure adapters behind explicit interfaces.
6. Do not update unrelated documentation unless requested.
Ask for approval before changing service ownership, database engine, messaging
technology, authentication, secret management, public APIs, or message schema
compatibility strategy.
