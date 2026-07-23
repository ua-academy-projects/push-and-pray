# Refactor Prompt 4 — UI Charts and Final Integration

## Role

You are a senior frontend engineer implementing stage 4 (final) of a 4-stage architecture refactor of SkyIvano. Work carefully, keep code simple and explainable, and do not exceed the scope of this stage.

## Project context

Read `docs/architecture.md` (as updated through Stage 3), `docs/project-status.md`, and `refactor-0-discovery-and-plan.md` before doing anything else. By now `backend-service` exposes daily/statistics/chart endpoints backed by every stored date in PostgreSQL (Stage 3), fed independently by `fetcher-service` (Stage 2). This stage rebuilds `ui-service` into a dashboard that uses those endpoints, and does a final pass confirming every architecture rule holds end-to-end.

Inspect the current `ui-service/src/` structure first (`components/`, `hooks/useWeather.ts`, `api/weatherApi.ts`) — reuse what still fits (e.g. `CurrentWeatherCard`, `WeatherBackground`, layout/header) rather than rewriting the whole app.

## Current stage

**Stage 4 of 4 — UI charts and final integration.**

## Stage goal

A polished, responsive weather analytics dashboard that reads exclusively from `backend-service`'s public API, with interactive charts, a date-range selector, summary statistic cards, and explicit loading/empty/error/stale states.

## Scope

### Chart library

Pick one: Recharts, Chart.js + react-chartjs-2, or Apache ECharts + its React wrapper. Recommendation: **Recharts** — smallest bundle/API surface for the chart types needed here (line/bar/area, tooltips, responsive containers), idiomatic React (components, not imperative canvas calls), good TypeScript support out of the box. Document the actual choice and reasoning in `docs/architecture.md`, even if you pick a different one.

### API client

`src/api/weatherApi.ts` — add typed functions for the Stage 3 endpoints (`getDaily`, `getDailyByDate`, `getStatisticsDaily`, `getStatisticsPeriod`, `getStatisticsAll`, `getCharts`). Confirm (and keep it true) that this file only ever calls `VITE_BACKEND_BASE_URL` — no other base URL is configurable or hardcoded.

### Hooks

`src/hooks/` — add `useDateRange` (manages selected range + presets), `useStatistics`, `useCharts`, alongside the existing `useWeather`.

### Components

- `DateRangeSelector` — presets: Last 7 days, Last 10 days, Last 30 days, All available data (requests every stored date via `getCharts`/`getDaily` with no artificial limit), plus a manual date picker.
- `StatCards` — summary statistics for the selected range (from Stage 3's period-statistics response).
- Charts: average temperature by day, min/max temperature by day, average humidity by day, total precipitation by day, average/max wind speed, weather-condition distribution, temperature trend for the selected period.
- Reuse/extend existing `DataStatus` for loading/empty/error/stale-data states and last-synchronization time (read from `/api/sync-status`).

### Readability for long ranges

For "All available data" or 30+ day ranges: responsive width, reduced X-axis tick frequency, horizontal scroll or zoom as needed. No overlapping labels — verify visually.

## Out of scope

- No backend/fetcher changes (unless Stage 3's report flagged an endpoint rename the UI must adapt to — apply only that).
- No Docker/CI changes.

## Architecture rules (must hold)

- UI communicates only with `backend-service`. Grep `src/` for any URL other than `VITE_BACKEND_BASE_URL` before finishing — there should be none.
- UI never calls `fetcher-service`, Open-Meteo, or any internal/sync-triggering endpoint (`/internal/*`).
- Opening or refreshing the UI never triggers a synchronization — verify by watching `fetcher-service` logs while using the UI and confirming no fetch happens outside its own schedule.
- Charts are not hardcoded to 10 days — verify by seeding 45+ days in the test database and confirming "All available data" renders all of them.

## Detailed tasks

1. Read the docs and inspect the current UI code as described above.
2. Add the chosen chart library dependency.
3. Implement the API client functions, hooks, and components listed above.
4. Wire date-range selection end-to-end: selecting a preset or custom range re-fetches statistics + chart data for that range.
5. Implement loading/empty/error/stale states for every data-fetching component, not just the top-level page.
6. Manually test in a browser: golden path (default view), each preset, a custom range, an empty range (before any data exists / a future date range), a backend-down error state, a stale-data warning (stop `fetcher-service`, wait past `WEATHER_DATA_MAX_AGE_MINUTES`, confirm the UI surfaces it).
7. Write/port tests (below).
8. Update `README.md`, `docs/architecture.md`, `docs/project-status.md`, `docs/troubleshooting.md`.

## Testing requirements

Vitest + React Testing Library (existing convention). Cover: current weather rendering, date-range selection (all four presets + custom), daily statistics rendering, period statistics rendering, chart rendering, loading state, empty state, error state, stale-data warning, and explicit assertions that the API client/mocked fetch calls never target a fetcher or internal-sync URL.

## Verification commands

```bash
cd ui-service
npm install
npm run dev
npm test
```

With all four services running (`fetcher-service`, `backend-service`, `ui-service`, PostgreSQL), manually confirm the browser Network tab shows requests only to `backend-service`'s `/api/*` endpoints — never to Open-Meteo, `fetcher-service`, or `/internal/*`.

## Documentation updates

- `README.md`: final architecture-at-a-glance diagram and run instructions for all four services.
- `docs/architecture.md`: chart library choice + reasoning, final end-to-end diagrams, confirm every section matches the shipped implementation.
- `docs/project-status.md`: mark Stage 4 and the overall refactor complete; run through the acceptance criteria list from `refactor-0-discovery-and-plan.md` and confirm each one explicitly.
- `docs/troubleshooting.md`: real issues only.

## Acceptance criteria

- Full acceptance criteria list from `refactor-0-discovery-and-plan.md` holds end-to-end.
- All tests pass across all four services.
- The application is simple enough to explain in a mentor review.

## Required final report

- Summary of what was built
- Changed files (list)
- Chart library chosen and why
- Tests executed and results
- Manual verification performed (commands + outcomes, including the Network-tab check)
- Problems encountered
- Troubleshooting doc updates made
- Remaining work / anything deferred
- project-status.md updates made
- Final confirmation against every item in the acceptance criteria list

## Stop condition

This is the final stage. Stop after completing and reporting — do not start unrelated follow-up work without being asked.
