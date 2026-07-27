# Provider Service

The Provider is an internal AbuseIPDB proxy. It accepts normalized lookup
requests from History Service, validates and normalizes AbuseIPDB responses,
and returns a provider-independent internal result. A separate Provider worker
owns periodic blacklist polling and keeps pending History deliveries in a
small local SQLite outbox. Provider never accesses MariaDB or UI.

## Configuration

Create the service-local file from the repository root:

```bash
cp services/provider-service/.env.example services/provider-service/.env
```

Provider loads that file explicitly regardless of the current working directory:

```dotenv
ABUSEIPDB_BASE_URL=https://api.abuseipdb.com
ABUSEIPDB_API_KEY=replace-me
ABUSEIPDB_CONNECT_TIMEOUT_SECONDS=5
ABUSEIPDB_READ_TIMEOUT_SECONDS=10
ABUSEIPDB_WRITE_TIMEOUT_SECONDS=5
ABUSEIPDB_POOL_TIMEOUT_SECONDS=5
ABUSEIPDB_OPERATION_TIMEOUT_SECONDS=20
BLACKLIST_POLLING_ENABLED=false
BLACKLIST_OUTBOX_PATH=var/provider-blacklist-outbox.sqlite3
RABBITMQ_HOST=127.0.0.1
RABBITMQ_PORT=5672
RABBITMQ_VIRTUAL_HOST=/
RABBITMQ_USERNAME=aegis_provider
RABBITMQ_PASSWORD=replace-me
RABBITMQ_EXCHANGE_NAME=aegis.blacklist
RABBITMQ_ROUTING_KEY=blacklist.snapshot.complete
```

`ABUSEIPDB_API_KEY` is required and is read from the service-local environment
file or an exported environment variable at application startup. Never commit or
log a real key. The base URL is fixed in configuration, must use HTTPS, and
cannot be controlled by request data.

Install the locked workspace and run from the repository root:

```bash
uv sync --locked --all-packages --all-extras
.venv/bin/uvicorn provider_service.main:app \
  --app-dir services/provider-service/src \
  --host 127.0.0.1 \
  --port 8001
```

Provider maintains one lifecycle-owned HTTPX client for AbuseIPDB. It is reused
across requests and closed during shutdown.

Run exactly one standalone polling worker when periodic synchronization is
enabled:

```bash
.venv/bin/aegis-provider-blacklist-worker
```

The API and worker are independent processes. The worker calls AbuseIPDB,
commits every successful fetch to its SQLite outbox, and publishes the complete
message to RabbitMQ with persistent delivery and publisher confirmation.
Polling and publication retries have separate clocks, so a broker outage does
not discard a fetched snapshot.
Production must place `BLACKLIST_OUTBOX_PATH` on durable storage writable only
by the Provider service account.

`POST /internal/v1/reputation-checks` is the internal provider-proxy boundary
for History Service. It accepts only a canonical public `ip_address` and a
`max_age_days` value from 1 through 365, calls the configured AbuseIPDB
endpoint, and returns a validated normalized result. It forwards no request to
History Service and performs no persistence or idempotency work. A valid
`X-Request-ID` is returned in the response header and in safe error envelopes.

`GET /internal/v1/blacklist` returns one complete normalized AbuseIPDB snapshot.
It accepts `confidence_minimum` from 0 through 100 (default 90) and `limit` from
1 through 1000 (default 1000). Duplicate normalized IP addresses invalidate the
snapshot with `UPSTREAM_INVALID_RESPONSE`; results are never persisted.
Provider Service extracts supported rate-limit and `Retry-After` metadata for
API consumers. The standalone worker uses the same parsing and normalization
abstractions when deciding its next poll.

`GET /health/live` and `GET /health/ready` are quota-free API-process checks.
Their payload identifies Provider as the polling owner and readiness reports
whether polling is configured, but neither endpoint proves the separate worker
is running. In a systemd deployment, check it independently:

```bash
systemctl is-active aegis-provider-blacklist-worker.service
journalctl -u aegis-provider-blacklist-worker.service -n 100 --no-pager
```

Tests replace the reputation provider or use HTTPX mock transports. The default
suite makes no live AbuseIPDB calls:

```bash
.venv/bin/pytest services/provider-service/tests
```
