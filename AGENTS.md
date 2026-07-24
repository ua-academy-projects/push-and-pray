# Crypto & Fiat Rates Dashboard - project specification

This document is the source of truth for Codex and contributors. Build the application incrementally, keep service boundaries explicit, and prefer code that a DevOps Academy student can explain.

## 1. Product goal

Create a small multi-service web application that shows current and historical cryptocurrency and fiat exchange rates. The repository will later be used for Docker, orchestration, CI/CD, and cloud exercises, so each service must be independently runnable and configurable.

The first version must satisfy the Assignment 1 architecture:

```text
Browser -> UI service -> Python Backend/Proxy -> CoinGecko / Frankfurter
                          |
                          +-> Go API Fetcher -> PostgreSQL
```

Hard boundaries:

- The browser/UI obtains all application data only from the Python Backend. It also loads pinned Chart.js assets from jsDelivr.
- The UI never calls CoinGecko, Frankfurter, PostgreSQL, or the API Fetcher directly.
- The Backend is the orchestration point for external data.
- Only the Go API Fetcher owns and accesses PostgreSQL.
- Explicit provider-refresh requests, scheduled collector results, and backfill points are forwarded by Backend to API Fetcher. Normal overview/cached reads are not persisted; charts read already stored PostgreSQL observations.
- Do not add direct database access to the Backend or UI.

## 2. Technology choices

### UI service

- HTML5, CSS3, and vanilla JavaScript (ES modules).
- A minimal static-file HTTP server is allowed; do not introduce React/Vue for the first assignment.
- Use Chart.js for the multi-series history chart. Pin the version rather than referencing `latest`.
- Responsive layout for desktop and mobile.
- Implement light and dark themes with CSS custom properties; components must use semantic design tokens rather than hard-coded theme colors.
- No secrets in frontend code.

### Backend / Proxy service

- Python 3.12+.
- FastAPI, Uvicorn, Pydantic Settings, and `httpx.AsyncClient`.
- Responsibilities: validate UI input, call public APIs, normalize heterogeneous responses, call History, and return one stable internal JSON contract.
- Generate OpenAPI automatically through FastAPI.

### API Fetcher (the Go API service)

- Go 1.23+ using `net/http` or a small router such as Chi.
- `pgx/v5` for PostgreSQL access.
- Responsibilities: accept normalized observations from Backend, persist them, and return stored request/price history.
- This service must not call CoinGecko or Frankfurter.

### Database

- PostgreSQL 16+.
- Schema migrations are owned by `api-fetcher`.
- Store normalized numeric values in `NUMERIC`, not floating-point database columns.
- Store timestamps as `TIMESTAMPTZ` in UTC.

## 3. External data sources

### CoinGecko

Public root: `https://api.coingecko.com/api/v3`.

Use:

- `GET /coins/markets` for the top 10 cryptocurrencies by market capitalization.
- `GET /coins/markets?ids=...` for current cryptocurrency price plus one-hour/day change.
- `GET /coins/{id}/market_chart` for historical cryptocurrency prices.

Use CoinGecko IDs (`bitcoin`, `ethereum`) as identifiers, not ticker symbols, because symbols are not unique. Support an optional `COINGECKO_API_KEY`; the application must work with the keyless public API at reduced rate limits. Respect `Retry-After` on HTTP 429.

### Frankfurter

Public root: `https://api.frankfurter.dev/v2`; no key is required.

Use:

- `GET /rates?base=USD&quotes=UAH` for current/latest working-day rates.
- `GET /rates?base=USD&quotes=UAH&from=YYYY-MM-DD&to=YYYY-MM-DD` for time series.

Frankfurter rates are reference rates and update daily, not live trading quotes. Always display the source date returned by the provider. Weekend/holiday requests may return the latest working day.

## 4. User experience

The UI has three primary tabs: **Overview**, **History**, and **Capitalization**. Labels may be Ukrainian, but code, endpoint names, database names, and documentation identifiers are English.

