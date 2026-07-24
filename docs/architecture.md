# Current architecture

[Українська версія](architecture.uk.md)

## Components and ownership

```text
Browser
  └─ HTTP :3000 → UI service (static HTML/CSS/ES modules)
       └─ HTTP :8000 → Python Backend / Proxy
            ├─ HTTPS → CoinGecko
            ├─ HTTPS → Frankfurter
            ├─ AMQP :5672 → RabbitMQ → Go API Fetcher consumer
            └─ HTTP :8081 + bearer token → Go API Fetcher (reads/write fallback)
                 └─ PostgreSQL protocol :5432 → PostgreSQL 16
```

- **UI** renders overview cards and dynamic Chart.js charts. It has no provider/database credentials and calls only Backend. Chart.js 4.4.7 and chartjs-plugin-zoom 2.2.0 are pinned CDN dependencies.
- **Backend** validates instrument IDs, calls both providers, normalizes decimals/timestamps, serves UI APIs, runs manual backfill orchestration, and owns the periodic collector.
- **API Fetcher** validates normalized observations and exclusively owns PostgreSQL queries. Internal endpoints require `Authorization: Bearer <API_FETCHER_TOKEN>`.
- **RabbitMQ** durably buffers explicit refresh, collector, and backfill observations. The main queue is `rates.observations`; repeatedly failed messages are dead-lettered to `rates.observations.dlq`.
- **PostgreSQL** stores observations in `NUMERIC`/`TIMESTAMPTZ` columns. `(source, instrument_id, source_timestamp, requested_at)` makes a sampled point idempotent while allowing a new observation every five minutes.

## Main flows

### Provider collection and current reads

1. The scheduled collector or explicit provider-refresh endpoint calls CoinGecko and/or Frankfurter.
2. Backend normalizes the response and publishes a persistent observation event to RabbitMQ.
3. API Fetcher consumes the event, inserts the sample, and sends `ACK` only after PostgreSQL accepts it. Exact duplicates are harmless because the database uses `ON CONFLICT DO NOTHING`.
4. If RabbitMQ publishing fails, Backend falls back to the authenticated synchronous History HTTP endpoint.
4. The UI Overview refresh button follows a separate read-only path through `stored-current` and never calls a provider.

The top-10 overview request asks CoinGecko `/coins/markets` for `sparkline=true` and `price_change_percentage=1h,24h`, so weekly sparklines and both short changes arrive in the same provider call.

Normal cached current reads are not persisted. UI displays values with two decimals, while JSON and PostgreSQL retain full precision.

The Overview `Оновити` button calls `GET /api/v1/rates/stored-current`. Backend requests the newest persisted row per instrument from API Fetcher, so this user action never calls a public provider. Provider polling is isolated in the scheduled collector.

### PostgreSQL history charts

1. UI creates an independent graph configuration (up to five series).
2. UI sends an exact RFC3339 time window and an independent bucket step (`5m`, `30m`, `1h`, `4h`, or `1d`) to Backend.
3. Backend proxies the request to API Fetcher; API Fetcher uses PostgreSQL `date_bin` and takes the latest stored value in each bucket.
4. UI optionally normalizes each returned series to percentage change and renders a separate Chart.js instance. Refresh-all and automatic five-minute refresh preserve every chart card.

PDF export builds a dedicated print-only report rather than printing the live layout. It snapshots every active chart to PNG, includes every remaining overview card, records generation date/time to the second, and adds the Rateboard copyright/service footer. If a section has no data, the report explicitly says that information is unavailable.

The graph step is aggregation, not the requested time range. For example, period `1d` with step `30m` returns up to 48 PostgreSQL buckets. Empty buckets are not interpolated.

### Five-minute collector

The collector is an `asyncio` background task inside Backend. It aligns each cycle to an absolute wall-clock interval boundary; with the default 300-second interval it starts at `:00`, `:05`, `:10`, `:15`, and so on, independent of Backend startup time or the duration of the previous cycle. It then sequentially requests all 20 catalog instruments with cache bypassed. Each successful result is sent to API Fetcher with a cycle correlation ID. Per-instrument failures are logged and do not stop later instruments. The task is cancelled during Backend shutdown.

This produces five-minute sampled observations going forward. Fiat values may remain unchanged all day because Frankfurter publishes daily reference rates, but each collector run has its own aligned `requested_at`. It cannot reconstruct missing historical five-minute samples while the application was stopped.

### Capitalization treemaps

The capitalization tab calls `GET /api/v1/market-map` for a selected period. Backend takes the current top-10 market caps, fetches each coin's historical `market_caps` series, and calculates `(current / baseline - 1) × 100`. Results are cached for five minutes per period. UI recursively partitions the available area so each rectangle's area is proportional to current capitalization, while green/red/gray represents positive, negative, or negligible capitalization change. Users may keep multiple period maps simultaneously; all are reproduced as structured HTML in the PDF report.

### Annual backfill

`scripts/backfill-year.sh` calls `POST /api/v1/rates/backfill`. Backend processes instruments sequentially, retrieves provider series, converts every point to an observation, and sends batches of at most 100 to API Fetcher. Each batch is an independent request; the current API Fetcher batch handler inserts its items one by one and is not an all-or-nothing database transaction.

## Time, precision, and failure behavior

- Service timestamps use UTC; UI formats dates in the browser locale.
- Decimal JSON fields are strings. UI rounds displayed rates to two decimals only.
- Provider GETs use a 5-second connect/10-second client timeout target and retry timeouts/network errors/429/5xx up to two times with backoff.
- Provider errors use Backend's structured provider error envelope. Standard FastAPI validation/HTTP errors use FastAPI's `detail` response shape.
- A successfully published observation returns `persistence_status: queued`; synchronous fallback returns `saved` or `failed`. If the UI database refresh cannot reach History, Backend returns `503` and UI preserves its last valid state.
- RabbitMQ retries a database failure once through redelivery; another failure routes the message to the durable dead-letter queue.

## Runtime and security

- Services bind to localhost by default.
- CORS allows only `UI_ORIGIN`.
- `.env`, API-key files, private keys, dumps, logs, `.run/`, virtualenvs, and caches are excluded by `.gitignore`/`.codexignore`.
- Secrets must never be placed in frontend code or logs.
- Docker, Kubernetes, CI/CD, authentication, and cloud deployment are intentionally outside this assignment.

## Assignment 1 compliance note

The required service boundaries are implemented: UI calls Backend only, Backend calls providers and History, and History alone owns PostgreSQL. Current data, explicit refresh, persistence, and stored-history APIs work.

The `Історія` tab now visualizes stored PostgreSQL observations through Backend and History. A separate paginated request-row table is not implemented, but stored data is visible as time series. Normal Overview reads are not persisted; explicit refreshes, scheduled collector cycles, and backfill are. See `assignment-compliance.md` for the full matrix.
