# Monitoring RabbitMQ, Redis, and the durable outbox

This documents what's collected automatically for the RabbitMQ/Redis/outbox
path introduced by the database-mode migration, what appears on the cloud
dashboards, and what still requires an operator to run an explicit inspection
command. No new monitoring platform was introduced; the implementation reuses
the existing CloudWatch/Ops Agent host-metrics convention and the existing
`/health` JSON-endpoint convention.

## Cloud dashboard layout

Each provider module creates one operational dashboard for its environment.
The dashboards compare hosts by signal instead of creating a CPU, memory,
disk, uptime/status, or network widget for every individual VM:

- A CPU widget contains one line for every EC2/GCE VM.
- Memory and disk widgets do the same when agent metrics are enabled.
- AWS status-check failures and GCP uptime each have one cross-VM widget.
- Received and sent network traffic use separate widgets because direction is
  operationally meaningful; each widget compares all VMs.
- Legends use the stable configuration/workload names such as `fetcher`,
  `history`, `ui`, `database`, and `bastion`. AWS assigns each name a stable
  explicit color across host charts. GCP uses one labelled data set per VM, so
  Cloud Monitoring renders distinct series colors in each comparison chart.
- HTTP 500 and all-5xx counters share one count widget. Synthetic success and
  duration remain separate because percentages and milliseconds should not
  share an axis.

The alert resources remain per VM and signal. Consolidating charts changes how
operators compare hosts; it does not merge alerts or make one VM's threshold
depend on another VM.

Managed PostgreSQL, RabbitMQ, Redis, and outbox health are not charted by this
change. The monitoring modules currently receive VM IDs and host/log metrics,
but no RDS/Cloud SQL identifiers or time-series feed for the application-level
RabbitMQ, Redis, or outbox fields. Their implemented visibility remains the
health and manual inspection paths below. Adding dashboard panels for them
requires collection first; putting unrelated placeholder or mixed-unit series
on the host charts would imply monitoring that does not exist.

## Automatically collected