### Visual style and themes

Use a minimalist, modern visual language: generous whitespace, a clear typographic hierarchy, restrained borders and shadows, rounded but not excessively pill-shaped controls, and subtle transitions. The rates and charts are the focal point. Avoid gradients, glassmorphism, decorative illustrations, visual noise, and excessive animation.

- Provide a clearly visible light/dark theme toggle in the header using a sun/moon icon plus an accessible label.
- On the first visit, follow `prefers-color-scheme`. After the user switches theme, save `light` or `dark` in `localStorage` and honor that explicit choice on future visits.
- Apply the theme before the page becomes visible to prevent a flash of the wrong theme.
- Set `color-scheme: light dark` appropriately so native controls match the active theme.
- The toggle must be keyboard-operable and expose its current state with an accessible name or `aria-pressed`.
- Theme changes must update cards, navigation, selectors, chart background, grid, axes, legends, tooltips, focus rings, loading states, and errors without reloading the page.
- Animate color/background/border changes for approximately 150-200 ms, while respecting `prefers-reduced-motion`.

Suggested semantic tokens and palette:

```css
:root,
[data-theme="light"] {
  color-scheme: light;
  --color-bg: #f7faf8;
  --color-surface: #ffffff;
  --color-surface-muted: #eef5f0;
  --color-text: #17211b;
  --color-text-muted: #617068;
  --color-border: #dce8e0;
  --color-primary: #168a4b;
  --color-primary-hover: #0f713d;
  --color-primary-soft: #e2f5e9;
  --color-negative: #c53b3b;
  --color-focus: #22a45d;
}

[data-theme="dark"] {
  color-scheme: dark;
  --color-bg: #151917;
  --color-surface: #1d2420;
  --color-surface-muted: #252e29;
  --color-text: #edf5f0;
  --color-text-muted: #a4b4aa;
  --color-border: #344239;
  --color-primary: #45c978;
  --color-primary-hover: #67d991;
  --color-primary-soft: #183c28;
  --color-negative: #ff7777;
  --color-focus: #67d991;
}
```

These values are a starting point, not a reason to duplicate raw colors throughout CSS. Keep the light theme predominantly white with green accents, and the dark theme dark gray rather than pure black, also with green accents. Maintain WCAG AA contrast for normal text and interactive states. Positive and negative values must include an arrow/sign or text in addition to green/red color.

### Overview tab

On first load:

- Show Bitcoin/USD as the primary large rate card.
- Show price, quote currency, available one-hour/day percentage changes, provider, and last-updated timestamp.
- Below it, show a selectable top-10 cryptocurrency list ordered by market cap. Each row includes one-hour/day changes and a compact seven-day price sparkline.
- Show a second list of popular fiat pairs against UAH. The initial set is `USD/UAH`, `EUR/UAH`, `GBP/UAH`, `PLN/UAH`, `CHF/UAH`, `CAD/UAH`, `AUD/UAH`, `JPY/UAH`, `CNY/UAH`, and `CZK/UAH`. Only show pairs supported by the provider.

Interaction:

- Clicking any crypto or fiat row replaces the primary large card with that instrument.
- A `+ Compare` action opens a searchable selector and adds another full-width card below the existing rate cards.
- Multiple comparison cards may be added. Each can be removed independently, and the add-card control always remains last.
- A `Refresh` action reads the latest persisted samples from PostgreSQL through Backend/History, shows a loading state, disables duplicate clicks, and displays an inline error without clearing the last valid value. It must not call public providers.
- Visually distinguish positive, negative, and unavailable changes. Do not use color as the only signal.

### History tab

