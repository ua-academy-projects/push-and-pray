# Aegis contracts

This document describes the HTTP, RabbitMQ, and Redis boundaries. It separates
browser-facing UI routes, the History application API, the internal Provider
API, asynchronous snapshot messages, and UI-internal Redis keys. The direct
Provider's lifespan scheduler is the RabbitMQ publication owner.

Unless stated otherwise:

- JSON is UTF-8;
- JSON timestamps are timezone-aware ISO 8601 values normalized to UTC;
- service boundary models reject unknown fields;
- examples contain sanitized identifiers and public IP addresses;
- `X-Request-ID`, when accepted, is a UUID.

## Boundary summary

```text
Browser -> UI Service -> History Service -> Provider Service -> AbuseIPDB

Provider lifespan scheduler
  -> RabbitMQ
  -> History lifespan consumer
  -> MariaDB

Browser cookie -> UI Service -> Redis
```

There is no HTTP endpoint for Provider to push blacklist snapshots to History.
Completed snapshots cross that boundary only through RabbitMQ.

## Browser-facing UI routes

These routes are exposed by UI Service. They are not the History application
API.

| Method | Path | Request | Response |
| --- | --- | --- | --- |
| `GET` | `/` | — | Server-rendered lookup page and recent history |
| `POST` | `/` | Form fields `ip_address`, `max_age_days` | Server-rendered result or safe error |
| `GET` | `/blacklist` | `page`; `graph_mode` (`time` or `requests`); `range_days`; `request_limit` (`5`, `10`, `20`, `50`, `100`) | Persisted blacklist page and analytics |
| `GET` | `/blacklist/status` | — | Minimal same-origin polling JSON |
| `GET` | `/theme` | Optional anonymous session cookie | Current theme JSON |
| `POST` | `/theme` | Form field `theme` | `303` redirect after a valid submission |
| `GET` | `/health/live` | — | UI liveness |
| `GET` | `/health/ready` | — | UI dependency readiness |
| `GET` | `/static/style.css` | — | Base stylesheet |
| `GET` | `/static/blacklist.css` | — | Blacklist stylesheet |
| `GET` | `/static/blacklist.js` | — | Blacklist polling script |

### Lookup form

```http
POST /
Content-Type: application/x-www-form-urlencoded

ip_address=8.8.8.8&max_age_days=30
```

`max_age_days` must parse as an integer from 1 through 365. UI forwards a
validated request to `POST /api/v1/checks` and renders HTML. The UI response is
not the JSON History contract.

### Same-origin blacklist status

```http
GET /blacklist/status
```

Success:

```json
{
  "state": "ready",
  "latest_snapshot_id": 42,
  "data_stale": false
}
```

`state` is one of `empty`, `ready`, `syncing`, `stale`, or `degraded`.
`latest_snapshot_id` may be `null`. If History is unavailable, UI returns
`503`:

```json
{
  "error": "Blacklist status is temporarily unavailable."
}
```

This route polls persisted state only. It does not trigger Provider or
AbuseIPDB.

### Theme routes

```http
GET /theme
```

```json
{
  "theme": "dark"
}
```

`GET /theme` creates or refreshes the configured anonymous session cookie and
returns `light` or `dark`.

```http
POST /theme
Content-Type: application/x-www-form-urlencoded
Referer: /blacklist

theme=light
```

A valid value is saved best-effort and returns `303` to a safe same-origin
`Referer`, or `/` when the referer is absent or unsafe. Any value other than
`light` or `dark` returns `400`.

The cookie:

- defaults to the name `theme_session`;
- contains only a randomly generated UUID4;
- is `HttpOnly` and `SameSite=Lax`;
- is `Secure` for HTTPS requests or when configured;
- uses the Redis theme TTL as `Max-Age`.

### UI health

```http
GET /health/live
```

```json
{"status": "ok"}
```

`GET /health/ready` calls History readiness and Redis `PING`. It returns:

```json
{"status": "ready"}
```

or HTTP `503`:

```json
{"status": "not ready"}
```

UI responses include `X-Request-ID`. UI reuses a valid incoming UUID or
generates a UUID when the header is absent or invalid.

## History application API

History Service owns the application API under `/api/v1/*`. UI Service is its
application client. Provider Service does not expose these routes.

History accepts a valid optional `X-Request-ID` and generates one when absent.
An invalid header returns `400 INVALID_REQUEST_ID`. Every response includes the
effective `X-Request-ID`.

Application errors use:

