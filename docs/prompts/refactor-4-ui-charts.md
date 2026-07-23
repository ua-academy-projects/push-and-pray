# Refactor Prompt 4 — UI Charts and Final Integration

## Role

You are a senior frontend engineer implementing stage 4 (final) of a 4-stage architecture refactor of SkyIvano. Work carefully, keep code simple and explainable, and do not exceed the scope of this stage.

## Project context

Read `docs/architecture.md` (as updated through Stage 3), `docs/project-status.md`, and `refactor-0-discovery-and-plan.md` before doing anything else. By now `backend-service` exposes daily/statistics/chart endpoints backed by every stored date in PostgreSQL (Stage 3), fed independently by `fetcher-service` (Stage 2). This stage rebuilds `ui-service` into a dashboard that uses those endpoints, and does a final pass confirming every architecture rule holds end-to-end.

Inspect the current `ui-service/src/` structure first (`components/`, `hooks/useWeather.ts`, `api/weatherApi.ts`) — reuse what still fits (e.g. `CurrentWeatherCard`, `WeatherBackground`, layout/header) rather than rewriting the whole app.

## Current stage

**Stage 4 of 4 — UI charts and final integration.**

## Stage goal

A polished, responsive weather analytics dashboard that reads exclusively from `backend-service`'s public API, organized into four sections, with interactive charts, summary statistic cards, a manual refresh control, and explicit loading/empty/error/stale states.

## Navigation and content structure (decided)

The dashboard is a single scrolling page, not a tab-per-route app. A persistent current-conditions hero sits at top, followed by a **status strip**, then three sections that are **all visible immediately, stacked, with no click required to reach any of them**:

1. **Today** — the current day's hourly weather, all 24 hours, as a plain hour-by-hour list (horizontally-scrolling hour cards: hour + temperature only). **No chart here** — this was an explicit correction from the first draft of this stage. Data from `GET /api/weather/hourly` / the Stage 3 daily/hourly reads — carry the existing hourly fetch forward, just change how it renders.
2. **Forecast** — next 10 days, from `GET /api/weather/forecast?days=10` (Stage 3). Also a plain list, not a chart: horizontally-scrolling day cards (date, condition glyph, high/low, precipitation chance), each visibly tagged "predicted." Forecast values are expected to change before the date arrives — the card treatment (not a precise line+band chart) is deliberate, so the UI doesn't imply false precision about numbers that will move.
3. **Averages** — the *only* section with charts, and it must cover more than temperature: average temperature (line + min/max band), average humidity (area), total precipitation (bar), average/max wind speed (two-line), and weather-condition distribution (donut), all from `GET /api/weather/statistics*` / `GET /api/weather/charts`. Give this section its own compact range control (Last 7 / 10 / 30 days / All available data) — it still needs to satisfy "charts must be able to show every stored date," it just doesn't need a page of its own to do it. Default to Last 30 days.

**History is not one of the three always-visible sections.** It opens in its own overlay window, triggered by a button (e.g. "Open history ↗") — reuse the same plain-list treatment as Today/Forecast (date + recorded avg/min/max temperature, no chart), with its own range presets (7/10/30/All) so "All available data" is reachable there too, just not chart-rendered. This is also where the accessibility "a table view exists" requirement is satisfied — the history overlay *is* the table view.

### Manual refresh — status strip + inline log

Confirmed pattern: a persistent status strip (not a modal, not a drawer) sitting between the hero and the Today section, containing: a sync-status chip (ok/failed), "last synced at {time}", "next scheduled run", an expandable **inline log** toggle, and the "Refresh now" button itself.

- **Refresh now** calls `POST /api/sync/trigger` on the Backend and waits for the response before updating displayed data — the one path by which user action can cause a synchronization (see `refactor-2-fetcher-service.md`; it still never touches Open-Meteo or the Fetcher directly). Show a spinner + "Refreshing…" on the button itself while in flight — not a full-page loading state, the rest of the dashboard stays interactive. On success, update the "last synced" time and prepend a new row to the log.
- Clicking the log toggle expands an **inline panel directly beneath the strip** (accordion, no overlay) listing recent attempts from `GET /api/sync/history` — timestamp, trigger type (scheduled/manual), a status chip (success/failed, icon + label, never color alone), and an error message when failed. This is a genuinely different feature from the stale-data banner: the banner is passive ("this data might be old"), the log is an on-demand history a user actively opens.

