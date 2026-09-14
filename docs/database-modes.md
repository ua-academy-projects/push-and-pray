# Database modes and coordinated cutover

## What `default_db` selects, and what it doesn't

`default_db` (`application` or `cloud`, required in every configuration)
selects **only where PostgreSQL runs**: the self-hosted container on
the database VM, or the managed RDS/Cloud SQL instance chosen by
`default_cloud`.

RabbitMQ (Fetcher-to-History messaging, on the History VM) and Redis (UI
session storage, on the UI VM) run in **both** database modes, on both
clouds. Switching `default_db` never provisions or removes them, and never
touches their data — see ["Database-mode switch, or the first cutover from
PGMQ/SQL sessions"](#database-mode-switch-or-the-first-cutover-from-pgmqsql-sessions)
below for what does.

## AWS RDS Free Tier

Cloud mode on AWS provisions a Free Tier-eligible RDS for PostgreSQL
configuration by design: a single Single-AZ `db.t4g.micro` (or `db.t3.micro`
where the engine/region requires it), 20 GiB General Purpose SSD (`gp2`), one
day of backup retention, no storage autoscaling, and no paid optional
features. The JSON schema restricts the AWS profile to these settings.
Terraform reads JSON directly and does not automatically run schema validation;
the database module has no equivalent profile preconditions. Validate the JSON
against the schema before deployment and review the actual Terraform plan.

**Free Tier eligibility does not guarantee a zero bill.** Before a live
deployment, verify the target AWS account's active Free Tier plan, remaining
credits, and expiration against the current
[AWS RDS Free Tier terms](https://aws.amazon.com/rds/free/) — new-account
offers are credit- and time-limited. RabbitMQ, Redis, the VM fleet, and every
other project service are ordinary paid compute; this requirement covers RDS
only, not the deployment as a whole.

## GCP Cloud SQL sizing

Cloud mode on GCP is not held to an equivalent Free Tier requirement — the
shipped `economy` profile (`db-f1-micro`-class `tier`, `ENTERPRISE` edition,
10 GiB `PD_SSD`, `ZONAL` availability, one retained backup) is a low-cost
*development* profile, not a promise of free Cloud SQL hosting or capacity
equivalent to the AWS Free Tier instance. Shared-core Cloud SQL tiers are
explicitly outside Google's Cloud SQL SLA. Unlike the AWS profile, nothing in
the schema or Terraform module enforces a cost ceiling on the GCP side — a
custom `database_profile` can select a much larger `tier`. Verify the
selected tier's actual pricing and regional availability against
[Cloud SQL instance settings](https://docs.cloud.google.com/sql/docs/postgres/instance-settings)
before a live deployment.

## VM sizing and single-host availability for RabbitMQ/Redis

RabbitMQ shares the History VM; Redis shares the UI VM, in both database
modes. `rabbitmq.memory_mb`/`redis.memory_mb` (plus `redis.maxmemory_mb`) in
the project JSON are ceilings on the *broker/cache container*, not the whole
VM — the History/UI application process and OS overhead still need their own
headroom on the same instance. With the shipped example's sizing (`history`
on `t3.small`/`e2-small`, ~2 GiB RAM, `rabbitmq.memory_mb: 768`; `ui` on
`t3.micro`/`e2-micro`, ~1 GiB RAM, `redis.memory_mb: 256`), that leaves
roughly 1.3 GiB for History plus OS, and roughly 750 MiB for UI plus OS.
These are illustrative, not a sizing guarantee — raise the VM's `size_map`
tier (and the corresponding `memory_mb`/`maxmemory_mb`) if the application or
broker/cache workload grows.

Neither RabbitMQ nor Redis runs with clustering or replication in this
architecture — each is a single Compose service on a single VM, by deliberate
scope decision, not an oversight. A History VM outage takes RabbitMQ down
with it: Fetcher's durable outbox keeps retrying until the broker returns, so
no observation is lost, but delivery stalls for the outage's duration. A UI
VM outage takes Redis down with it: new sessions cannot be created and
existing ones are unreachable until the VM returns. A highly available
broker/cache is out of scope for this project.

## TLS

Fetcher, History, and the migration connection all use `sslmode=verify-full`
with a mounted CA bundle in cloud mode — encryption alone is not the
requirement, the server's identity is actually verified.

- **AWS**: the RDS endpoint's own DNS hostname plus AWS's published CA
  bundle satisfy verification with no extra infrastructure.
- **GCP**: Cloud SQL private services access needs shared CA mode and a
  private DNS zone record matching the certificate's SAN — a per-instance
  certificate output is not a complete trust bundle on its own. Validate the
  pinned provider's exact shared-CA behavior during implementation rather
  than assuming it.

RabbitMQ connections between the Fetcher/History VMs are also
authenticated TLS with certificate verification and mounted trust material —
never a plaintext or unverified `amqp://` connection. UI-to-Redis stays
inside the UI host's private Docker network; add verified TLS if Redis is
ever moved to a separate host.

Nothing falls back to a previous database, PGMQ, PostgreSQL sessions, or a
different endpoint on connection failure — a missing or invalid value fails
the container start instead.

## Which procedure applies

Four things can happen to a running deployment. Only the last two discard
RabbitMQ/Redis state — get this classification right before doing anything:

| Situation | PostgreSQL replaced? | RabbitMQ/Redis reset? | Procedure |
| --- | --- | --- | --- |
| New image tag, config-only change, restarting a crashed service | No | No | [Routine redeploy](#routine-redeploy) |
| Standing up a new deployment from nothing | N/A (created fresh) | N/A (created fresh) | [Fresh deployment](#fresh-deployment) |
| `default_db` or the selected `database_profile` changes on an existing deployment | Yes | **Yes** | [Database-mode switch, or the first cutover](#database-mode-switch-or-the-first-cutover-from-pgmqsql-sessions) |
| An existing deployment still on PGMQ/PostgreSQL sessions moves to RabbitMQ/Redis, even with no `default_db` change | No | **Yes** (first-time creation, but nothing is migrated in) | Same procedure, "first cutover" case |

## Routine redeploy

A new image tag, a non-destructive config change, or restarting a crashed
service is **not** a cutover. `docker compose ... up -d` / `restart` on an
existing role preserves its named volumes — RabbitMQ's
`oilscope-rabbitmq-data`, Redis's `oilscope-redis-data`, and (in application
mode) PostgreSQL's own volume — and reconnects with the same credentials and
endpoints it already had. **Never run the reset commands below as part of a
routine redeploy**; they exist only for the two cutover cases in the table
above.

## Fresh deployment

1. Provision the selected PostgreSQL hosting, VMs, and private networking
   through Terraform; export a fresh `terraform output -json` for Ansible.
2. Bootstrap hosts and make the required secret versions available
   (`oilscope.platform.upload_secret_versions`).
3. Start RabbitMQ and Redis, configure credentials/topology, and verify them
   (`rabbitmq.yml`, and the `redis` role from `ui.yml`).
4. Initialize PostgreSQL and grants from the migration host using verified
   TLS (`migrate.yml`, cloud mode only — application mode's `database.yml`
   role does this in place).
5. Start History, then Fetcher, then UI, checking readiness at each stage
   before moving to the next.

In practice this is one run of
`infrastructure/ansible/deploy.sh oilscope.platform.deploy_workloads`, which
imports `database.yml` → `migrate.yml` → `rabbitmq.yml` → `history.yml` →
`fetcher.yml` → `ui.yml` (`ui.yml` also deploys Redis) in that order — see
[the platform README's "Deploy all workloads"](../infrastructure/ansible/oilscope/platform/README.md#deploy-all-workloads)
for the exact command.

## Database-mode switch, or the first cutover from PGMQ/SQL sessions

This applies in exactly the two cases from the table above — both discard
RabbitMQ/Redis state that a routine redeploy must never touch. Replace
`/absolute/path/project-config.json` and
`/absolute/path/terraform-outputs.json` with the real paths, and
`infrastructure/ansible/inventory/oilscope-aws.yml` with whichever inventory
matches `default_cloud`, exactly as in the platform README.

### 1. Stop the application, in order

Stop Fetcher first — it owns the outbox retry dispatcher, and stopping it
first guarantees no new observation gets published while History/UI come
down. Then History, then UI. Each role's Compose service uses `restart:
unless-stopped`, so `docker compose stop` (not `down`, which would also
remove the container) keeps it stopped until explicitly started again —
nothing needs disabling separately, and a host reboot mid-cutover won't
bring it back with obsolete settings.

Run on each VM (reached over SSH through the bastion — the same path
Ansible's `ProxyCommand` uses, see
[`infrastructure/ansible/inventory/README.md`](../infrastructure/ansible/inventory/README.md)):

```sh
# Fetcher VM
docker compose --env-file /opt/oilscope/app/deployment.env -f /opt/oilscope/app/compose.yaml stop fetcher

# History VM
docker compose --env-file /opt/oilscope/app/deployment.env -f /opt/oilscope/app/compose.yaml stop history

# UI VM
docker compose --env-file /opt/oilscope/app/deployment.env -f /opt/oilscope/app/compose.yaml stop ui
```

Confirm all three are stopped (`docker compose ... ps` shows no running
container for the role) before continuing — a still-running Fetcher would
keep publishing into the queues step 4 is about to reset.

**First cutover on an existing database only:** while the old PostgreSQL is
still running (i.e. before step 3 below replaces it), connect to it and
unschedule the retired cleanup job so it isn't left scheduled against a
table nothing will use:

```sql
SELECT cron.unschedule('delete-expired-ui-sessions');
```

See ["Retired PGMQ/pg_cron objects"](#retired-pgmqpg_cron-objects-on-an-existing-self-hosted-deployment)
below for why this isn't automated and what stays behind on purpose.

### 2. Apply the Terraform plan (database-mode switch only)

Review the plan — it should show only the previously selected database's
resources destroyed and the newly selected ones created, with nothing hidden
behind `lifecycle` suppression. Apply only in the separately authorized
deployment phase, then refresh the output file Ansible reads:

```sh
terraform -chdir=infrastructure/terraform apply
terraform -chdir=infrastructure/terraform output -json > /absolute/path/terraform-outputs.json
```

Skip this step for a first RabbitMQ/Redis cutover with no database-mode
change — PostgreSQL itself isn't being replaced, only RabbitMQ/Redis are new.

### 3. Initialize the replacement database

```sh
# cloud mode
infrastructure/ansible/deploy.sh oilscope.platform.migrate \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path=/absolute/path/project-config.json \
  -e terraform_outputs_path=/absolute/path/terraform-outputs.json

# application mode — database.yml does this in place, no separate migrate.yml run
infrastructure/ansible/deploy.sh oilscope.platform.database \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path=/absolute/path/project-config.json
```

No price or outbox data is transferred either way: switching back later
creates a fresh, empty database, not a restore.

### 4. Reset RabbitMQ and Redis — scoped, never blanket

Everything above must already be stopped (step 1) — a running Fetcher or
History would immediately refill what this step is about to clear. Unlike
PostgreSQL, RabbitMQ and Redis are **not** recreated by steps 2–3, so a
delayed-retry message or an in-flight session left over from before the
cutover could otherwise repopulate the fresh database's world view.

**RabbitMQ** — purge the three application-owned queues, derived from the
deployment's `rabbitmq.vhost`/`rabbitmq.queue` (main `<queue>`, retry
`<queue>.retry`, dead-letter `<queue>.dead` — see the `rabbitmq` role's
`definitions.json.j2` for where these three specifically come from).
**Purge `.dead` and `.retry` before the main queue**: the `.retry` queue's
`reliable-retry` policy forwards its messages back into the main queue once
their TTL (`rabbitmq.retry_delay_ms`) expires, independent of any consumer
being connected — purging main first could let a `.retry` message land back
in it seconds later.

```sh
# on the VM configured as rabbitmq.host_vm (the History VM in the shipped examples);
# substitute the deployment's actual rabbitmq.vhost/rabbitmq.queue for
# oilscope/price_observations below
docker compose --file /opt/oilscope/rabbitmq/compose.yaml exec rabbitmq \
  rabbitmqctl purge_queue -p oilscope price_observations.dead
docker compose --file /opt/oilscope/rabbitmq/compose.yaml exec rabbitmq \
  rabbitmqctl purge_queue -p oilscope price_observations.retry
docker compose --file /opt/oilscope/rabbitmq/compose.yaml exec rabbitmq \
  rabbitmqctl purge_queue -p oilscope price_observations
```

This purges only these three queues in this one vhost — never a
`rabbitmqctl` invocation that touches every vhost or every queue, since a
shared broker could host other applications' data.

**Redis** — delete only keys under this application's session key prefix
(`redis.key_prefix`, e.g. `oilscope:session:`) in its configured database
index (`redis.database`), never `FLUSHALL`. Sessions are stored as
`key_prefix + sha256(session_id)`, so a prefix scan reaches every session
this application created and nothing else:

```sh
# on the VM configured as redis.host_vm (the UI VM in the shipped examples);
# substitute the deployment's actual redis.database/redis.key_prefix below
docker compose --file /opt/oilscope/redis/compose.yaml exec redis sh -c '
  export REDISCLI_AUTH="$REDIS_PASSWORD"
  redis-cli -n 0 --scan --pattern "oilscope:session:*" | xargs -r redis-cli -n 0 DEL
'
```

`SCAN` (not `KEYS`) avoids blocking Redis with one long-running command on a
large keyspace; `xargs -r` no-ops cleanly when nothing matches.

### 5. Restart the application

Re-run the History, Fetcher, and UI playbooks so their Compose files pick up
the refreshed `database_connection`/`broker_connection` facts and, for a
mode switch, the new Terraform outputs — then confirm each role's `/health`
reports ready before starting the next:

```sh
infrastructure/ansible/deploy.sh oilscope.platform.history \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path=/absolute/path/project-config.json \
  -e terraform_outputs_path=/absolute/path/terraform-outputs.json   # cloud mode only

infrastructure/ansible/deploy.sh oilscope.platform.fetcher \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path=/absolute/path/project-config.json \
  -e terraform_outputs_path=/absolute/path/terraform-outputs.json   # cloud mode only

infrastructure/ansible/deploy.sh oilscope.platform.ui \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path=/absolute/path/project-config.json
```

Each playbook run already waits for its own role's `/health` to report ready
before finishing, so `history` → `fetcher` → `ui` above already enforces the
dependency order (Fetcher needs RabbitMQ/History reachable; UI needs History
and its co-located Redis reachable). Once UI is up, run the existing smoke
test as a final end-to-end check spanning all three — its health URLs default
to `127.0.0.1`, matching a single-host Compose deployment, so point them at
each VM's actual address for a real multi-VM deployment:

```sh
UI_HEALTH_URL=http://<ui-vm>:80/health \
HISTORY_HEALTH_URL=http://<history-vm>:8001/health \
FETCHER_HEALTH_URL=http://<fetcher-vm>:8002/health \
infrastructure/docker/smoke-test.sh
```

Discarded events and sessions from this cutover are intentional — switching
back later creates fresh state on the old side too, never a restoration.

The outage spans from stopping producers (step 1) through every restarted
service passing its health check (step 5) — there is no dual-write or
blue-green path, since data migration between databases is explicitly out of
scope by design. Existing price observation rows are preserved throughout
unless PostgreSQL itself is the thing being replaced.

## If a cutover step fails

Leave the application stopped — do not restart services against a
half-completed switch. Diagnose the failed stage in place: resuming means
repeating that step, not starting over from step 1, unless the failure
itself left step 1's stopped state in doubt (check `docker compose ... ps`
on all three VMs again before resuming). Switching back to the previous
`default_db`/profile does not restore data, queue messages, or sessions
already discarded by completed steps — it creates fresh state on the old
side too, for the same reason step 3 doesn't transfer data forward.

## Retired PGMQ/pg_cron objects on an existing self-hosted deployment

Migrations 004 (PGMQ setup) and 007 (pg_cron session cleanup) were retired
to `database/migrations/retired/` and are no longer applied on a fresh
deployment. On a database that already ran them before this change, the
`pgmq` extension/queue, the `ui_sessions` table, and the `pg_cron` cleanup
job are **not** dropped automatically — dropping shared extensions with
`CASCADE` or blindly re-running retired migrations against a database in an
unknown state is riskier than leaving unused objects in place. Before
abandoning them: stop the old services and explicitly unschedule the named
`pg_cron` job first (`SELECT cron.unschedule('delete-expired-ui-sessions')`)
rather than just leaving it scheduled against a table nothing still uses.
Actually dropping the obsolete extension, queue, and table is a separate,
explicit cleanup step to perform once you've confirmed nothing else on that
instance depends on them — not something this migration set does for you.