- Select up to five crypto or fiat instruments through a searchable checkbox picker.
- Choose a data period independently: `1D`, `7D`, `30D`, `90D`, or `1Y`.
- Choose a PostgreSQL aggregation step independently: `5M`, `30M`, `1H`, `4H`, or `1D`.
- Choose chart mode: absolute price or percentage change.
- In percentage mode normalize every series to `0%` at the first common visible timestamp: `(value / firstValue - 1) * 100`.
- Every build action adds a separate dynamic chart card. Refresh updates existing cards without removing them.
- Existing chart cards refresh automatically every five minutes on wall-clock boundaries while the page is visible; do not run overlapping refresh cycles.
- Change chart scale with mouse/touch zoom. Allow individual zoom reset and clearing all chart cards.
- Allow exporting all current chart cards through a print-optimized PDF flow.
- Toggle individual series through the legend.
- Tooltips show timestamp, pair, formatted value/change, and source.
- The chart reads stored PostgreSQL observations through Backend and History. Empty aggregation buckets are not interpolated.

### Capitalization tab

- Allow adding multiple independent top-10 CoinGecko capitalization treemaps for `1H`, `4H`, `1D`, `7D`, `30D`, and `1Y`.
- Rectangle area must be proportional to current market capitalization.
- Green means capitalization increased, red means it decreased, and gray means the absolute change is no more than 0.01%.
- Calculate capitalization change from CoinGecko `market_caps` history rather than substituting price change.
- Allow refreshing, removing, and clearing maps. Include every current map in the structured PDF report.

Accessibility requirements:

- Keyboard-operable tabs, lists, selectors, and buttons.
- Visible focus state, semantic HTML, labels for inputs, and appropriate ARIA only where native semantics are insufficient.
- WCAG AA contrast in both themes, including hover, disabled, chart, and muted-text states.
- Minimum usable viewport width: 320px.

## 5. Domain model and normalized contracts

An `instrument` is identified as:

- Crypto: `crypto:{coingecko_id}:{quote}`, for example `crypto:bitcoin:usd`.
- Fiat: `fiat:{base}:{quote}`, for example `fiat:USD:UAH`.

Canonical current-rate representation:

```json
{
  "instrument_id": "crypto:bitcoin:usd",
  "kind": "crypto",
  "base": "BTC",
  "quote": "USD",
  "name": "Bitcoin",
  "price": "67187.33589366",
  "change_1h_percent": "0.421",
  "change_24h_percent": "3.63727848",
  "market_cap": "1317800000000.00",
  "rank": 1,
  "source": "coingecko",
  "source_timestamp": "2026-07-17T09:30:00Z",
  "requested_at": "2026-07-17T09:30:03Z"
}
```

Decimal values are JSON strings to avoid accidental precision loss between Python, Go, JavaScript, and PostgreSQL. UI rounds displayed rates to two decimals without changing stored precision. Optional values are `null`, not omitted. Fiat change, market-cap, and rank values are normally `null`.

History point:

```json
{
  "timestamp": "2026-07-16T00:00:00Z",
  "value": "40.9532"
}
```

Use UTC over all service boundaries. The UI formats dates in the browser's locale and indicates the timezone.

## 6. Backend API exposed to UI

All endpoints are prefixed with `/api/v1`.

### Health

- `GET /health/live` - process is alive; no downstream checks.
- `GET /health/ready` - reports History reachability; external providers should not make readiness fail permanently.

### Catalog and current data

- `GET /api/v1/instruments` - supported crypto and fiat instruments for selectors.
- `GET /api/v1/market-map?period=1d` - top-10 capitalization treemap data and calculated capitalization change; supported periods are `1h`, `4h`, `1d`, `7d`, `30d`, and `1y`.
- `GET /api/v1/overview?quote=usd&fiat_quote=UAH` - Bitcoin primary card, crypto top 10, and popular fiat pairs in one response.
- `GET /api/v1/rates/current?instruments=crypto:bitcoin:usd,fiat:USD:UAH&refresh=false` - current normalized rates, maximum 10 instruments.
- `POST /api/v1/rates/refresh` with `{ "instruments": [...] }` - explicitly bypass Backend cache and persist fresh successful observations.
- `GET /api/v1/rates/stored-current?instruments=...` - latest PostgreSQL samples for the UI refresh button; never calls public providers.
- `POST /api/v1/rates/backfill` - fetch and persist up to 20 provider series over at most 366 days.