```json
{
  "error": {
    "code": "INVALID_REQUEST",
    "message": "The request did not satisfy the API contract.",
    "request_id": "f3e495d2-5db3-4cf2-88fd-ae72f68384e1"
  }
}
```

### Manual reputation checks

#### Create a check

```http
POST /api/v1/checks
Content-Type: application/json
X-Request-ID: f3e495d2-5db3-4cf2-88fd-ae72f68384e1
```

```json
{
  "ip_address": "8.8.8.8",
  "max_age_days": 30
}
```

Fields:

| Field | Rules |
| --- | --- |
| `ip_address` | String, 1–100 characters; History normalizes it and requires a global public IPv4 or IPv6 address |
| `max_age_days` | Integer, 1–365; default `30` |

A newly persisted check returns `201`; an idempotent replay returns `200`.

```json
{
  "request_id": "f3e495d2-5db3-4cf2-88fd-ae72f68384e1",
  "history_id": 145,
  "ip_address": "8.8.8.8",
  "ip_version": 4,
  "is_public": true,
  "is_whitelisted": null,
  "abuse_confidence_score": 0,
  "country_code": "US",
  "usage_type": "Data Center/Web Hosting/Transit",
  "isp": "Example Network",
  "domain": "example.net",
  "total_reports": 0,
  "num_distinct_users": 0,
  "last_reported_at": null,
  "max_age_days": 30,
  "source": "AbuseIPDB",
  "checked_at": "2026-07-22T12:00:02Z"
}
```

The request ID is also the manual lookup idempotency key:

- same UUID and equivalent normalized payload: return the existing record with
  `200`, without another provider call or row;
- same UUID and different relevant payload: return
  `409 IDEMPOTENCY_CONFLICT`.

Failed provider calls and failed persistence are not reported as successful
checks.

#### List checks

```http
GET /api/v1/checks?limit=20&offset=0&ip_address=8.8.8.8
```

- `limit`: 1–100, default `20`;
- `offset`: non-negative, default `0`;
- optional `ip_address`: valid IP, normalized before filtering.

Response:

```json
{
  "items": [],
  "limit": 20,
  "offset": 0,
  "total": 0
}
```

Items use the same persisted record shape as the create response.

#### Get one check

```http
GET /api/v1/checks/145
```

`history_id` must be positive. Success returns one persisted record. A missing
record returns `404 HISTORY_RECORD_NOT_FOUND`.

### Blacklist read API

All blacklist endpoints read MariaDB. None calls Provider Service, publishes a
message, or triggers synchronization.

| Method | Path | Query |
| --- | --- | --- |
| `GET` | `/api/v1/blacklist/status` | — |
| `GET` | `/api/v1/blacklist` | `limit`, `offset`, optional `ip_version`, `minimum_score`, `country_code` |
| `GET` | `/api/v1/blacklist/snapshots` | `limit`, `offset` |
| `GET` | `/api/v1/blacklist/snapshots/{snapshot_id}` | `limit`, `offset` |
| `GET` | `/api/v1/blacklist/analytics` | `pair_limit` |
| `GET` | `/api/v1/blacklist/analytics/turnover` | `from`, `to`, `interval` |
| `GET` | `/api/v1/blacklist/analytics/requests` | `limit` (`5`, `10`, `20`, `50`, or `100`; default `10`) |

#### Status

```json
{
  "polling_owner": "provider",
  "state": "ready",
  "sync_in_progress": false,
  "latest_snapshot_id": 42,
  "latest_provider_generated_at": "2026-07-22T12:00:00Z",
  "latest_fetched_at": "2026-07-22T12:00:02Z",
  "last_attempt_at": "2026-07-22T12:00:02Z",
  "last_success_at": "2026-07-22T12:00:02Z",
  "next_attempt_at": null,
  "rate_limit_limit": 5,
  "rate_limit_remaining": 4,
  "rate_limit_reset_at": "2026-07-23T00:00:00Z",
  "data_stale": false,
  "last_error": null
}
```

Nullable timestamp, identifier, rate-limit, and error fields are `null` when
unavailable. `last_error`, when present, contains only `code` and `message`.

#### Latest or selected snapshot page

Latest snapshot:

```http
GET /api/v1/blacklist?limit=100&offset=0&ip_version=4&minimum_score=90&country_code=US
```

Selected snapshot:

```http
GET /api/v1/blacklist/snapshots/42?limit=100&offset=0
```

Rules:

- `limit`: 1–100, default `100`;
- `offset`: non-negative, default `0`;
- latest-only `ip_version`: `4` or `6`;
- latest-only `minimum_score`: 0–100;
- latest-only `country_code`: exactly two uppercase letters.

