# API reference

[Українська версія](api.uk.md)

FastAPI exposes interactive schemas at `http://127.0.0.1:8000/docs`. All UI-facing data endpoints use `/api/v1`.

## Backend health

### `GET /health/live`

Returns `200` when the Backend process is alive. It does not check dependencies.

### `GET /health/ready`

Checks History readiness. Returns `200` with `status: ready` or `503` with `status: degraded`. Provider availability does not affect readiness.

## Catalog and current rates

### `GET /api/v1/instruments`

Returns the static 20-instrument selector catalog: 10 configured crypto/USD instruments and 10 fiat/UAH pairs.

### `GET /api/v1/overview?quote=usd&fiat_quote=UAH`

Returns:

- `primary`: first CoinGecko market item (normally Bitcoin);
- `crypto`: top 10 CoinGecko markets by market cap;
- `fiat`: configured USD, EUR, GBP, PLN, CHF, CAD, AUD, JPY, CNY, and CZK pairs.

Overview reads do not persist observations.

### `GET /api/v1/rates/current`

Query parameters:

- `instruments`: comma-separated IDs, required, 1–10;
- `refresh`: boolean, default `false`.

When `refresh=false`, Backend may serve its in-memory current cache and does not persist. When `true`, it bypasses cache and queues each returned observation for History.

### `POST /api/v1/rates/refresh`

Body, 1–20 instruments:

```json
{
  "instruments": ["crypto:bitcoin:usd", "fiat:USD:UAH"]
}
```

Bypasses current cache, persists successful observations, and returns `items` with `persistence_status`.

### `GET /api/v1/rates/stored-current?instruments=...`

Returns the latest PostgreSQL observation for each of 1–10 instruments through the History service. This endpoint never calls CoinGecko or Frankfurter and is used by the UI `Оновити` button.

## Provider history and backfill

### `GET /api/v1/market-map?period=1d`

Returns the current CoinGecko top-10 market caps and calculated market-cap change for one of `1h`, `4h`, `1d`, `7d`, `30d`, or `1y`. Each period is cached for 300 seconds. Every item includes `instrument_id`, `name`, `symbol`, decimal-string `market_cap`, decimal-string `change_percent`, `period`, `source`, and `source_timestamp`.

### `GET /api/v1/rates/history`

Query parameters:

- `instruments`: comma-separated IDs, 1–5;
- `from`: RFC3339 timestamp, required;
- `to`: RFC3339 timestamp, required;
- `step`: PostgreSQL aggregation step: `5m`, `30m`, `1h`, `4h`, or `1d`;
- `mode`: `price` or `percent`, default `price`;
- maximum date span: 366 days.

The response contains series read from PostgreSQL through History. Each point is the latest stored observation in its `step` bucket. Empty buckets are omitted; percentage normalization is performed by UI.

### `POST /api/v1/rates/backfill`

Body, 1–20 instruments and at most 366 days:

```json
{
  "instruments": ["crypto:bitcoin:usd", "fiat:USD:UAH"],
  "from_date": "2025-07-17",
  "to_date": "2026-07-17"
}
```

With RabbitMQ enabled, returns per-instrument `fetched`, `queued`, and `persistence_status` values. Without RabbitMQ it returns synchronous `inserted` and `duplicates` counts.

### `GET /api/v1/requests/history`

Proxies stored PostgreSQL observations through History. The current UI does not display this endpoint.

Query parameters:

- `instrument_id`: optional exact ID;
- `limit`: 1–100, default 50;
- `cursor`: optional RFC3339 timestamp from `next_cursor`.

## Current rate shape

Decimal fields are JSON strings:

```json
{
  "instrument_id": "crypto:bitcoin:usd",
  "kind": "crypto",
  "base": "BTC",
  "quote": "USD",
  "name": "Bitcoin",
  "price": "67187.33589366",
  "change_1h_percent": "0.42",
  "change_24h_percent": "3.63",
  "market_cap": "1317800000000",
  "rank": 1,
  "source": "coingecko",
  "source_timestamp": "2026-07-17T09:30:00Z",
  "requested_at": "2026-07-17T09:30:03Z",
  "stale": false,
  "persistence_status": "queued"
}
```

Fiat change/market/rank values are normally `null`. `change_1h_percent` is returned to UI but the current PostgreSQL schema does not persist it.

`persistence_status` is `queued` after a confirmed RabbitMQ publish, `saved` after synchronous HTTP fallback, `failed` when neither path succeeds, and `skipped` for reads that are intentionally not persisted.

## RabbitMQ observation events

Backend publishes persistent JSON messages to the durable direct exchange `rates.events` with routing key `observation.persist`. History consumes `rates.observations`, acknowledges only after the PostgreSQL insert, and dead-letters a repeatedly failed delivery to `rates.observations.dlq`. Queue names and the broker URL are configurable through `RABBITMQ_*` variables.

## Provider error shape

```json
{
  "error": {
    "code": "UPSTREAM_RATE_LIMITED",
    "message": "coingecko request failed",
    "request_id": "uuid",
    "retry_after_seconds": 30
  }
}
```

Provider errors use this shape. FastAPI validation and explicit `HTTPException` responses use `{ "detail": ... }`.

## Internal History API

All `/internal/v1/*` endpoints require bearer authorization.

### `POST /internal/v1/observations`

Inserts one normalized observation. Returns `201 {"created": true}` for a new provider point or `200 {"created": false}` for a duplicate.

### `POST /internal/v1/observations/batch`

Body: `{ "items": [...] }`, with 1–100 observations. Returns created/total counts. The current implementation inserts sequentially; it is not atomic across the whole batch.

### `GET /internal/v1/observations`

Supports `instrument_id`, `limit` (maximum 100), and RFC3339 `cursor`. Returns descending request time and `next_cursor` when another page may exist. It does not currently implement `from`/`to` filtering.

History health endpoints are `GET /health/live` and `GET /health/ready`; readiness includes a PostgreSQL ping.
