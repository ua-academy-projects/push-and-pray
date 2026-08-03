# Rateboard API

## History Service API used by UI

Base path: `/api/v1`.

### Health

```text
GET /health/live
GET /health/ready
```

Readiness requires PostgreSQL and the observation consumer.

### Catalog and overview

```text
GET /api/v1/instruments
GET /api/v1/overview
```

Overview returns the latest PostgreSQL observation for available crypto and fiat
instruments. It never calls a public provider.

### Current persisted observations

```text
GET /api/v1/rates/current?instruments=crypto:bitcoin:usd,fiat:USD:UAH
GET /api/v1/rates/stored-current?instruments=crypto:bitcoin:usd
```

Both routes read PostgreSQL. They accept 1–10 known instruments.

### Historical series

```text
GET /api/v1/rates/history?instruments=crypto:bitcoin:usd&from=<RFC3339>&to=<RFC3339>&step=5m&mode=price
```

Limits:

- one to five instruments;
- maximum 366-day query window;
- steps `5m`, `30m`, `1h`, `4h`, `1d`;
- modes `price`, `percent`.

Empty aggregation buckets are omitted.

### Observation rows

```text
GET /api/v1/requests/history?instrument_id=...&limit=50&cursor=...
```

### Market capitalization map

```text
GET /api/v1/market-map?period=1d
```

Periods: `1h`, `4h`, `1d`, `7d`, `30d`, `1y`. The service compares stored
market-cap observations, not price changes.

## API Fetcher internal API

API Fetcher is not used by UI.

```text
GET  /health/live
GET  /health/ready
POST /internal/v1/collect
POST /internal/v1/backfill
```

POST endpoints require:

```text
Authorization: Bearer <INTERNAL_API_TOKEN>
```

They return `queued` after RabbitMQ publisher confirmation. They do not imply a
PostgreSQL commit.

## RabbitMQ API boundary

`rates.fetch.commands` carries `rates.backfill.requested` commands to API
Fetcher. `rates.observations` carries `rate.observation.collected` events to
History Service. Both queues are durable and have dead-letter queues.
