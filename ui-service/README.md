# UI Service

React + TypeScript dashboard for SkyIvano. Talks only to the Backend Service's public API (`VITE_BACKEND_BASE_URL`). Never calls Open-Meteo, the Weather Fetcher Service, or PostgreSQL directly, and never triggers a *scheduled* synchronization — the one exception is the "Refresh now" control, which calls `POST /api/sync/trigger` on the Backend.

Full UI behavior rules: [../docs/architecture.md](../docs/architecture.md).

## Setup

```bash
npm install
cp .env.example .env   # adjust VITE_BACKEND_BASE_URL if needed
```

Requires the Backend Service to be running (see [../backend-service/README.md](../backend-service/README.md)).

## Run

```bash
npm run dev
```

## Test

```bash
npm test
```