### Visual design (decided)

Two design rounds were mocked up and reviewed; both are settled — implement to these specifics rather than re-deriving them:

- **Background**: reuse the existing `WeatherBackground.tsx` / `WeatherBackground.module.css` unchanged — the live condition-driven gradient + sun/moon glow + drifting clouds/rain/snow/fog already there is correct and was explicitly kept, not redesigned. Do not rebuild it.
- **Foreground language ("Glass")**: frosted, translucent cards floating on that background.
  - Card surface: `rgba(255,255,255,0.50)` with `backdrop-filter: blur(18px) saturate(160%)`, `border: 1px solid rgba(255,255,255,0.65)`, `border-radius: 22px`, soft shadow (`0 10px 34px rgba(20,40,70,0.16)`).
  - Chips (hour cards, day cards, stat chips, log rows): the same frosted language at a lighter surface (`rgba(255,255,255,0.55)`), `border-radius: 16px`.
  - Ink: dark blue-grey (`#0d1420` primary, `#3b4a5c` secondary, `#5f7086` muted) — never pure black, it reads flat against the glass.
  - Display/heading font: a geometric sans stack — `"Avenir Next", Avenir, "Century Gothic", Futura, sans-serif` — uppercase with slight letter-spacing for section headings; body stays system sans.
  - Accent: blue, `linear-gradient(135deg, #4facfe, #2a78d6)` for the primary action (Refresh button) and hero figure; chart series colors follow the validated categorical palette from the `dataviz` skill (`#2a78d6` slot 1, `#008300` slot 2, `#eda100` slot 3, `#e34948` slot 4, `#4a3aa7` slot 5) unchanged — the glass aesthetic is a chrome/card decision, not a data-color one. Give chart panels a more opaque inner surface (`rgba(255,255,255,0.72)`) than the outer card glass, so gridlines/axis text stay legible — don't let chart data sit directly on translucent glass.
  - Dark mode: derive a dark-glass variant using the same structure (dark translucent surface, lighter ink, same accent) rather than skipping dark mode — the artifact's reviewed "Vivid" option is a reasonable starting point for the dark-mode token values if a literal dark inversion of Glass looks muddy.

## Scope

### Chart library

Pick one: Recharts, Chart.js + react-chartjs-2, or Apache ECharts + its React wrapper. Recommendation: **Recharts** — smallest bundle/API surface for the chart types needed here (line/bar/area, tooltips, responsive containers), idiomatic React (components, not imperative canvas calls), good TypeScript support out of the box. Document the actual choice and reasoning in `docs/architecture.md`, even if you pick a different one.

### API client

`src/api/weatherApi.ts` — add typed functions for the Stage 3 endpoints (`getDaily`, `getDailyByDate`, `getStatisticsDaily`, `getStatisticsPeriod`, `getStatisticsAll`, `getCharts`). Confirm (and keep it true) that this file only ever calls `VITE_BACKEND_BASE_URL` — no other base URL is configurable or hardcoded.

### Hooks

`src/hooks/` — add `useDateRange` (manages selected range + presets), `useStatistics`, `useCharts`, alongside the existing `useWeather`.

### Components

