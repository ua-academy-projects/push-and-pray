# Weather microservices demo
<img width="1319" height="907" alt="image" src="https://github.com/user-attachments/assets/12061463-a05a-4172-814a-c4daad543c14" />


A small weather dashboard built from cooperating services: a UI, a backend/proxy, a
history service, PostgreSQL for persistence, Redis for UI sessions, and RabbitMQ for
asynchronous messaging between the backend and the history service.

Each service runs as a Docker container, and each container runs on its own Vagrant VM
bridged onto the home LAN, so every machine has a real address you can reach from a
phone or another laptop on the same router.

## Architecture

![Architecture](docs/architecture.svg)


| Service | Port | Role |
|---|---|---|
| `ui-service` | 80 | Static dashboard served by nginx; reverse-proxies `/api/*` to the backend |
| `backend-service` | 8000 | UI-facing API: sessions, city registration, history reads. Never calls the weather API |
| `fetcher-service` | 8002 | The only component that calls the public weather API; polls on its own clock and publishes to RabbitMQ |
| `history-service` | 8001 | Owns persistence: the history rows and the watch list. Consumes from RabbitMQ |
| `postgres` | 5432 | Relational store for the request history |
| `redis` | 6379 | Ephemeral UI session state (no user accounts, no business data) |
| `rabbitmq` | 5672 / 15672 | Durable `weather.events` queue + management UI |

### Rules the design follows

**No UI action ever triggers a call to the public API.** The monitored cities are fixed
by deployment configuration (`WATCHED_CITIES`), and the dashboard has no way to add,
remove or refresh one — it only reads what has already been collected. The fetcher
resolves those names to coordinates once at startup and then polls hourly on its own
clock.

**The history is append-only.** Rows are written by the history service straight from
the message queue. There is no delete or clear endpoint anywhere in the stack, so a
monitoring record cannot be rewritten from the UI.

**The UI talks only to the backend.** Every request from the browser goes to `/api/*`,
which nginx proxies to the backend. Nothing in the page addresses the fetcher, the
history service, the database, Redis or RabbitMQ.

**Writes are asynchronous, reads are synchronous.** The fetcher publishes each reading to
the durable `weather.events` queue instead of calling History over HTTP. History consumes
whenever it is alive — restart either side and RabbitMQ holds the message until the
consumer comes back. Reads (`/history/recent`, `/history/count`) stay plain HTTP, since a
queue is one-directional and RPC-over-AMQP would be overkill here.

**Duplicate readings are suppressed.** `MIN_RECORD_INTERVAL_SECONDS` (default 3000)
means two rows for the same city can never land closer than ~50 minutes apart, however
often the service restarts.

**Redis holds UI preferences only.** Session state is the chart period, the city filter,
the rows-per-page choice, and the featured city — never weather data. There is no
authentication and no user management; the session is an opaque cookie id with a sliding
30-day TTL.

## What the UI does

Open the dashboard and you get a live weather console. The page background is a gradient
sky that repaints to match the featured city's real conditions and time of day — daytime
blue, muted indigo at night, grey-blue for rain, darker violet for storms.

**Hero panel.** The featured city shown large: temperature, "feels like", a written
condition, and an animated scene that reflects the actual weather code — the sun rotates
its rays, the moon drifts among stars, rain falls from a cloud, lightning flashes during a
storm. Below it, four readouts: wind, humidity, pressure, PM2.5.

**City cards.** One card per watched city, with temperature, condition, a weather glyph,
and four air-quality bars (PM2.5, PM10, NO₂, O₃) coloured green/amber/red by threshold.
Click any card to feature it — the hero and the page sky follow, and the choice is saved
to your session.

**Fixed city set.** The dashboard monitors the cities named in `WATCHED_CITIES`
(Kyiv, Warsaw and Vilnius by default). There is no search box and no add/remove button:
changing the set is a deployment decision, not a user action.

**Temperature chart.** One line per monitored city, built from the stored history, with
a period selector (24 hours / 7 days / 30 days) and a city selector. Both persist across
refreshes.

**Collection log.** Every reading the fetcher has collected, newest first: id, timestamp,
city, temperature, humidity, NO₂, and upstream status. Filter by city, choose 20/50/100
rows, and page through the whole log with "Load more". The log is read-only.

**Session persistence.** Change the chart period, the filter, the row count, or the
featured city, then refresh the page — everything comes back exactly as you left it,
because the state lives in Redis keyed by your session cookie. Open the same URL in a
private window and you get an independent session with default settings.

## Repository layout

