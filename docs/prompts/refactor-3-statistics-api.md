# Refactor Prompt 3 — Statistics API and Database Adjustments

## Role

You are a senior backend engineer implementing stage 3 of a 4-stage architecture refactor of SkyIvano. Work carefully, keep code simple and explainable, and do not exceed the scope of this stage.

## Project context

Read `docs/architecture.md` (as updated in Stages 1–2), `docs/project-status.md`, and `refactor-0-discovery-and-plan.md` before doing anything else. By now `backend-service` owns PostgreSQL directly (Stage 1) and receives normalized data from `fetcher-service` over HTTP (Stage 2). This stage adds the statistics/chart capability the UI needs for Stage 4 — none of it exists yet.

Inspect `backend-service/app/models/daily_weather.py` and `hourly_weather.py` before writing any code: the current `daily_weather` table has no `average_temperature`, `average_temperature_method`, `average_apparent_temperature`, `average_humidity`, or `average_cloud_cover` columns. These need a new Alembic migration — do not edit the existing initial-schema migration.

## Current stage

**Stage 3 of 4 — Statistics API and database adjustments.**

## Stage goal

`backend-service` can answer: what happened on one day, what happened over a date range, and what happened across all stored data — computed from PostgreSQL, using every matching date ever synced (not capped at 10 days). It also returns chart-ready time series.

## Scope

### Schema

New Alembic migration on `daily_weather` adding: `average_temperature`, `average_temperature_method` (enum/string: `"hourly"` or `"min_max_fallback"`), `average_apparent_temperature`, `average_humidity`, `average_wind_speed`, `average_cloud_cover`. Backfill existing rows using the fallback method (min+max)/2 where hourly data isn't available, hourly-derived average where it is.

### Persistence

- `app/services/persistence_service.py` — when upserting a daily record, calculate `average_temperature` from that date's hourly rows if enough exist (define and document the threshold, e.g. "at least 1 hourly record for the date"), else fall back to `(temperature_min + temperature_max) / 2` and set `average_temperature_method` accordingly. Apply the same approach to `average_apparent_temperature`. Do not silently blend both methods for the same field.

### Statistics

New `app/services/statistics_service.py`:
- `get_daily_statistics(db, date)` — average/min/max temperature, average apparent temperature, average humidity, total precipitation, average/max wind speed, average cloud cover, dominant weather condition for one day.
- `get_period_statistics(db, from_date, to_date)` — period bounds, number of available days, average temperature, average daily min/max, lowest/highest recorded temperature, average humidity, total + average daily precipitation, counts of rainy/snowy/clear/cloudy days (define the weather-code buckets used and document them), average/max wind speed, warmest/coldest day, most common weather condition. Must use every stored date in range, not just the most recent 10.
- `get_all_time_statistics(db)` — same shape as period statistics, spanning every stored date.
- Handle empty ranges (no data in range → explicit empty result, not an error) and invalid ranges (`from > to` → 400 with a clear message) explicitly — write tests for both.

### Charts

New `app/services/chart_service.py` (or extend `weather_query_service`): `get_chart_data(db, from_date, to_date)` returning the ordered time-series shape from the target design (temperature/humidity/precipitation/wind arrays keyed by date, plus a `period` summary block). Order strictly by date ascending.

### API

Add to `app/api/public_weather.py` (or split into `app/api/statistics.py` / `app/api/charts.py` if that reads cleaner — your call, but keep it consistent with the existing router style):

```
GET /api/weather/daily
GET /api/weather/daily/{date}
GET /api/weather/statistics/daily/{date}
GET /api/weather/statistics?from={date}&to={date}
GET /api/weather/statistics/all
GET /api/weather/charts?from={date}&to={date}
```

Decide whether these replace or sit alongside the existing `GET /api/weather/history` and `GET /api/weather/hourly` from Stage 1 — if you consolidate/rename anything the UI currently depends on, list the exact before/after endpoint names in your report so Stage 4 can update the UI client accordingly.

## Out of scope

- No UI changes yet (Stage 4 consumes these endpoints).
- No changes to `fetcher-service`.
- No changes to the internal sync contract from Stage 2.

## Architecture rules (must hold)

- All statistics/chart calculations happen in `backend-service` against PostgreSQL — nothing is computed client-side that could be computed reliably here.
- Period and all-time statistics use every matching stored date, never an implicit 10-day cap.
- The average-temperature calculation method used for a given day is reported in the API response wherever relevant, and never silently mixed within one response.

## Detailed tasks

1. Read the docs and inspect the current schema/services as described above.
2. Write and apply the Alembic migration; write the backfill logic (a one-off script or a `data migration` step — document which you chose and why).
3. Implement the persistence-time average calculation.
4. Implement `statistics_service.py` and `chart_service.py`.
5. Implement/extend the API routes.
6. Write tests (below).
7. Update `docs/project-status.md`, `docs/architecture.md` (§ database schema, § API contracts), `docs/troubleshooting.md`.

## Testing requirements

pytest against real PostgreSQL. Cover: daily average calculation via hourly data, daily average fallback to min/max, one-day statistics, period statistics using all matching stored dates (not just the latest 10), all-time statistics, empty date range, invalid date range (`from > to`), chart data ordering, chart data spanning more than 10 days (seed 30+ days and confirm all are returned, not truncated).

## Verification commands

```bash
cd backend-service
alembic upgrade head
uvicorn app.main:app --reload --port 8000
curl localhost:8000/api/weather/daily
curl "localhost:8000/api/weather/statistics?from=2026-07-01&to=2026-07-20"
curl localhost:8000/api/weather/statistics/all
curl "localhost:8000/api/weather/charts?from=2026-07-01&to=2026-07-20"
pytest
```

## Documentation updates

- `docs/architecture.md`: document the new schema columns, the average-temperature method rule, and every new/changed endpoint with example responses.
- `docs/project-status.md`: mark Stage 3 complete.
- `docs/troubleshooting.md`: real issues only.

## Acceptance criteria

- Charts can display more than 10 days when the database has more than 10 unique dates.
- Statistics endpoints work for one day, a selected period, and all available data.
- All tests pass.

## Required final report

- Summary of what was built
- Changed files (list)
- Exact endpoint before/after list if any existing endpoint was renamed or removed
- Tests executed and results
- Manual verification performed (commands + outcomes)
- Problems encountered
- Troubleshooting doc updates made
- Remaining work / anything deferred
- project-status.md updates made

## Stop condition

Do not start Stage 4. Stop after completing and reporting this stage.