```json
{
  "snapshot": {
    "snapshot_id": 42,
    "provider": "AbuseIPDB",
    "provider_generated_at": "2026-07-22T12:00:00Z",
    "fetched_at": "2026-07-22T12:00:02Z",
    "confidence_minimum": 90,
    "requested_limit": 1000,
    "returned_count": 1
  },
  "items": [
    {
      "ip_address": "8.8.8.8",
      "ip_version": 4,
      "abuse_confidence_score": 90,
      "country_code": "US",
      "last_reported_at": "2026-07-22T11:47:00Z"
    }
  ],
  "limit": 100,
  "offset": 0,
  "total": 1
}
```

A missing latest or selected snapshot returns
`404 BLACKLIST_SNAPSHOT_NOT_FOUND`.

#### Snapshot list

```http
GET /api/v1/blacklist/snapshots?limit=20&offset=0
```

`limit` is 1–100 with default `20`; `offset` is non-negative with default `0`.
The response contains `items`, `limit`, `offset`, and `total`. Each item uses the
seven-field `snapshot` summary shown above.

#### Analytics

```http
GET /api/v1/blacklist/analytics?pair_limit=10
```

`pair_limit` is 1–30 with default `10`. The response contains:

- `latest_snapshot`: nullable summary with `snapshot_id`,
  `provider_generated_at`, `confidence_minimum`, `requested_limit`,
  `returned_count`, and `result_limit_reached`;
- `score_distribution`: `minimum`, `maximum`, and `count` buckets;
- `top_countries`: `items`, `unknown_count`, and `other_count`;
- `ip_versions`: `ip_version` and `count`;
- `snapshot_churn`: current/previous snapshot IDs and `added`, `removed`,
  `retained` counts.

With no snapshot:

```json
{
  "latest_snapshot": null,
  "score_distribution": [],
  "top_countries": {
    "items": [],
    "unknown_count": 0,
    "other_count": 0
  },
  "ip_versions": [],
  "snapshot_churn": []
}
```

#### Turnover

```http
GET /api/v1/blacklist/analytics/turnover?from=2026-07-22T00:00:00Z&to=2026-07-23T00:00:00Z&interval=auto
```

- `from` and `to` are optional but must be supplied together as aware
  timestamps;
- omitting the range, or sending `period=all`, selects all available stored
  snapshot history;
- `to` must be later than `from`;
- `interval` is `auto`, `hour`, `day`, `week`, or `month`;
- automatic granularity is hourly through 48 hours, daily through 31 days,
  weekly through 180 days, and monthly beyond 180 days;
- at most 366 interval points may be requested.

All timestamps and bucket boundaries are UTC. Weeks begin Monday at
`00:00:00Z`; months begin on their first calendar day at `00:00:00Z`.
MariaDB selects the latest snapshot in each bucket with deterministic
timestamp and snapshot-ID ordering. Missing buckets remain present with null
metrics because absence of a snapshot is not evidence of zero turnover.

```json
{
  "from": "2026-07-22T00:00:00Z",
  "to": "2026-07-23T00:00:00Z",
  "interval": "hour",
  "requested_period": "custom",
  "effective_start": "2026-07-22T03:15:00Z",
  "effective_end": "2026-07-22T22:10:00Z",
  "granularity": "hour",
  "bucket_count": 24,
  "points": [
    {
      "period_start": "2026-07-22T00:00:00Z",
      "turnover_percent": 10.0,
      "added_count": 10,
      "removed_count": 5,
      "snapshot_id": 42
    }
  ]
}
```

Point metrics and `snapshot_id` may be `null`.

#### Request-count series

`GET /api/v1/blacklist/analytics/requests?limit=20` returns the requested
number of latest successfully persisted delivered snapshots, ordered from
oldest to newest for charting. One point represents one request; `new_ips` is
the number added relative to its persisted baseline (or all IPs for the first
available baseline).

```json
{
  "limit": 20,
  "points": [{
    "request_id": "018f6a42-44c2-7f57-8c78-6dcb40b3912a",
    "created_at": "2026-07-22T12:00:02Z",
    "total_ips": 1000,
    "new_ips": 37
  }]
}
```

### History health

```http
GET /health/live
```

```json
{"status": "ok"}
```

`GET /health/ready` runs a minimal MariaDB query and verifies that the
configured RabbitMQ consumer task is registered and running. It returns:

```json
{"status": "ready"}
```