- `StatusStrip` — sync-status chip, last-synced time, next-run time, log toggle, `RefreshControl` (the "Refresh now" button described above) — all in one persistent bar, not a modal or drawer.
- `SyncLogPanel` — the inline accordion that expands beneath `StatusStrip`, listing `GET /api/sync/history` results with a status chip (success/failed, icon + label, never color alone) and trigger-type label.
- `HourlyToday` — plain hour-card list (hour + temperature), horizontally scrollable, no chart.
- `ForecastStrip` — 10-day forecast day-cards (date, condition, high/low, precipitation chance, "predicted" label), horizontally scrollable, no chart.
- `HistoryOverlay` — opened via a button from the main page; contains its own `DateRangeSelector` (7/10/30/All) and a plain date-list (date + recorded avg/min/max), no chart. This is also the app's "table view" for accessibility purposes.
- `DateRangeSelector` — presets: Last 7 days, Last 10 days, Last 30 days, All available data (requests every stored date via `getCharts`/`getDaily` with no artificial limit), plus a manual date picker. Used in two places only: the Averages section and the History overlay — each keeps its own independent range state.
- `StatCards` — summary statistics for the Averages section's selected range (from Stage 3's period-statistics response).
- `AveragesCharts` — the only chart-bearing component: average temperature by day (with min/max band), average humidity by day, total precipitation by day, average/max wind speed, weather-condition distribution. All read from the Averages section's own range selection.
- Reuse/extend existing `DataStatus` for loading/empty/error/stale-data states, applied per-section (Today/Forecast/Averages/History overlay each have their own loading/empty/error state, since they load independently).

### Readability for long ranges

For "All available data" or 30+ day ranges in the Averages section (or the History overlay's list): responsive width, reduced X-axis tick frequency (charts) or virtualized/paginated scrolling (the plain lists), horizontal scroll or zoom as needed. No overlapping labels — verify visually.

## Out of scope

- No backend/fetcher changes (unless Stage 3's report flagged an endpoint rename the UI must adapt to — apply only that).
- No Docker/CI changes.

## Architecture rules (must hold)

- UI communicates only with `backend-service`. Grep `src/` for any URL other than `VITE_BACKEND_BASE_URL` before finishing — there should be none.
- UI never calls `fetcher-service`, Open-Meteo, or any internal endpoint (`/internal/*`) directly. The one path by which a user action reaches the Fetcher is `POST /api/sync/trigger` on the Backend — the UI calls that public endpoint, nothing else.
- Opening or refreshing the browser page (F5, navigating to the app) never triggers a synchronization — verify by watching `fetcher-service` logs while loading/reloading the UI and confirming no fetch happens outside its own schedule. Only an explicit click on "Refresh now" may cause one, and even then only via the Backend proxy above.
- Charts are not hardcoded to 10 days — verify by seeding 45+ days in the test database and confirming "All available data" renders all of them.

## Detailed tasks

1. Read the docs and inspect the current UI code as described above — in particular confirm `WeatherBackground` still works unmodified against whatever condition/theme data the Backend now returns.
2. Add the chosen chart library dependency (used only inside `AveragesCharts`).
3. Implement the API client functions, hooks, and components listed above, styled per the Visual design spec above (glass card tokens, geometric display font, blue accent).
4. Wire the Averages section's and History overlay's date-range selectors independently: selecting a preset or custom range in one must not affect the other's data.
5. Implement loading/empty/error/stale states for Today, Forecast, Averages, and the History overlay independently — each fetches on its own and can fail/be empty independently of the others.
6. Manually test in a browser: golden path (default view with all three sections populated), each Averages preset, a custom range, opening/closing the History overlay with each of its presets, an empty range, a backend-down error state, a stale-data warning (stop `fetcher-service`, wait past `WEATHER_DATA_MAX_AGE_MINUTES`, confirm the UI surfaces it), clicking Refresh now end-to-end, expanding/collapsing the inline sync log.
7. Write/port tests (below).
8. Update `README.md`, `docs/architecture.md`, `docs/project-status.md`, `docs/troubleshooting.md`.

## Testing requirements

Vitest + React Testing Library (existing convention). Cover: current weather rendering, Today/Forecast/Averages all rendering without any user interaction (they're visible immediately, not behind a click), the History overlay opening/closing and not rendering its content while closed, date-range selection in both the Averages section and the History overlay (all four presets + custom, independently), daily statistics rendering, period statistics rendering, forecast-strip rendering with a visible "predicted" indicator and no chart, `HourlyToday` rendering as a list with no chart, `AveragesCharts` rendering all five chart types, loading/empty/error state per section, stale-data warning, the refresh control's loading→success cycle (mock `POST /api/sync/trigger`), the inline sync log expanding/collapsing and rendering both success and failure entries, and explicit assertions that the API client/mocked fetch calls never target a fetcher or internal-sync URL directly (only `/api/sync/trigger` on the Backend).

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