```
backend-service/    sessions + read-only history API (the UI's only counterpart)
fetcher-service/    the only service that calls the public weather API
history-service/    RabbitMQ consumer + persistence
ui-service/         nginx + dashboard

infra/
  scripts/
    install-docker.sh   Docker Engine + Compose v2, run on every VM
    deploy.sh           writes nothing, just brings one stack up
  postgres/docker-compose.yml   postgres + redis + rabbitmq
  history/docker-compose.yml
  backend/docker-compose.yml
  fetcher/docker-compose.yml
  ui/docker-compose.yml
```

Each VM owns exactly one compose file and brings up only its own containers —
there is no cluster-wide orchestration, and no Swarm. The `Vagrantfile` holds
no deployment logic: it computes LAN addresses, writes each service's `.env`
next to its compose file, and calls the scripts under `infra/`.

Containers publish their ports (`ports:`) rather than sharing the VM's network
namespace, so each service's surface is explicit in its compose file.

## Publishing images

Service images are built once on your machine and pushed to a registry; the VMs
only pull them. That keeps provisioning fast — nothing compiles five times over
— and means every VM runs a byte-identical image.

```bash
docker login
./infra/scripts/publish-images.sh          # tags as :latest
./infra/scripts/publish-images.sh v1.2.0   # or a specific version
```

Then provision. `IMAGE_TAG` selects which published tag the VMs pull:

```bash
sudo -E vagrant provision                        # :latest
IMAGE_TAG=v1.2.0 sudo -E vagrant provision       # a pinned version
```

Override the namespace with `REGISTRY_NAMESPACE` if you publish elsewhere.

## Running with Vagrant

### Prerequisites

- [Vagrant](https://www.vagrantup.com/)
- The `vagrant-qemu` plugin: `vagrant plugin install vagrant-qemu`
- QEMU: `brew install qemu`

### Configure your network first

The VMs take static addresses on your home subnet, so two values must match your router:

```ruby
BRIDGE_IFACE = ENV.fetch("VAGRANT_BRIDGE", "en0")       # your active adapter
LAN_PREFIX   = ENV.fetch("LAN_PREFIX", "192.168.88")    # FIRST THREE octets only
```

Find them with:

```bash
route get default | grep interface   # → the adapter, e.g. en0
ipconfig getifaddr en0               # → e.g. 192.168.88.15, so prefix is 192.168.88
```

Make sure the octets used below (`.50`–`.53`) fall **outside your router's DHCP pool**,
or you will eventually get an address conflict.

### Start the cluster

```bash
sudo -E OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES vagrant up --provider=qemu
```

Two things about that command:

- `sudo` is required because macOS's `vmnet` framework (which provides bridged
  networking) needs elevated privileges.
- `OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES` works around a crash where the Objective-C
  runtime — pulled in by `vmnet` — refuses to continue after QEMU's `-daemonize` calls
  `fork()`.

Override the network per-run if you need to:

```bash
LAN_PREFIX=192.168.1 VAGRANT_BRIDGE=en1 sudo -E OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES vagrant up --provider=qemu
```

### VM layout

All four machines are bridged onto the LAN, so these addresses answer from any device on
the router — not just from the host.

| VM | Containers | IP | SSH port |
|---|---|---|---|
| `postgres` | postgres, redis, rabbitmq | `<prefix>.200` | 2222 |
| `history` | history-service | `<prefix>.201` | 2223 |
| `backend` | backend-service | `<prefix>.202` | 2224 |
| `fetcher` | fetcher-service | `<prefix>.203` | 2226 |
| `ui` | ui-service | `<prefix>.204` | 2225 |

Pick octets **outside your router's DHCP pool**. A device that already holds one of these
addresses will answer instead of the VM, and the symptom is confusing: the VM pings fine
from inside the LAN but refuses connections from the host.

Open the dashboard at `http://<prefix>.204` — including from your phone.

### Everyday commands

```bash
sudo -E vagrant status
sudo -E vagrant ssh backend -- 'docker ps'
sudo -E vagrant ssh history -- 'docker logs history --tail 20'
sudo -E vagrant provision ui        # rebuild one service after a push
sudo -E vagrant destroy -f
```

`sudo` is needed for these too: the QEMU processes belong to root, so an unprivileged
`vagrant` cannot even read their state.

### Adding another VM

Every machine is generated from one dictionary, so adding a service means adding an entry
to `NODES` in the `Vagrantfile` — a new octet, an SSH port, and the `docker run` line.
The `fetcher` VM was added exactly that way: one entry, no new config block.

> The provisioner clones this repo from GitHub (`REPO_BRANCH`), not from your working
> copy. Push your changes before running `vagrant provision`, or the VMs will rebuild the
> old code.

