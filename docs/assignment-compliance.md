# Assignment 1 compliance

[Українська версія](assignment-compliance.uk.md)

This matrix compares the supplied `DevOps_Academy_Assignment_1.pdf` with the current Rateboard implementation. It describes implemented behavior, not intended future behavior.

| Assignment requirement | Status | Current implementation |
| --- | --- | --- |
| Three cooperating services | Implemented | Static UI, Python Backend/Proxy, Go API Fetcher |
| Relational database | Implemented | PostgreSQL 16 with a History-owned migration |
| UI communicates only with Backend | Implemented | Application data is requested from `http://127.0.0.1:8000/api/v1`; UI never calls providers, History, or PostgreSQL |
| Backend calls a public API | Implemented | CoinGecko for crypto and Frankfurter for fiat reference rates |
| Backend coordinates persistence | Implemented with scoped behavior | Explicit refreshes, collector cycles, and backfill are forwarded to API Fetcher; normal Overview/cached reads are not persisted |
| History owns persistence | Implemented | Only the Go service imports `pgx` and accesses `DATABASE_URL` at runtime |
| Store request timestamp | Implemented | `requested_at TIMESTAMPTZ` |
| Store requested entity/query | Implemented | Normalized `instrument_id`, base and quote codes |
| Store response data | Implemented | Price, daily change, market cap, rank, source and provider timestamp |
| Retrieve current data in UI | Implemented | Overview and comparison cards |
| Refresh displayed data | Implemented | Refresh rereads the latest PostgreSQL samples and preserves UI card/chart structure; public APIs are polled only by the collector |
| Save successful retrieved data | Partially implemented | Persistence is guaranteed for explicit refresh/collector/backfill paths, not for every normal read |
| History exposes stored data | Implemented | Internal list endpoint is proxied by Backend as `GET /api/v1/requests/history` |
| View stored data in UI | Implemented as charts | The `Історія` tab reads PostgreSQL observations through Backend/History; a separate request-row table is not implemented |
| Clear setup and run instructions | Implemented | `README.md`, `.env.example`, `scripts/start-all.sh` |
| Explain architecture and boundaries | Implemented | `docs/architecture.md`, `AGENTS.md`, defense guide |
| Avoid Docker/Kubernetes/CI/CD as main focus | Implemented | These are deliberately outside the repository |

## Historical data behavior

- The collector stores a new sample at every aligned five-minute boundary while Backend is running.
- The History tab reads only stored PostgreSQL observations. Period and graph step are separate: for example, one day with a 30-minute step.
- Backfill uses the providers' native historical granularity and cannot manufacture missing five-minute samples.

Charts use the same stored observation path as the list API, but present the data as aggregated time series.

## Recommended next compliance change

Add a small `Збережені запити` section that calls `GET /api/v1/requests/history`, supports instrument filtering and cursor pagination, and clearly labels source time versus request time. This closes the remaining visible UI requirement without changing service ownership.
