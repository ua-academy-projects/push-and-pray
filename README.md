# SkyIvano

A small multi-service weather dashboard for **Ivano-Frankivsk, Ukraine**, built as a DevOps Academy assignment. It demonstrates clean service boundaries, scheduled background synchronization, and relational persistence — without Docker, Kubernetes, CI/CD, or cloud deployment (that's future work, see [docs/architecture.md](docs/architecture.md)).

Weather data comes from the free [Open-Meteo](https://open-meteo.com/) API (no key/auth required).

The project was originally built as three services (UI, Backend, History) and has since been refactored into four (UI, Backend, a Weather Fetcher, PostgreSQL); the History Service no longer exists. See [docs/prompts/refactor-0-discovery-and-plan.md](docs/prompts/refactor-0-discovery-and-plan.md) for the full staged plan.

## Screenshots

<table>
<tr>
<td width="65%"><img src="docs/screenshots/dashboard-desktop.png" alt="SkyIvano dashboard on desktop: current weather hero, status strip, Today, Forecast, and Averages sections with charts" width="100%"></td>
<td width="35%"><img src="docs/screenshots/dashboard-mobile.png" alt="SkyIvano dashboard on a mobile viewport" width="100%"></td>
</tr>
</table>

## Architecture at a glance

```
Scheduled sync:  Fetcher Scheduler -> Weather Fetcher Service -> Open-Meteo -> Weather Fetcher Service -> Backend Service -> PostgreSQL
User reads:      Browser -> UI Service -> Backend Service -> PostgreSQL
Manual refresh:  Browser -> UI Service -> Backend Service -> Weather Fetcher Service -> Open-Meteo -> Weather Fetcher Service -> Backend Service -> PostgreSQL
```

Three independently runnable services, each with a single responsibility, plus PostgreSQL:

| Service | Responsibility |
|---|---|
| **ui-service** | React/TypeScript dashboard. Talks only to the Backend's public API. |
| **backend-service** | FastAPI. Owns PostgreSQL directly — persistence, upserts, sync-attempt bookkeeping, the public API. Never calls Open-Meteo; never calls the Fetcher except to proxy one manual-refresh action. |
| **fetcher-service** | FastAPI. The only service that calls Open-Meteo. Runs the sync scheduler independently of user traffic, normalizes the response, pushes it to the Backend over HTTP. Never touches PostgreSQL. |

The UI never calls Open-Meteo or the Fetcher directly, and never triggers a *scheduled* sync — it only ever reads data the Backend has already persisted, plus one explicit "Refresh now" action that still routes through the Backend. Full rules and diagrams: [docs/architecture.md](docs/architecture.md).

## Technology stack

- **UI**: React, TypeScript, Vite, CSS Modules, Recharts, Vitest + React Testing Library
- **Backend**: Python 3.12, FastAPI, Pydantic, httpx, SQLAlchemy 2, Alembic, PostgreSQL, pytest
- **Fetcher**: Python 3.12, FastAPI, Pydantic, httpx, APScheduler, pytest
- **Database**: PostgreSQL (no SQLite anywhere — including tests), owned exclusively by the Backend

## Local setup overview

Prerequisites: Python 3 (3.12 recommended; 3.14 also verified working with the `psycopg` v3 driver — see `docs/troubleshooting.md`), Node.js (LTS), and a local PostgreSQL instance.

PostgreSQL itself can be a native install or run in a plain Docker container purely as a local dev-database convenience — this does **not** make the project "use Docker": the three application services still run natively, and there is no Dockerfile/Compose file for them (see `docs/architecture.md` §14 for actual future containerization plans). The commands below use the container approach; swap in `createdb` if you have a native Postgres.

```bash
docker run -d --name skyivano-postgres \
  -e POSTGRES_USER=skyivano -e POSTGRES_PASSWORD=skyivano -e POSTGRES_DB=skyivano \
  -p 5432:5432 -v skyivano-pgdata:/var/lib/postgresql/data postgres:16
docker exec skyivano-postgres createdb -U skyivano skyivano_test
```

1. Databases created above (`skyivano` for dev, `skyivano_test` for tests).
2. Copy each service's `.env.example` to `.env` and adjust if needed.
3. Set up and run each service (see commands below).

Detailed setup, migrations, and environment variables: [docs/architecture.md](docs/architecture.md) and each service's own README.

## Running the services

Order doesn't strictly matter — `backend-service` serves stored data even with the Fetcher stopped (stale but not broken), and `fetcher-service` records a failed sync locally if the Backend is unreachable rather than crashing. For a fresh database, start the Backend first so its migrations run before the Fetcher's first push arrives.

**Backend Service**:
```bash
cd backend-service
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --reload --port 8000
```

**Weather Fetcher Service**:
```bash
cd fetcher-service
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8002
```

**UI Service**:
```bash
cd ui-service
npm install
npm run dev
```

Then open the UI (default `http://localhost:5173`).

## Running with Vagrant

An alternative to the native setup above: [`Vagrantfile`](Vagrantfile) brings up all four components (`postgres`, `backend`, `fetcher`, `ui`) as separate VMs under the QEMU provider (`vagrant-qemu` plugin — required on Apple Silicon, since VirtualBox's arm64 support isn't reliable). Every VM is bridged onto the same home-network LAN as the host Mac (and reachable from other devices on it, e.g. a phone), each with a fixed IP:

| VM | LAN IP | Port |
|---|---|---|
| postgres | 192.168.0.220 | 5432 |
| backend | 192.168.0.221 | 8000 |
| fetcher | 192.168.0.222 | 8002 |
| ui | 192.168.0.223 | 5173 |

Bridged networking (`vmnet_bridged`) needs root, and a separate macOS Objective-C runtime quirk (`+[NSNumber initialize] ... fork()`) crashes QEMU on some machines unless one extra environment variable is set. Always bring the environment up with:

```bash
sudo env OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES vagrant up
```

Use that same `sudo env OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` prefix for every other lifecycle command too (`reload`, `halt`, `destroy`, `status`, `ssh <name>`) — mixing sudo and non-sudo runs leaves root-owned files behind that break the non-sudo commands.

Once up, open `http://192.168.0.223:5173` from this Mac or any other device on the LAN — there's no `localhost` fallback, since the VMs have no forwarded ports, only the bridged LAN addresses above.

## Running tests

```bash
cd backend-service && DATABASE_URL=postgresql+psycopg://skyivano:skyivano@localhost:5432/skyivano_test pytest
cd fetcher-service && pytest
cd ui-service && npm test
```

Backend Service tests run against real PostgreSQL — point `DATABASE_URL` at `skyivano_test` before running them (the whole suite, not just persistence tests, refuses to run otherwise). Fetcher Service tests mock Open-Meteo and the Backend's HTTP client — no live network calls, no database.

## Documentation

- [docs/architecture.md](docs/architecture.md) — architecture, service boundaries, API contracts, database schema, sync/read/manual-refresh flows, decisions (source of truth)
- [docs/implementation-plan.md](docs/implementation-plan.md) — the original 4 build stages (pre-refactor)
- [docs/troubleshooting.md](docs/troubleshooting.md) — known issues and fixes
- [docs/project-status.md](docs/project-status.md) — current progress checklist
- [docs/prompts/](docs/prompts/) — self-contained AI-agent prompts, one per refactor stage

## Known limitations (v1)

- Single hardcoded location (Ivano-Frankivsk) — no location picker.
- Internal endpoints (`/internal/*`) have no authentication — see security notes in [docs/architecture.md](docs/architecture.md).
- No containerization, orchestration, or CI/CD yet.
- No system light/dark theme toggle — a deliberate choice, since the background already carries its own weather/day-night theming; see `docs/architecture.md` §15.