or HTTP `503`:

```json
{"status": "not ready"}
```

It does not call Provider or AbuseIPDB.

## Internal Provider API

Provider Service exposes these routes for History Service. UI and browsers must
not call them.

Provider accepts an optional valid `X-Request-ID`, generates one when absent,
and rejects an invalid value with `400 INVALID_REQUEST_ID`. It returns the
effective ID in `X-Request-ID` and safe error envelopes.

### Normalized reputation check

```http
POST /internal/v1/reputation-checks
Content-Type: application/json
X-Request-ID: f3e495d2-5db3-4cf2-88fd-ae72f68384e1
```

```json
{
  "ip_address": "2001:4860:4860::8888",
  "max_age_days": 30
}
```

`ip_address` must already be canonical and globally public.
`max_age_days` is a required strict integer from 1 through 365. The response is
the normalized reputation result shown in the History create response without
`request_id` or `history_id`.

Provider does not persist the result or implement request idempotency.

### Normalized blacklist fetch

```http
GET /internal/v1/blacklist?confidence_minimum=90&limit=1000
X-Request-ID: f3e495d2-5db3-4cf2-88fd-ae72f68384e1
```

- `confidence_minimum`: 0–100, default `90`;
- `limit`: 1–1000, default `1000`.

```json
{
  "provider": "AbuseIPDB",
  "generated_at": "2026-07-22T12:00:00.123456Z",
  "fetched_at": "2026-07-22T12:00:02.654321Z",
  "request": {
    "confidence_minimum": 90,
    "limit": 1000
  },
  "rate_limit": {
    "limit": 5,
    "remaining": 4,
    "reset_at": "2026-07-23T00:00:00Z",
    "retry_after_seconds": null
  },
  "items": [
    {
      "ip_address": "8.8.8.8",
      "ip_version": 4,
      "abuse_confidence_score": 90,
      "country_code": "US",
      "last_reported_at": "2026-07-22T11:47:00Z"
    }
  ]
}
```

Rules:

- `provider` is exactly `AbuseIPDB`;
- `generated_at` is AbuseIPDB's aware snapshot-generation timestamp;
- `fetched_at` is Provider's local completion timestamp;
- `request` echoes the effective confidence minimum and limit;
- nullable rate-limit values represent absent or unusable headers;
- `items` has at most 1000 entries and never exceeds `request.limit`;
- addresses are canonical global IPv4 or IPv6 values;
- `ip_version` must match the address;
- scores are 0–100;
- country codes are uppercase two-character strings or `null`;
- `last_reported_at` is aware or `null`;
- duplicate normalized addresses invalidate the upstream response.

Unknown AbuseIPDB fields may be ignored by the upstream adapter. The normalized
internal response rejects unknown fields.

### Provider errors

Provider errors use:

```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "The provider rate limit has been reached.",
    "request_id": "f3e495d2-5db3-4cf2-88fd-ae72f68384e1",
    "retry": {
      "retry_after_seconds": 3600,
      "reset_at": "2026-07-23T00:00:00Z"
    }
  }
}
```

`retry` is optional. Implemented error codes include:

| Status | Code |
| ---: | --- |
| 400 | `INVALID_REQUEST_ID` |
| 422 | `INVALID_REQUEST` |
| 429 | `RATE_LIMIT_EXCEEDED` |
| 500 | `INTERNAL_SERVER_ERROR` |
| 502 | `UPSTREAM_INVALID_RESPONSE` |
| 502 | `UPSTREAM_REQUEST_REJECTED` |
| 503 | `UPSTREAM_AUTHENTICATION_FAILED` |
| 503 | `UPSTREAM_UNAVAILABLE` |
| 504 | `UPSTREAM_TIMEOUT` |

### Provider health

```http
GET /health/live
```

```json
{
  "status": "ok",
  "blacklist_polling_owner": "provider"
}
```

```http
GET /health/ready
```

```json
{
  "status": "ready",
  "blacklist_polling_owner": "provider",
  "blacklist_polling_enabled": false
}
```

These endpoints do not call AbuseIPDB. Readiness returns `503` when the enabled
scheduler task has terminated; liveness only confirms the HTTP process.

## RabbitMQ blacklist snapshot contract

This is the only Provider-to-History snapshot delivery contract. Provider keeps
its own message model and History validates the same wire shape with a separate
boundary model.

### Topology

Names are configurable. Current defaults are:

