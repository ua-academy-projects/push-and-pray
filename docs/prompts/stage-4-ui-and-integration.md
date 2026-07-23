# Stage 4 Prompt — UI Service and Integration

## Role

You are a senior full-stack engineer implementing the final stage of a multi-service DevOps Academy assignment called SkyIvano. Work carefully, keep the code simple and explainable, and do not exceed the scope of this stage.

## Project context

SkyIvano is a weather dashboard for Ivano-Frankivsk. The UI Service is a React/TypeScript app that renders only data already persisted and served by the Backend Service — it never talks to Open-Meteo, the History Service, or PostgreSQL, and never triggers synchronization. Before doing anything else, read:

- `README.md`
- `docs/architecture.md` (technical source of truth — API contracts, UI behavior rules)
- `docs/implementation-plan.md` (this stage's work breakdown, under "Stage 4")
- `docs/project-status.md` (Stages 1–3 should already be complete)
- `docs/troubleshooting.md`

Then inspect the existing repository, especially the Backend's actual `/api/*` response shapes (`backend-service/app/schemas/`, `app/api/public_weather.py`) so the UI's types match reality, not just the docs.

## Current stage

**Stage 4 of 4 — UI Service and integration.**

## Stage goal

A polished, accessible, responsive weather dashboard that reads exclusively from the Backend's public API, plus a verified end-to-end local run of all three services together.

## Scope

- `src/api/weatherApi.ts` — thin client around `VITE_BACKEND_BASE_URL`, calling only `GET /api/weather`, `/api/weather/history`, `/api/weather/hourly`, `/api/sync-status`.
- `src/types/weather.ts` matching the Backend's actual response shapes.
- `src/utils/weatherCode.ts` — one centralized WMO weather-code → {description, icon, visual theme, background category} mapping. No weather-code `if` statements anywhere else.
- `src/utils/dateFormat.ts`, `src/utils/windDirection.ts`.
- `src/hooks/useWeather.ts` — fetch on mount; poll `GET /api/weather` on one clearly-named, easily-changeable interval constant (short enough — 60 seconds — that a successful scheduled sync shows up on-screen automatically within roughly one interval, with no push mechanism); expose loading/error/stale/data state. Keep a `reload()` function that repeats the same read (never calls the sync endpoint) implemented and exported, but **do not wire it to any visible UI control for now** — see the Header note below.
- Components: `Header` (logo, location, last sync time, fresh/stale status — **no reload button rendered**; leave the button's JSX and its `onClick={reload}` wiring in the file but commented out, with a one-line comment noting it's disabled pending a product decision, so it's a trivial one-line uncomment to bring back), `CurrentWeatherCard` (hero), `WeatherMetrics` (grid), `HourlyTimeline` (horizontally scrollable, highlight the current hour), `DailyHistory` (previous 10 days + today, clearly distinguishing today/yesterday/older), `DataStatus` (source, sync time, freshness, non-blocking stale warning, friendly no-data message), `WeatherBackground` (CSS-only gradients/shapes driven by weather theme + day/night, respecting `prefers-reduced-motion`).
- `src/App.tsx` composing everything with distinct loading/empty/stale/error states (not color-only).
- CSS: glassmorphism, gradients, rounded corners, spacious layout, responsive breakpoints, visible focus states, sufficient contrast.
- `tests/`: Vitest + React Testing Library.

## Out of scope

- No Backend or History Service code changes unless you find a genuine contract mismatch — if so, note it and fix the smaller side (usually the UI type), not both, and explain in your report.
- No Docker/CI.
- No location picker, no auth, no calls to any internal/sync endpoint from the UI.
- No heavy UI component library (no MUI/AntD).

## Architecture rules (must hold)

- The UI communicates only with the Backend's public `/api/*` endpoints.
- The UI never calls Open-Meteo, the History Service, or PostgreSQL, directly or indirectly.
- The UI never calls `/internal/weather/sync` or any other internal endpoint. There is currently no user-facing control that calls anything but `GET /api/weather` — a successful scheduled sync is expected to reach the screen via the next poll tick, not via a manual trigger.
- A normal page refresh reloads persisted data only; it does not and cannot trigger a sync (the UI has no code path that could).
- Polling interval must live in one clear, named constant — not scattered magic numbers.
- The "Reload displayed data" button is implemented but not rendered (commented out in `Header`) — see Scope. This is a deliberate, easily-reversible choice, not a removal of the feature.

## Detailed tasks

1. Read the docs and inspect the repo as described above.
2. Implement the API client, types, utils, hook, and all components listed in Scope.
3. Implement loading, empty (no data yet), stale-data-warning, and error states, each visually and textually distinct, using semantic HTML and ARIA where needed — no internal error details (stack traces, raw exception text) shown to the user.
4. Write tests: initial `GET /api/weather` call happens on mount and it's the only network call made; current-weather rendering; metrics rendering; hourly rendering; previous-10-days rendering; loading state; empty state; stale-data warning renders and is not color-only; failed initial load renders a friendly error state; polling re-fetches `/api/weather` on the configured interval and re-renders with the new data (and calls nothing else); the reload button is not present in the rendered output, but `reload()` itself (unit-tested directly on the hook, not through a UI click) still correctly re-fetches `/api/weather`; weather-code mapping unit tests; at least one responsive-layout assertion if practical.
5. Run all three services together locally and manually verify against the acceptance list below.
6. Update `docs/project-status.md` (final), `README.md` if any run command changed, `docs/troubleshooting.md` (real issues only).

## Testing requirements

Vitest + React Testing Library, with `fetch`/the API client mocked — no live backend required for the test suite itself.

## Verification commands

```bash
# with history-service (:8001) and backend-service (:8000) already running
cd ui-service
npm run dev
npm test
```

Manual end-to-end check: start all three services, load the page against an empty database (expect a friendly empty state), trigger one manual sync via `curl -X POST localhost:8000/internal/weather/sync`, then **wait for the UI's own poll interval to tick** (do not manually reload the page) and confirm live data appears on its own; then temporarily lower `WEATHER_DATA_MAX_AGE_MINUTES` on the Backend and wait for the next poll tick again (expect the stale warning to appear without the app looking broken).

## Documentation updates

- `docs/project-status.md`: mark Stage 4 items complete, mark overall project status.
- `README.md`: update if any command in "Running the services"/"Running tests" changed.
- `docs/troubleshooting.md`: real issues only.
- `docs/architecture.md`: update only if the final API contract diverged from what's documented.

## Acceptance criteria

- UI looks modern and polished (glassmorphism, gradients, dynamic day/night/weather theme), not a plain CRUD form.
- Current weather, metrics, hourly timeline, and previous-10-days sections all render from persisted Backend data.
- Stale data is clearly, non-blockingly marked; empty and error states are friendly and don't leak internal details.
- Responsive across common breakpoints; keyboard-accessible; visible focus states; no color-only status signaling.
- All UI tests pass, and the tests prove no request goes anywhere except the Backend's public API.
- Full stack (Postgres + History + Backend + UI) runs locally end-to-end successfully.

## Required final report

- Summary of what was built
- Changed files (list)
- Tests executed and results
- Manual verification performed (the full end-to-end check above, with outcomes)
- Problems encountered
- Troubleshooting doc updates made
- Remaining work / anything deferred
- project-status.md updates made (including final overall status)

## Stop condition

This is the last stage. Do not start unrelated new work (Docker, CI, deployment, etc.) — those remain explicitly future work per `docs/architecture.md` §13.
Stop after completing and reporting this stage.