## Working on one service

Each stack can be rebuilt on its own VM without touching the others:

```bash
sudo -E vagrant provision backend        # re-clone, rebuild, restart
sudo -E vagrant ssh backend -- 'cd /opt/app/infra/backend && docker compose ps'
sudo -E vagrant ssh backend -- 'cd /opt/app/infra/backend && docker compose logs -f'
```

The provisioner clones this repo from GitHub (`REPO_BRANCH`), not from your
working copy — push before provisioning, or the VM rebuilds the old code.

## Key endpoints

Prepend `http://<prefix>.52:8000` for a direct backend call, or `http://<prefix>.53/api`
to go through the UI's nginx proxy (it strips the `/api/` prefix before forwarding).

**Fetcher** (`http://<prefix>.54:8002`)

- `GET /health` — what the fetcher has been doing: sweep count, last sweep time,
  cities seen. Observability only; it never triggers a fetch.

**Sessions**

- `GET /session` — bootstrap: ensures a session cookie and returns its saved UI state
- `GET /session/state` — read the stored preferences
- `PUT /session/state` — merge a patch into them
- `DELETE /session` — drop the state and issue a fresh session

**Cities and readings**

- `GET /cities` — the monitored cities (fixed configuration)
- `GET /latest` — latest stored reading per city
- `GET /latest?city=<city>` — latest stored reading for one city

**History** (read-only — there is no write or delete endpoint)

- `GET /history/recent?limit=<n>&offset=<n>` — paged history, newest first
- `GET /history/count` — total row count

## Verifying the stack

The fetcher reports its own activity:

```bash
curl -s http://<prefix>.203:8002/health
```

`sweeps_completed` climbs on its own schedule with nobody touching the UI, which is the
point: collection is driven by the fetcher's clock, not by user actions.

Readings only reach the database if the fetcher published to RabbitMQ, History consumed
the message, and PostgreSQL accepted the insert — so a growing count proves the whole
async path:

```bash
curl -s http://<prefix>.202:8000/history/count
```

RabbitMQ management UI at `http://<prefix>.50:15672` (`app` / `example`). Under
**Queues → weather.events** you should see `Consumers: 1` — that is the history service.

Resilience demo — the message survives a dead consumer:

```bash
sudo -E vagrant ssh history -- 'docker stop history'
curl -s -X POST "http://<prefix>.52:8000/cities?city=Poltava"
# management UI now shows Ready: 1, Consumers: 0 — the message is waiting
sudo -E vagrant ssh history -- 'docker start history'
sleep 5
curl -s "http://<prefix>.52:8000/history/recent?limit=1"   # Poltava is there
```

## Environment variables

| Variable | Service | Default | Purpose |
|---|---|---|---|
| `DATABASE_URL` | history | set by Vagrant/compose | PostgreSQL connection string |
| `RABBITMQ_URL` | history, fetcher | set by Vagrant/compose | AMQP broker URL |
| `WEATHER_EVENTS_QUEUE` | history, fetcher | `weather.events` | Queue name for the write path |
| `HISTORY_BASE` | backend | `http://history:8001` | Where the backend sends its HTTP reads |
| `REDIS_URL` | backend | `redis://postgres:6379/0` | Session store |
| `SESSION_TTL_SECONDS` | backend | `2592000` (30 days) | Sliding session lifetime |
| `POLL_INTERVAL_SECONDS` | fetcher | `3600` | How often the fetcher sweeps every city |
| `MIN_RECORD_INTERVAL_SECONDS` | fetcher | `3000` | Minimum gap between two stored readings for one city |
| `WATCHED_CITIES` | fetcher, backend | `Kyiv,Warsaw,Vilnius` | The monitored cities. Both services read the same list |
| `BACKEND_HOST` | ui | `backend` | Rendered into `nginx.conf` at container start via `envsubst` |

All of these are written by the Vagrant provisioner into
`infra/<service>/.env`, which Compose reads automatically. The compose
files themselves contain no addresses or credentials.

## Database inspection

```bash
psql -h <prefix>.50 -U postgres -d history_db -W    # password: example
```

```sql
SELECT id, event_time, query_params->>'city' AS city, response_status
FROM requests_history ORDER BY id DESC LIMIT 10;
```

## Notes

- Credentials here (`example`, `app`/`example`) are for local learning only — do not
  reuse them anywhere.
- The `ui-service` image renders `nginx.conf` from a template at startup, so the same
  image works under Compose (DNS name `backend`) and under Vagrant (a LAN IP).