### Historical data

- `GET /api/v1/rates/history?instruments=...&from=...&to=...&step=5m&mode=price` - stored PostgreSQL series, maximum five instruments and maximum one year for version 1.
- `GET /api/v1/requests/history?instrument_id=...&limit=50&cursor=...` - Backend proxies the API Fetcher response; do not let UI call Go directly.

Provider-client failures return this structured error envelope:

```json
{
  "error": {
    "code": "UPSTREAM_RATE_LIMITED",
    "message": "Rate provider is temporarily unavailable",
    "request_id": "uuid",
    "retry_after_seconds": 30
  }
}
```

FastAPI validation and explicit `HTTPException` responses currently use FastAPI's `{ "detail": ... }` shape. Use HTTP 400/422 for invalid input, 404 for unknown instruments, 429 for provider rate limits, 502 for other upstream failures, and 503 when a required internal service is unavailable.

## 7. Internal History API

The Go service is internal and exposes:

- `GET /health/live`
- `GET /health/ready` including a PostgreSQL ping
- `POST /internal/v1/observations` - idempotently store one normalized observation
- `POST /internal/v1/observations/batch` - store a bounded batch of up to 100 items; current implementation is sequential and non-atomic
- `GET /internal/v1/observations?instrument_id=...&limit=...&cursor=...`
- `GET /internal/v1/series?instruments=...&from=...&to=...&step=...` - bucket stored observations for charts

Backend sends `Idempotency-Key`, derived from `source + instrument_id + source_timestamp + requested_at`, so retries of the same sample do not create duplicates. Use a short internal shared token (`API_FETCHER_TOKEN`) for basic service-to-service authorization even in local development; never log it.

If provider retrieval succeeds but API Fetcher saving fails, return current data with `persistence_status: "failed"` and log the failure. Do not pretend persistence succeeded. A later version may add a durable queue, but that is outside Assignment 1.

## 8. PostgreSQL schema

Initial migration:

```sql
CREATE TABLE observations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    instrument_id TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('crypto', 'fiat')),
    base_code TEXT NOT NULL,
    quote_code TEXT NOT NULL,
    price NUMERIC(38, 18) NOT NULL CHECK (price > 0),
    change_24h_percent NUMERIC(20, 10),
    market_cap NUMERIC(38, 8),
    rank INTEGER,
    source TEXT NOT NULL,
    source_timestamp TIMESTAMPTZ NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'success',
    request_id UUID NOT NULL,
    raw_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (source, instrument_id, source_timestamp, requested_at)
);

CREATE INDEX observations_instrument_requested_idx
    ON observations (instrument_id, requested_at DESC);
CREATE INDEX observations_requested_idx
    ON observations (requested_at DESC);
```

Do not store API keys, authorization headers, or entire upstream responses in `raw_metadata`.

## 9. Caching, resilience, and limits

- Backend in-memory TTL cache: current crypto 30 seconds, crypto top 10 60 seconds, and fiat current 1 hour. Catalog is currently static and provider history is not cached.
- `refresh=true` bypasses read cache but updates it after success.
- External HTTP timeout: 5 seconds connect, 10 seconds total target; retry at most twice for idempotent GET on timeout, 429, or 5xx with exponential backoff and jitter.
- Do not retry validation errors or most 4xx responses.
- Limit query counts and date spans before calling providers.
- Current implementation does not serve expired stale cache entries after upstream failure.
- Add a request/correlation ID at the Backend boundary and forward it to API Fetcher.
- Structured JSON logs must include service, level, request_id, route, status, latency_ms, and upstream name where relevant. Never log secrets.