**Outbox backlog** (Fetcher's `/health`, field `outbox`): `pending_count` and
`oldest_pending_seconds`, from a direct `COUNT(*)`/`MIN(created_at)` query
against `published_queue_events WHERE status = 'pending'` — the same table
and partial index (`ix_published_queue_events_pending`) the outbox dispatcher
itself uses. A growing `pending_count` or a large `oldest_pending_seconds`
means RabbitMQ publishing is falling behind (broker unreachable, publisher
confirms timing out, or the broker rejecting as unroutable). The field is
included in both `200` ready and `503` broker-not-ready responses. Fetcher's
readiness reflects the latest outbox publish or broker probe; the outbox query
itself is diagnostic and does not change that status. Its duration is bounded
by the configured RabbitMQ timeout. A query failure is logged with details and
reported as `{"outbox": {"error": "unavailable"}}`, without exposing a raw
database error in the HTTP response.

**Redis memory and persistence** (UI's `/health`, field `redis`):
`used_memory`/`used_memory_human`/`maxmemory`/`maxmemory_policy` from
`INFO memory`, and `aof_enabled`/`aof_last_write_status`/
`aof_last_bgrewrite_status`/`rdb_last_bgsave_status` from `INFO persistence`.
`aof_last_write_status`/`aof_last_bgrewrite_status` are the fields to watch —
anything other than `ok` means the last AOF write or background rewrite
failed, which `PING` (what `is_ready()` already checks) does not catch:
a Redis instance can answer `PING` successfully while its AOF is silently
failing to persist. Like the outbox field, a failed `INFO` call is reported
as `{"redis": {"error": "..."}}` rather than failing the health check —
readiness is still governed solely by `PING`.

Both fields are **pull-based JSON, not pushed metrics**: nothing currently
polls them on a schedule, graphs them, or alarms on a threshold. An operator
(or the existing smoke test / a manual `curl`) sees them on every `/health`
call. Wiring them into CloudWatch/Ops Agent as real collected metrics with
configurable alarm thresholds is deferred — see "Deliberately deferred"
below.

## Manual inspection only

**RabbitMQ queue depth and unacknowledged messages** — not automated.
Inspect directly on the VM configured as `rabbitmq.host_vm`:

```sh
docker compose --file /opt/oilscope/rabbitmq/compose.yaml exec rabbitmq \
  rabbitmqctl list_queues --vhost oilscope name messages_ready messages_unacknowledged
```

Substitute the deployment's actual `rabbitmq.vhost`. This lists all three
application queues (main, `.retry`, `.dead` — see
[`database-modes.md`](database-modes.md#4-reset-rabbitmq-and-redis--scoped-never-blanket)
for why those three exist) in one call. A growing `messages_ready` on the
main queue means History's consumer isn't keeping up or is down; a nonzero
`.dead` count means messages have exhausted `rabbitmq.max_attempts` and need
operator attention (they are not automatically replayed — see
"Distinguishing failure modes" below); a `.retry` count is normal and
expected to drain on its own as each message's TTL expires.

## Distinguishing failure modes

An operator seeing degraded behavior needs to know *where* to look before
touching anything. In order of what to check first:

1. **Is RabbitMQ itself reachable?** `docker compose --file
   /opt/oilscope/rabbitmq/compose.yaml exec rabbitmq rabbitmq-diagnostics -q
   check_running` on the History VM (the same check `rabbitmq.yml` waits on
   during deployment). If this fails, it's a broker outage — Fetcher's
   outbox will grow (`pending_count` climbing) and History's `/health` will
   report `503` (`rabbitmq_consumer` not ready), because both depend on it.
2. **Is PostgreSQL reachable?** Fetcher's outbox insert and History's
   observation insert both need it. A DB outage shows up as Fetcher's `/v1/fetch`
   failing and History's `/health` failing its `SELECT 1` — *not* as outbox
   backlog growth, since Fetcher can't even write the pending row in the
   first place. If RabbitMQ is healthy but History's `/health` still fails,
   check PostgreSQL, not the broker.
3. **Is the backlog delayed but draining, or stuck?** Compare
   `pending_count`/`oldest_pending_seconds` (Fetcher `/health`) against
   the RabbitMQ main-queue `messages_ready` count over a couple of minutes.
   Both climbing together and RabbitMQ is reachable (step 1 passed): the
   *broker* is accepting but something downstream (History's consumer) isn't
   keeping up. Only the outbox count climbing while RabbitMQ's queues stay
   near zero: publishing itself is failing before reaching the broker (check
   Fetcher's own logs/TLS config).
4. **Are retries exhausted?** A nonzero count on `<queue>.dead` (checked via
   the `rabbitmqctl list_queues` command above) means History's consumer
   attempted and failed a message `rabbitmq.max_attempts` times. This is not
   the same as a backlog — the main queue can be empty while `.dead` holds
   permanently failed messages. Inspect failed messages without consuming
   them (`rabbitmqctl` doesn't offer a peek by default; use the management
   UI's **Get messages** action with **Requeue** rather than **Ack**, so
   inspecting doesn't remove them) before deciding whether to fix and
   manually republish, or discard.
5. **Is Redis failing outright, or degrading?** UI's `/health` returning
   `503` on `sessions` means `PING` failed — a real Redis outage. UI's
   `/health` returning `200` with `redis.aof_last_write_status` or
   `redis.aof_last_bgrewrite_status` not `"ok"` means Redis is up and
   answering but silently failing to persist — sessions still work right
   now, but an unplanned restart could lose recent writes since the last
   successful AOF write. Treat the second case as urgent but not an
   immediate outage.

None of these commands consume or replay messages/data — they're all
read-only inspection. Do not run the RabbitMQ/Redis reset commands from
`database-modes.md` in response to any of the above; those are for a
database-mode switch or first cutover only, never for diagnosing a routine
failure.

## Deliberately deferred

Automated, alarmed collection of outbox backlog, RabbitMQ queue depth, and
Redis memory/persistence status through CloudWatch/Ops Agent (with
configurable thresholds in the `monitoring` JSON block, matching how
`cpu_threshold_percent`/`memory_threshold_percent`/`http_error_threshold`
already work) was **not** built in this pass. Reasons:

- No custom-application-metric convention exists anywhere in this repository
  today — `infrastructure/terraform/modules/{aws,gcp}/monitoring/agent.tf`
  only ever generates host `hostmetrics`/CloudWatch-Agent CPU/memory/disk
  metrics and tails one log file (`traefik-access.log`, UI VMs only).
  Building this properly means a new per-service log-shipping or
  metrics-push mechanism (a periodic script writing structured output that
  the agent tails, plus matching `agent.tf`/`alarms.tf`/`dashboard.tf`
  additions in *both* AWS and GCP monitoring modules, plus new
  `project-config.schema.json` threshold fields) — real, separate,
  cross-cloud infrastructure work, not a documentation or health-endpoint
  change.
- The pull-based `/health` fields added here already satisfy this step's own
  completion bar ("every listed signal has an implemented collection path or
  an explicit manual inspection command") without that additional
  infrastructure surface or its cost/complexity.
- Adding it would touch both AWS and GCP Terraform in a step that is
  otherwise local/documentation-only; per the project's execution
  boundaries, infrastructure changes of that size are better scoped and
  reviewed on their own rather than folded into an operational-visibility
  documentation pass.

If this is wanted later: extend `agent.tf` in both monitoring modules with a
role-keyed conditional for `rabbitmq.host_vm`/`redis.host_vm` (mirroring the
existing `ui_vms` pattern used for `traefik-access.log`), point it at a new
periodic script's output file, and add matching alarm/dashboard entries and
schema threshold fields.