| Element | Type and durability | Default |
| --- | --- | --- |
| Main exchange | Direct, durable | `aegis.blacklist` |
| Main routing key | — | `blacklist.snapshot.complete` |
| Main queue | Durable | `aegis.history.blacklist.snapshots` |
| Retry exchange | Direct, durable | `aegis.blacklist.retry` |
| Retry queue, 300 seconds | Durable, TTL 300 seconds | `aegis.history.blacklist.snapshots.retry.300` |
| Retry queue, 900 seconds | Durable, TTL 900 seconds | `aegis.history.blacklist.snapshots.retry.900` |
| Retry queue, 1800 seconds | Durable, TTL 1800 seconds | `aegis.history.blacklist.snapshots.retry.1800` |
| Retry queue, 3600 seconds | Durable, TTL 3600 seconds | `aegis.history.blacklist.snapshots.retry.3600` |
| Dead-letter exchange | Direct, durable | `aegis.blacklist.dead` |
| Dead-letter routing key | — | `blacklist.snapshot.dead` |
| Dead-letter queue | Durable | `aegis.history.blacklist.snapshots.dead` |

Retry routing keys are `blacklist.snapshot.retry.<delay>`. Each retry queue
dead-letters expired messages back to the main exchange with routing key
`blacklist.snapshot.complete`.

### AMQP envelope

Provider publishes with publisher confirms, mandatory routing, and these
properties:

| Property or header | Published value | Consumer rule |
| --- | --- | --- |
| Body | UTF-8 JSON | Must validate as the versioned message |
| `content_type` | `application/json` | If present, must equal `application/json` |
| `content_encoding` | `utf-8` | If present, case-insensitively equals `utf-8` |
| `delivery_mode` | Persistent (`2`) | Required to be persistent |
| `message_id` | String form of body `delivery_id` | If present, must be a matching UUID |
| `correlation_id` | String form of body `correlation_id` | If present, must be a matching UUID |
| `timestamp` | Body `created_at` | If present, must be aware and match `created_at` to whole-second precision |
| `type` | `blacklist.snapshot.complete` | If present, must match body `message_type` |
| `app_id` | `aegis-provider-service` | If present, must match body `producer` |
| `x-aegis-retry-attempt` | Absent on initial publish; positive integer on retry | Defaults to `0`; must be a non-negative integer and not a boolean |

Provider currently supplies every property listed above except the retry header
on an initial message. History retains compatibility with omitted optional AMQP
metadata by validating it when present. Persistent delivery mode and the JSON
body contract are mandatory.

Consumer retry and DLQ copies preserve the body and metadata, use persistent
delivery mode, and require publisher confirmation before the original message
is ACKed.

### JSON message

```json
{
  "schema_version": 1,
  "message_type": "blacklist.snapshot.complete",
  "delivery_id": "06a22d6d-d8cc-49b7-b1b5-6d92b0929c3f",
  "correlation_id": "06a22d6d-d8cc-49b7-b1b5-6d92b0929c3f",
  "producer": "aegis-provider-service",
  "provider": "AbuseIPDB",
  "created_at": "2026-07-22T12:00:02.777777Z",
  "snapshot": {
    "provider": "AbuseIPDB",
    "generated_at": "2026-07-22T12:00:00.123456Z",
    "fetched_at": "2026-07-22T12:00:02.654321Z",
    "request": {
      "confidence_minimum": 90,
      "limit": 1000
    },
    "rate_limit": {
      "limit": 5,
      "remaining": 4,
      "reset_at": "2026-07-23T00:00:00Z",
      "retry_after_seconds": null
    },
    "items": [
      {
        "ip_address": "8.8.8.8",
        "ip_version": 4,
        "abuse_confidence_score": 90,
        "country_code": "US",
        "last_reported_at": "2026-07-22T11:47:00Z"
      }
    ]
  }
}
```

All fields shown are required except the nullable values themselves.
`schema_version` is exactly `1`; unknown versions are terminal validation
failures. Unknown JSON fields are rejected.

### Timestamp semantics and precision

- `snapshot.generated_at` becomes History's `provider_generated_at`. It is the
  provider's generation time, not receipt or publication time.
- `provider` plus `provider_generated_at` identifies one provider generation
  and is unique in MariaDB.
- Provider preserves an aware upstream timestamp and JSON may carry fractional
  seconds. MariaDB snapshot timestamp columns support microsecond precision.
- `snapshot.fetched_at` is the local Provider completion time.
- `created_at` is message creation time.
- AMQP `timestamp` represents `created_at`, not `provider_generated_at`.
  AMQP timestamps have whole-second interoperability semantics, so History
  compares it to `created_at` after dropping microseconds.