Backend also owns a background collector. It aligns runs to absolute `COLLECTOR_INTERVAL_SECONDS` wall-clock boundaries, fetches all 20 configured instruments with cache bypassed, and persists successful results. With the default 300 seconds it starts at `:00`, `:05`, `:10`, `:15`, and so on. Values below 60 are clamped. This accumulates five-minute samples going forward. Frankfurter values may remain unchanged during a day, and unavailable historical five-minute points must never be fabricated.

## 10. Repository structure

```text
project-root/
  AGENTS.md
  README.md
  .env.example
  ui-service/
    public/
      index.html
      css/
      js/
    tests/
  backend-service/
    app/
      clients.py
      models.py
      services.py
      config.py
      main.py
    tests/
    pyproject.toml
  api-fetcher/
    cmd/server/
    internal/
      api/
      config/
      repository/
    migrations/
    go.mod
  scripts/
    start-all.sh
    backfill-year.sh
  docs/
    architecture.md
    api.md
```

Do not add Docker Compose, Kubernetes, CI/CD, or cloud infrastructure until the three services work locally; those are intentionally later assignments.

## 11. Configuration

Document these variables in `.env.example` without real values:

```text
BACKEND_HOST=127.0.0.1
BACKEND_PORT=8000
UI_ORIGIN=http://127.0.0.1:3000
API_FETCHER_URL=http://127.0.0.1:8081
API_FETCHER_TOKEN=change-me
COINGECKO_BASE_URL=https://api.coingecko.com/api/v3
COINGECKO_API_KEY=
FRANKFURTER_BASE_URL=https://api.frankfurter.dev/v2
COLLECTOR_ENABLED=true
COLLECTOR_INTERVAL_SECONDS=300
DATABASE_URL=postgres://rates:rates@127.0.0.1:5432/rates?sslmode=disable
API_FETCHER_HOST=127.0.0.1
API_FETCHER_PORT=8081
UI_HOST=127.0.0.1
UI_PORT=3000
BACKFILL_YEAR_ON_START=0
LOG_LEVEL=INFO
```

Bind to localhost by default. CORS should allow only the configured UI origin in development.

## 12. Testing and acceptance criteria

### Automated tests

- Current Python tests cover instrument parsing, TTL cache expiry, decimal serialization, and alignment of the collector to five-minute wall-clock boundaries.
- Current UI utility tests cover percentage normalization, theme selection, and two-decimal display formatting.
- `go test ./...` currently verifies package compilation; dedicated Go test files and full mocked integration/E2E coverage remain future work.

### Definition of done for Assignment 1

- All three services start independently using README commands.
- UI communicates only with Backend.
- Backend fetches and normalizes CoinGecko and Frankfurter data.
- Every successful explicit fetch is sent to API Fetcher and persisted once.
- The History tab visualizes stored PostgreSQL observations through Backend and History; a separate paginated request-row view remains optional follow-up work.
- Overview provides Bitcoin, crypto top 10, fiat pairs, multi-card comparison, one-hour/day statistics, and refresh without losing cards.
- History UI supports up to five series per dynamic chart, price/% modes, short/year ranges, refresh-all, zoom, clear-all, and print-to-PDF export.
- Light and dark themes match the specified palettes, persist the user's choice, and keep all UI/chart states readable and accessible.
- Invalid input and upstream failure produce useful, non-secret errors.
- Tests and linters pass.
- README explains architecture, boundaries, prerequisites, environment variables, migrations, start order, test commands, and major design decisions.

## 13. Recommended implementation order

1. Scaffold the three services and health endpoints.
2. Add PostgreSQL migration and Go API Fetcher create/list endpoints.
3. Add Python provider clients and normalization tests.
4. Connect Backend to API Fetcher with idempotency and failure reporting.
5. Implement Overview API and basic UI.
6. Add PostgreSQL history aggregation and the multi-series chart.
7. Add stronger resilience, accessibility audits, and end-to-end tests.

Keep commits small and ensure the application remains runnable after each stage. Do not silently expand scope into authentication, user accounts, trading, portfolios, WebSockets, or deployment infrastructure.