- Entry `last_reported_at` and rate-limit `reset_at` may be `null`.

### Request configuration and entries

`snapshot.request` is required:

- `confidence_minimum`: strict integer from 0 through 100;
- `limit`: strict integer from 1 through 1000.

`snapshot.items` is a complete list for that request, bounded by both 1000 and
`request.limit`. Each entry requires:

- `ip_address`: canonical global public IPv4 or IPv6 string;
- `ip_version`: `4` or `6`, matching the address;
- `abuse_confidence_score`: strict integer from 0 through 100;
- `country_code`: uppercase two-character string or `null`;
- `last_reported_at`: aware timestamp or `null`.

### Delivery identity and duplicates

- Provider assigns a stable UUID `delivery_id` before its first publication
  attempt and retains that identity for retries of the same in-memory message.
- Provider publishes with persistent delivery, mandatory routing, and publisher
  confirms. RabbitMQ is the first durable handoff after positive confirmation.
- History persists `delivery_id` under a unique constraint.
- First delivery commits the snapshot and all entries in one MariaDB
  transaction.
- A repeated committed `delivery_id` returns the existing snapshot with
  `created=false`, creates no rows, and is ACKed.
- Delivery identity is first-commit-wins. If a later message reuses the
  `delivery_id` with different content, History still resolves it to the first
  committed snapshot and ACKs it as an accepted duplicate.
- Concurrent duplicates that race on the unique constraint reload and accept
  the winning committed row.
- A different `delivery_id` for the same `provider` and
  `provider_generated_at` is a terminal snapshot conflict.

After RabbitMQ confirms publication, consumer delivery is at least once. An
accepted duplicate is therefore a successful, expected outcome. Before that
confirmation, loss of the Provider process or VM can lose its
in-memory fetched message.

### Acknowledgement and failures

On successful new persistence, History ACKs only after MariaDB commit. An
accepted duplicate is ACKed after resolving the already committed row.

Retryable processing failures are:

- `HistoryUnavailableError`;
- SQLAlchemy `OperationalError`;
- explicitly raised `RetryableBlacklistProcessingError`.

They are copied, with publisher confirmation, through delayed tiers of 300,
900, 1800, and 3600 seconds. After those tiers, the message goes to the DLQ.

Terminal failures include:

- malformed JSON or schema validation;
- invalid content metadata, properties, or retry header;
- unknown schema version or message type;
- permanent application errors, including provider-generation conflicts;
- unexpected consumer exceptions.

Terminal failures go directly to the DLQ. The original is ACKed only after the
retry or DLQ copy receives a positive publisher confirmation. If republishing
cannot be confirmed, the original remains unacknowledged for broker
redelivery.

## Redis theme-state contract

This is an internal UI storage convention, not a public HTTP API or a
service-to-service contract.

| Item | Contract |
| --- | --- |
| Redis database | Configured by `REDIS_DB`, default `0` |
| Key prefix | Configured by `REDIS_THEME_PREFIX`, default `theme`; surrounding colons are stripped |
| Key | `<prefix>:<canonical UUID4 session ID>` |
| Value | Exactly `light` or `dark` |
| TTL | `REDIS_THEME_TTL_SECONDS`, default `2592000` seconds, minimum `60` |
| Cookie | Configured name, default `theme_session`; contains only the UUID4 |

Example:

```text
key:   theme:4ecbe4a8-fd1f-4b4b-a812-e3526136a7aa
value: dark
TTL:   2592000 seconds
```

Behavior:

- a missing or invalid cookie causes UI to generate a new UUID4;
- a missing Redis key returns the default `dark` theme;
- a valid read refreshes the Redis inactivity TTL;
- a write uses `SET` with the full TTL;
- invalid stored data falls back to `dark`;
- Redis read failure falls back to `dark`;
- Redis write and delete failures are logged safely and otherwise fail softly;
- Redis `PING` failure makes UI readiness return `503`;
- cookie activity refreshes its `Max-Age`;
- Redis contains no credentials, blacklist snapshots, analytics, manual lookup
  records, or authoritative business data.

## Compatibility

- HTTP routes are versioned where they cross application or service boundaries.
- RabbitMQ messages use an explicit `schema_version`.
- Provider and History own separate models for the same AMQP wire shape.
- Breaking HTTP or message changes require an explicit compatibility strategy.
- Raw AbuseIPDB responses never cross the Provider boundary.
- Blacklist snapshot delivery has no HTTP fallback.
