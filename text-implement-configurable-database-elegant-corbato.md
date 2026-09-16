# Configurable database hosting (`default_db`)

## Implementation progress (historical record)

The entries below describe work actually performed. The RabbitMQ/Redis decision
on 2026-09-14 supersedes earlier PGMQ, managed-queue, and PostgreSQL-session
targets. The local conversion and publisher timeout fix are implemented through
Step 11; operational completion is tracked in Steps 12–19 below.

### Step 1 — Database-mode schema setting (completed)

- Implemented: added optional `default_db` to root `properties` in
  `infrastructure/terraform/project-config.schema.json`, with string type,
  enum `application`/`cloud`, default annotation `application`, and a
  description of both modes.
- Decision: keep it out of root `required` so existing configurations remain
  valid. Leave `project-config.example.json` unchanged to demonstrate the
  omitted-setting case. Schema defaults are annotations; runtime fallback
  in Terraform/Ansible remains a later step.
- Validation: used the existing `.venv-ansible` Python environment and
  `jsonschema.Draft202012Validator` to validate the schema and five variants
  of the actual repository example: omitted, `application`, and `cloud`
  accepted; `rds` and null rejected specifically at `default_db`. All passed.
  `git diff --check` also passed. No persistent test file was added for this
  small schema-only step; broader configuration tests remain planned.
- Remaining: database profile schema, cross-field validation, configuration
  normalization, infrastructure, and application changes. Accepting `cloud`
  in the schema does not yet implement cloud deployment.

### Step 2 — Explicit database profiles (completed)

- Implemented: `database_profile`, `database_profile_map`, and reusable
  AWS/GCP profile definitions in the repository schema. Profile names use
  the existing dictionary naming convention; unknown fields are rejected.
- Decision: every supplied provider field is required and has no default.
  This supersedes earlier profile-default proposals. Removed the
  `default_db` schema annotation added in step 1; legacy omitted-mode
  behavior remains a later runtime compatibility requirement. Existing
  unrelated VM/monitoring settings and SQL column defaults are unchanged.
- Updated `/Users/pavlo/Desktop/project-config.new.json` with an explicit
  `application` mode and selected `economy` profile: AWS `db.t4g.micro`,
  PostgreSQL `18`, `20` GiB `gp2`, autoscaling limit `0`, Single-AZ, and
  one-day backups. Retained the database VM; no deployment or switch ran.
  Initially only AWS settings were added; the follow-up below adds GCP.
- Validation: Draft 2020-12 schema check, full real-config and repository
  example validation, rejection of each missing required AWS/GCP field,
  rejection of an empty AWS entry, and absence of profile defaults passed
  using `.venv-ansible` and `jsonschema`. GCP shape validation used a fixture,
  not live Cloud SQL. `git diff --check` passed.
- Remaining for step 3: mode-dependent requirements and VM rules; dynamic
  selected-profile/provider lookup validation follows in runtime work.

### Step 2 follow-up — GCP economy mapping (completed)

- Added `database_profile_map.economy.gcp` to the real Desktop config:
  `tier: db-f1-micro`, `edition: ENTERPRISE`, `disk_size_gb: 10`,
  `disk_type: PD_SSD`, `disk_autoresize: false`,
  `database_version: POSTGRES_18`, `backup_retained_count: 1`, and
  `availability_type: ZONAL`. Active selection remains AWS/application.
- Extended the repository GCP profile schema with required edition, disk
  type, and autoresize fields, with no defaults. These make the economy
  settings explicit and prevent reliance on the PostgreSQL 18 default
  Enterprise Plus edition for a shared-core instance.
- Decision: this is a low-cost development profile, not a promise of free
  Cloud SQL hosting or an equivalent capacity to the AWS micro instance.
  Shared-core Cloud SQL instances are outside the Cloud SQL SLA.
  Reference: [Cloud SQL instance settings](https://docs.cloud.google.com/sql/docs/postgres/instance-settings).
- Validation: Draft 2020-12 schema validation, full real config and existing
  repository example validation, rejection of every missing required GCP
  field, and unchanged active mode assertions all passed. No deployment
  or live sizing/performance validation was performed.

### Step 3 — Database-mode configuration rules (completed)

- Implemented: a root `allOf` conditional in the repository schema. Cloud
  mode requires `database_profile` and `database_profile_map` and forbids
  database-role VMs. Application mode, including omitted `default_db`,
  requires at least one database-role VM.
- Decision: explicitly require `default_db` in the conditional's `if` so
  omission takes the application branch. Use a negated all-VMs-are-not-
  database rule to express existence in the VM dictionary, with an inline
  `$comment` explaining it. Profiles remain optional and may be retained
  in application mode; their presence does not select cloud hosting.
- Validation: checked schema validity and 15 configuration cases using
  `.venv-ansible` and `jsonschema.Draft202012Validator`: the real Desktop
  config and repository example, all three mode/omission cases with and
  without a database VM, each missing cloud profile setting, application
  mode without profiles, and invalid string/null/boolean/numeric modes.
  All passed with the expected acceptance or rejection; `git diff --check`
  passed. Fixtures were in-memory copies; no real configuration or live
  infrastructure was changed in this step.
- Remaining: selected-profile existence and selected-provider lookup must
  be validated in configuration-loading code. This step validates mode
  relationships, not dynamic dictionary references or cloud deployment.

### Step 4 — Custom profile lookup validation (skipped by decision)

- User decision: avoid additional validation complexity. Skip the proposed
  Ansible `resolve_database_profile()` helper and separate Terraform
  profile-lookup validation/preconditions. No helper was implemented.
- Resolve `database_profile_map[database_profile][default_cloud]` directly
  when wiring cloud database modules. Missing keys fail through the normal
  lookup error; do not introduce a fallback profile or default field values.
- Retain the schema validation rules completed in steps 1–3 and existing
  configuration-loading checks. This decision concerns additional custom
  profile lookup validation, not database connectivity or migration readiness.
- Next implementation step: database migrations and the durable outbox
  schema. Earlier progress entries describing lookup validation as pending
  are superseded by this decision.

### Step 5A — Outbox migration (implemented; database tests pending)

- Added `database/migrations/006_extend_published_queue_events_outbox.sql`
  with payload, delivery status, sent timestamp, next-attempt timestamp,
  and persisted attempt counter. Added the guarded pending-payload
  constraint and partial pending-row index inside a transaction.
- Decision: keep the migration in the existing flat directory for now so
  the current runner picks it up after migration 005. Move it to `common/`
  during step 5B together with the runner changes. The database Dockerfile
  already copies the entire migrations directory; no image definition or
  runner change is needed for 5A.
- Compatibility: nullable payload and `status DEFAULT 'sent'` preserve the
  current PGMQ publisher's event-key-only inserts. Cloud publishers must
  explicitly write a payload and `status = 'pending'`. SQL column defaults
  are distinct from the explicit-JSON-only infrastructure configuration.
- Validation: reviewed transaction boundaries, migration ordering, existing
  Dockerfile inclusion, and the constraint guard against migration 001's
  pattern; `git diff --check` passed. Runtime SQL tests were not run:
  Docker's daemon is unavailable and no local PostgreSQL server was found.
  Do not treat static review as proof of migration idempotency or constraints.
- Pending local database checks: apply 005 and 006 to an isolated database,
  apply 006 again, verify event-key-only inserts and pending-with-payload
  inserts succeed, and verify pending-without-payload inserts fail. No live
  database or cloud resource was modified.

### Step 5B — Migration profiles and runner (completed; SQL execution pending)

- Moved migrations 001, 002, 003, 005, and 006 into `database/migrations/common/`.
  Common 003 retains session storage, hstore, and pgcrypto; extracted its
  pg_cron extension/job setup into
  `application/007_schedule_ui_session_cleanup.sql`. Moved PGMQ migration
  004 unchanged into `application/`. Added `cloud/.gitkeep` for the empty
  cloud SQL profile. Dockerfile already copies the complete directory tree.
- Updated `migrate.sh` to run common SQL in filename order, followed by the
  selected profile's SQL. Omitted `MIGRATION_PROFILE` retains application
  behavior. Invalid profiles, missing directories, or missing required SQL
  fail early; an empty cloud profile is allowed. SQL errors stop execution.
- Decision: profile order takes precedence over global filename order;
  shared tables exist before queue and cleanup setup. Cloud pg_cron remains
  a future managed-initialization Ansible task, not part of these SQL files.
- Updated README local migration commands and profile documentation. Added
  `database/tests/test_migrate_runner.py` using standard-library unittest
  with stubbed `psql`/`pg_isready` and copies of the actual migration files.
- Validation: all five runner tests passed (default application ordering,
  cloud with empty profile, invalid profile, SQL failure stops execution,
  and missing common SQL); `sh -n` and `git diff --check` passed. Confirmed
  common SQL contains no pg_cron or PGMQ references. These tests do not
  execute SQL. Step 5A's live local PostgreSQL checks remain pending due to
  unavailable Docker daemon/local PostgreSQL; no deployment was performed.

### Step 6A.1 — Explicit AWS RDS network values (completed)

- Added `clouds.aws.rds_network` to the real Desktop configuration with
  `secondary_subnet_cidr: 10.10.2.0/24` and
  `secondary_availability_zone: eu-central-1b`.
- Decision: supply both values explicitly in JSON, with no defaults or
  automatic AZ selection. Network settings live outside sizing profiles.
- Extended the repository schema to accept the object, require both fields
  when supplied, and require the object in AWS cloud-database mode.
  Existing application-mode configurations may omit it.
- Validation: actual and example configurations passed Draft 2020-12
  validation; missing cloud-mode network settings and missing individual
  fields were rejected. Confirmed the new CIDR is inside the configured VPC,
  does not overlap either configured subnet, and uses a different configured
  AZ. These are local configuration checks, not AWS availability checks.
- Remaining: Terraform subnet, routing, and outputs in step 6A.2 onward.
  No infrastructure resources were created; active mode remains application.

### Step 6A.2–4 — AWS networking changes (completed; static validation passed)

- User added `rds_enabled`, the secondary subnet, its private route-table
  association, and VPC/subnet outputs.
- User choice: read `var.config.default_db` directly rather than using
  `try`. The real Desktop JSON sets this field explicitly. This removes
  omitted-setting compatibility at this module boundary; the repository
  example still omits it, so example/schema/runtime compatibility must be
  reconciled before declaring that requirement satisfied. No fallback was
  added during this review.
- Fixed the reviewed VPC-reference typo to `aws_vpc.main[0].id` and ran
  Terraform formatting on the network module. Kept the direct JSON lookup
  for `default_db` as requested.
- Validation: root `terraform validate -no-color` passed outside the sandbox
  so provider plugins could start. Network `terraform fmt -check` and
  `git diff --check` passed. These are static checks, not a cloud-mode plan
  test or AWS connectivity verification. No Terraform resources were applied.

### Step 6B.1 — AWS database module foundation (completed)

- Root `aws_database` now passes only `config` and `network`. The module
  selects `config.database_profile_map[config.database_profile].aws` into
  `local.settings` only when enabled, otherwise null. No separate settings
  input or root database-settings local is needed.
- Decision: provider database modules resolve their own profile from the
  already-supplied JSON. Keep network as an input because its resource IDs
  are outputs of a sibling module, not JSON configuration values. Preserve
  direct `default_db` access and do not add profile defaults or validators.
- Reviewed the user-created subnet group and RDS security group; removed a
  duplicate `aws_db_subnet_group.this` block. Network access is restricted
  to the configured PostgreSQL port from Fetcher, History, and UI groups.
- Validation: initialized the new local module with `-backend=false` and
  `-lockfile=readonly`, reusing installed providers. Root Terraform validate,
  formatting checks, and `git diff --check` passed. No plan/apply or live
  AWS checks were performed.
- Remaining: the actual RDS instance, parameter group, and connection/secret
  outputs in the next part. The foundation does not yet provision a database.

### Architecture revision — RabbitMQ/Redis instructions (completed)

- Updated this plan only, based on the user's new choice and inspected Git
  history. Replaced the active SQS/Pub/Sub and PostgreSQL-session instructions
  with RabbitMQ on History and Redis on UI in both database modes/providers.
- Retained completed-step history and database-profile/networking work.
  Kept the durable outbox for RabbitMQ delivery. Replaced future scheduler
  grants/readiness work with Redis TTL and added explicit queue/session reset
  rules because these services survive PostgreSQL replacement.
- Validation: checked active sections for obsolete managed-queue instructions
  and reviewed RabbitMQ confirms and Redis session documentation. Whitespace
  checks passed. No application, Terraform, schema, or real JSON changes were
  made in this revision; no service tests or deployment ran.

### Step 6B.2 — RDS instance and connection outputs (completed locally)

- Added the RDS PostgreSQL instance and parameter group to the AWS database
  module. Instance class, engine version, storage size/type/autoscaling,
  Multi-AZ, and backup retention come directly from the selected JSON profile;
  no fallback profile values were added. Application/GCP modes create no RDS
  resources and do not require AWS profile or network fields.
- Single-AZ instances use the configured workload availability zone. Multi-AZ
  omits that pin so AWS can manage placement. The existing two-subnet group
  supplies the network; the instance is private with encrypted storage.
- Decision: RDS creates `oil_tracker` and generates the `oil_tracker_admin`
  password in Secrets Manager. These names are fixed application contracts,
  not sizing defaults. Export only the secret ARN, never its password value.
  Runtime credentials and the restricted application role will be wired in a
  later Ansible step; applications must not reuse the administrator account.
- Added `rds.force_ssl=1` and connection metadata specifying `verify-full`
  and the AWS CA bundle URL. Ansible must still download/mount the CA and
  configure clients. No pg_cron parameter is added because Redis replaces
  PostgreSQL session expiry. The UI security-group rule remains temporarily
  until its existing PostgreSQL session implementation is replaced.
- Root `aws_database_connection` exposes the DNS host, port, database,
  administrator username/secret ARN, and TLS metadata, or null when disabled.
  DNS host is separate from port so client hostname verification can use it.
- Decision: automatic minor updates stay enabled; major upgrades require an
  explicit change. Deletion protection and final snapshots are disabled and
  automated backups are deleted, matching the agreed disposable database
  mode-switch policy. These settings do not implement the coordinated
  application shutdown/reset sequence by themselves.
- Validation: mocked Terraform plans cover AWS/cloud, application without an
  AWS profile, and GCP without AWS settings: all three passed. Root Terraform
  validation, formatting, and whitespace checks passed. No cloud resources
  are created; provider engine/
  class availability, Free Tier eligibility, connectivity, and real TLS are
  not established by mocks. Managed-secret costs also remain outside the
  database profile's Free Tier sizing target.
- Remaining: GCP networking/Cloud SQL, deployment credential/CA wiring, and
  RabbitMQ/Redis application conversion. This completes the AWS database
  resources, not an end-to-end cloud deployment.

### Step 6C — GCP database and private networking (implemented locally)

- Added `modules/gcp/database` with `config` and `network` inputs. Like AWS,
  it selects its own explicit JSON profile only in GCP/cloud mode. Added root
  `gcp_database` and `gcp_database_connection`; disabled output is null.
- Added private services access range/connection and API enablement in the
  GCP network module. The network output explicitly depends on the connection,
  preserving creation/destruction ordering across the module boundary.
- Added required GCP/cloud network schema settings and populated the real
  Desktop JSON with `allocated_cidr: 10.20.0.0/16` and `dns_ttl_seconds: 300`.
  No profile defaults were introduced; the selected cloud/mode stayed unchanged.
  The range does not overlap the configured subnets; external/VPN network
  allocations must also be considered before deployment.
- Cloud SQL uses the selected PostgreSQL 18 profile, private IP only, the
  configured primary zone, explicit backups, and no pg_cron. REGIONAL enables
  PITR to meet HA requirements; economy ZONAL leaves it off. Cloud SQL uses
  port 5432, so the schema requires that service port in GCP/cloud mode.
- Decision: use shared CA, encrypted-only connections, automatic server
  certificate rotation, and an exact-host private DNS zone. Select the PSA
  instance DNS name from `dns_names`, not the PSC/public `dns_name` field.
  Export Google's regional shared-CA bundle URL rather than assuming the
  instance CA output is a full trust chain. Client CA mounting remains pending.
- Decision: enforce client restrictions with VM egress rules because Cloud SQL
  does not reside in our VPC or accept VM ingress tags. Permit PostgreSQL from
  Fetcher/History/UI and deny other VM traffic to the dedicated reserved range.
  UI is transitional and will be removed when Redis sessions are implemented.
- Created the `oil_tracker` database, `oil_tracker_admin` account, and generated
  credential JSON in Secret Manager. Only the secret ID is exported; there are
  no workload grants for this administrator. Runtime role/grant and migration
  secret retrieval work remains in Ansible. Added the random provider to the
  lockfile. Unlike RDS's managed password, this password exists in Terraform
  state; documented this exception in `docs/secrets.md`.
- Decision: disable both deletion protections, final backup, and retained
  backups on deletion. Child database/user resources use ABANDON so active
  connections/ownership do not block instance teardown; instance deletion
  still removes the data. Project APIs remain enabled. PSA cleanup can require
  retry while Google releases service-side networking after instance deletion.
- Validation: provider initialization and root Terraform validation passed.
  Formatting, whitespace, and real JSON/schema checks also passed. No tests were
  added or run, following the user's decision; previously removed AWS tests
  are not restored. No cloud plan/apply or live connectivity checks were run.
- Remaining: Ansible connection/CA/admin-secret integration and restricted
  runtime roles, then the RabbitMQ/Redis deployment and application conversion.
  See `modules/gcp/database/README.md` for the implemented contract and sources.

### Step 7A — Ansible database connection and CA wiring (implemented locally)

- Added `database_connection` before the first `compose_project` role in the
  Fetcher, History, and UI playbooks. It reads explicit `default_db` from JSON;
  application mode resolves the inventory database host/configured port, while
  cloud mode reads the selected provider's connection output from a controller
  `terraform_outputs_path` file. Missing managed outputs fail instead of
  falling back. Operators must refresh the full `terraform output -json` file
  from the correct applied deployment; the role cannot detect every stale file.
- Added shared `oilscope_database_connection` and
  `oilscope_database_environment` facts. Service roles use these facts instead
  of directly indexing the database inventory group. The application database
  play now publishes the JSON PostgreSQL port to match the resolved endpoint.
- Decision: retain the current `oil_tracker` runtime user/database contract.
  Existing workload password resolution remains in place. This role does not
  fetch administrator passwords, grant roles, or run managed migrations.
- Managed mode requires `verify-full`, downloads the provider's public CA over
  verified HTTPS, and mounts the CA directory read-only in service containers.
  Active Compose templates require connection variables and explicitly pass
  `sslrootcert`. The CA checksum is a Compose label so a changed bundle triggers
  container recreation during normal reconciliation and reloads client trust.
  Application mode retains its existing non-TLS behavior and emits no CA mount.
- UI is wired temporarily because its current PostgreSQL session implementation
  remains active. Remove this wiring when Redis sessions replace it. PGMQ and
  current readiness checks still prevent claiming a complete managed deployment.
- Removed Fetcher's obsolete database-host/user/name fallback variables. Updated
  role/collection documentation with the output refresh command and new input.
  Standalone local Docker definitions and the unused combined deployment
  template remain separate from the three active Ansible service templates.
- Validation: local Ansible deployment-playbook syntax check passed using the
  source collection and a static localhost inventory. No remote tasks or tests
  were run. External documentation lookup was blocked by an automatic approval
  reviewer usage limit; verified CA download options with installed ansible-doc.
- Next: administrator-secret retrieval, restricted application roles, and
  managed-database migration integration, followed by RabbitMQ/Redis conversion.

### Step 7B–7D — Managed bootstrap, grants, and migrations (implemented locally)

- Added `migrate.yml`, imported between Database and History in the full
  deployment playbook. It skips application mode and runs on the first History
  host, with its own baseline, Docker, connection/CA, workload-secret, and
  registry prerequisites. Operators must include that host when limiting a
  bootstrap invocation. The existing application database migration flow stays.
- Added `database_migrate` and a separate `/opt/oilscope/migrate/compose.yaml`
  project, reusing the configured database image/runner with cloud profile.
  History's Compose definition is never overwritten. The image must be built
  with current SQL before deployment; no image was built/published in this step.
- Decision: retrieve administrator and runtime secrets on the controller using
  the operator's AWS CLI/gcloud credentials. This avoids permanent administrator
  secret grants to application VM identities. Operator read access (and KMS
  decrypt where applicable) is a prerequisite. The admin secret is passed to
  short-lived migration containers, not written in SQL/Compose files; tasks
  use no_log and clear credential facts on completion/failure.
- Decision: cloud mode uses per-VM `oil_tracker_<vm-key>` runtime logins and
  the VM's existing POSTGRES_PASSWORD mapping, allowing different passwords
  across workloads. Application mode retains its current oil_tracker login.
  Updated service URL construction to encode password characters safely.
- Bootstrap creates logins before migrations; the administrator applies schema
  changes and owns the new tables. Grants are applied afterward: Fetcher gets
  outbox DML, History observation DML, and UI temporary session-table DML. No
  runtime ownership, superuser, createdb, or createrole is granted. Added schema
  CREATE restriction and administrator default privileges; future tables need
  explicit grants. SQL uses quoted identifiers/literals via psql environment
  variables, so passwords are never templated into persistent SQL.
- Added deployment-time verification using each runtime login after grants.
  SQL errors halt deployment. Repeated runs replay idempotent migrations; no
  applied-migrations ledger or all-files transaction was introduced. Removed
  VM roles and externally granted memberships are not reconciled automatically.
- Step 7 infrastructure/deployment wiring is complete locally. RabbitMQ/Redis
  conversion, legacy migration cleanup, and coordinated cutover remain later
  steps. The current app's PGMQ and session readiness are still incompatible
  with the target managed architecture; do not claim end-to-end readiness.
- Validation: local deployment-playbook, changed YAML/Jinja syntax, and whitespace
  checks passed. No tests, live
  cloud reads, database commands, image publishing, or deployment were run.
  See database_migrate/README.md for prerequisites and credential boundaries.

### Step 8 — Reconciliation: fixes, stale docs, and the cutover runbook (completed locally)

Investigated the actual state of the RabbitMQ/Redis conversion before touching
anything: it was already functionally complete (Go outbox publisher with
confirms/mandatory-return/capped backoff, `RabbitMQConsumer` with manual ack
after commit and retry/dead-letter republishing, `RedisSessionStore` with an
atomic Lua sliding-TTL script), matching this document's own specifications
in "RabbitMQ publisher and durable outbox," "RabbitMQ consumer and retries,"
and "Redis UI sessions." What remained was items 5 and 6 from "Remaining
implementation steps" — reconciliation and the cutover runbook — plus several
concrete bugs found by direct investigation, not assumption.

**Fixed (existing broken things, not new work):**
- `services/fetcher/internal/config/config_test.go`: `TestLoadOilPriceAPIConfiguration`
  failed outright — the required `RABBITMQ_*` env vars were never added when
  those became required, and the test still asserted a stale `"PGMQ queue"`
  message. Added the env vars; did not add any new test function.
- `services/fetcher`: `go mod tidy` — `amqp091-go` was marked `// indirect`
  despite being imported directly in `internal/rabbitmq/publisher.go`.
- Removed the leftover empty `services/fetcher/internal/pgmq/` directory.
- `infrastructure/docker/smoke-test.sh`: the UI health check still asserted
  `"sessions":"postgresql"`; the endpoint returns `"sessions":"redis"` since
  the conversion. Fetcher/History's checks had already been updated correctly.
- `infrastructure/ansible/oilscope/platform/roles/broker_connection/tasks/main.yml`:
  added an explicit `assert` after resolving `oilscope_broker_host` — a
  `rabbitmq.host_vm` matching no discovered History host previously failed
  only implicitly (an undefined-variable error inside `delegate_to`), not
  with an actionable message, unlike every other host-resolution point in
  this codebase.
- `services/ui/frontend/src/App.tsx`: the architecture-diagram footer still
  read "PGMQ"; changed to "RabbitMQ." The compiled static bundle under
  `services/ui/backend/src/ui_service/static/assets/` still contains the old
  string — this machine's local frontend build is broken (missing native
  `@rolldown/binding-darwin-universal`, unrelated to this change) and
  couldn't regenerate it. The Docker build pipeline (`Dockerfile.ui`, its own
  `npm ci` in a clean container) is unaffected and will produce the correct
  bundle from the now-fixed source.
- `database/tests/test_migrate_runner.py`: two tests hardcoded stale literal
  migration-file counts (`7`, `5`) from before migrations 003/004/007 were
  retired; replaced with counts computed from the actual `common`/profile
  directory contents so they don't go stale again.
- Did **not** add any new test file or test function anywhere — the earlier
  explicit decision to decline automated tests stands. Only pre-existing,
  now-broken tests were repaired.

**Verified, no fix needed:**
- AWS RDS Free Tier constraints (`db.t4g.micro`/`db.t3.micro`, `engine_version`
  `"18"` via `const`, `allocated_storage_gb` `20` via `const`, `storage_type`
  `"gp2"` via `const`, `max_allocated_storage_gb` `0` via `const` to disable
  autoscaling, `multi_az` `false` via `const`, `backup_retention_days` `1` via
  `const`) are already fully enforced in `project-config.schema.json`'s
  `cloud_database_aws` definition — settings outside this configuration are
  schema-rejected, not silently substituted.
- **Corrected by the review below:** the outbox dispatcher implements fresh
  TLS connections per attempt, publisher
  confirms plus `NotifyReturn` check for unroutable messages, exponent capped
  before `power()` in the backoff calculation, `attempt_count` clamped
  against overflow. Its attempt timeout is not yet guaranteed after the AMQP
  handshake; the earlier claim that it matched the spec exactly was too strong.

**Reconciled (stale documentation, describing a state that no longer exists):**
Root `README.md`'s entire Architecture section (feature list, technology-stack
table, component table, data-flow steps, file-tree comments, "Vagrant
deployment" prose, local-development prerequisites, three services' `/health`
table rows, the `ui_sessions`/hstore/pgcrypto/pg_cron paragraph, and the
Configuration env-var table) still described PGMQ and PostgreSQL-backed UI
sessions throughout. Rewrote all of it to describe the outbox/RabbitMQ/Redis
architecture actually running, added the missing `RABBITMQ_*`/`REDIS_*` env
vars to the reference table, and added a cross-reference to the new cutover
runbook (below). Also fixed: `infrastructure/ansible/oilscope/platform/
CHANGELOG.md`'s stale "migrations remain pending" sentence directly
contradicting the entry above it, and the complete absence of any RabbitMQ/
Redis changelog entry; `roles/database_connection/README.md`'s claim that UI
still runs the role "temporarily" (it doesn't run it at all, UI moved to
Redis); `roles/database_migrate/README.md`'s claim that UI receives DML
grants on `ui_sessions` (it doesn't — `database_migrate_workloads` only ever
selected `fetcher`/`history`, confirmed against `files/grants.sql`) and its
claim that the operator needs UI's `POSTGRES_PASSWORD` secret (UI has none —
confirmed against the current example config's `secret_mappings`), and its
closing paragraph's "conversion remains pending" framing; `modules/gcp/
database/README.md`'s "temporarily UI... remove when it moves to Redis"
language, when the underlying `.tf` firewall rule had already dropped UI's
tag; `infrastructure/ansible/oilscope/platform/README.md`'s "Deploy all
workloads" order (missing `migrate.yml`/`rabbitmq.yml` entirely) and its
"Fetcher, History, and UI" database-connection claim (UI is excluded);
added a new "RabbitMQ and Redis deployment" section there documenting the
actual role/playbook wiring and ordering, verified against the playbooks
directly rather than restated from memory.

**New: `docs/database-modes.md`** — the coordinated-cutover runbook item 6
asked for. Covers: what `default_db` does and doesn't select (RabbitMQ/Redis
run in both modes, on both clouds, unaffected by the database choice); the
AWS Free Tier requirement and its "not a zero bill" caveat; the TLS
requirements per provider; the fresh-deployment sequence and the
database-mode-switch/first-cutover sequence verbatim from this document's
"Ansible and deployment ordering" section, including the explicit
scoped-reset requirement for RabbitMQ's queues and Redis's session
namespace (never a blanket broker purge or `FLUSHALL`) since — unlike
PostgreSQL — they now survive a database-mode switch and must be cleared
deliberately, not implicitly, to prevent a delayed retry from repopulating a
fresh database; and explicit guidance that retired PGMQ/pg_cron objects on
an already-deployed self-hosted database are not dropped automatically and
must be unscheduled/removed as a separate, deliberate step, consistent with
"Obsolete tables can remain unused until a separate explicit cleanup" above.

**Deliberately not done:**
- No migration drops the retired `ui_sessions` table, `pgmq` extension/queue,
  or `pg_cron` job on an already-deployed database — per this document's own
  instruction against blind extension/CASCADE drops. Documented the manual
  procedure in `docs/database-modes.md` instead of automating it.
- No CI job was added or restored to exercise RabbitMQ/Redis end-to-end (the
  old PGMQ integration job was deleted with nothing replacing it). Restoring
  or adding integration-test CI is automated-test work the user declined;
  left exactly as found.
- The local-dev Compose files (`infrastructure/docker/compose.*.yaml`,
  the legacy Vagrant topology) still have no `compose.rabbitmq.yaml`/
  `compose.redis.yaml` equivalent, so that path can't start a working stack
  in one command. Documented as a known gap in `README.md` rather than built —
  a real, separate scope of work (new Compose files plus Vagrant provisioning
  changes), not a stale-doc fix.
- **Flagging, not resolving**: `modules/gcp/database/locals.tf` and the AWS
  equivalent read `var.config.default_db` directly (a prior, explicit user
  choice in Step 6A.2–4, made to avoid `try()`). A config that omits
  `default_db` entirely — which the schema still permits, and which the
  original task explicitly required to "preserve existing behavior" — would
  make that specific attribute access fail at Terraform plan time, not
  gracefully resolve to `application` mode. The shipped example config now
  sets `default_db` explicitly, which sidesteps the symptom for that one
  file, but doesn't resolve the general promise for any config that omits
  it. This wasn't fixed here because reversing it would override an explicit
  prior decision without asking; it needs a decision, not a unilateral edit.

Validation actually run this step, with real output: `go build ./...`/`go vet
./...`/`go test ./...` in `services/fetcher` (all pass); `go mod tidy` (clean
diff, only the expected direct/indirect reclassification); `ruff check` on
`services/fetcher` (n/a, no Python), `services/history`, `services/ui/backend`,
`database/tests` (all pass); the existing Python test suite via `.venv/bin/
python -m pytest services/history services/ui/backend` (11/11 pass, unchanged);
`database/tests/test_migrate_runner.py` via `python3 -m unittest discover`
(5/5 pass, after the two count-literal fixes); `terraform validate` from
`infrastructure/terraform` (passes; no `.tf` files were changed this step, so
this only confirms the pre-existing state); the edited Ansible task file
parsed with `python3 -c "import yaml; yaml.safe_load(...)"` (valid). `uv` and
`yamllint`/`ansible-lint` are not installed in this environment — used the
project's existing `.venv` directly for Python instead, and did not run YAML
lint or Ansible lint/syntax-check. No `terraform apply`, cloud read, live
database command, image build/publish, or deployment was performed.

**Addendum**: also rewrote `docs/supported-compose-deployment.md`, which
described a `compose.deployment.yaml.j2` "canonical" combined-stack template
that no longer exists (`compose_project`'s templates directory now only has
one file per role — `compose.database.yaml.j2`, `.fetcher.`, `.history.`,
`.ui.` — RabbitMQ/Redis are separate roles/Compose projects entirely,
outside `compose_project`). Removed the now-fictional "complete stack on one
machine" section, fixed the required/optional settings tables (dropped
`PGMQ_*`, added the actual `RABBITMQ_*`/`REDIS_*`/`OUTBOX_*` variables read
directly from the current `compose.{fetcher,history,ui}.yaml.j2` sources,
not assumed), and cross-referenced the new RabbitMQ/Redis documentation
instead of duplicating it.

While checking `docs/vm-deployment-operations.md` for the same kind of
staleness, found something unrelated to this migration and did **not** fix
it: it describes a GCP cloud-init auto-deploy mechanism (`oilscope-deploy.
service`/`run.sh`, from `infrastructure/terraform/modules/gcp/vm/templates/`)
that sources its Compose file from `infrastructure/docker/compose.
deployment.yaml` — a file that has never existed in this repository, at
this session's start or at `HEAD` before it (confirmed via `git show HEAD`).
This predates the RabbitMQ/Redis work entirely and is a separate, real gap
in a different deployment path (VM self-deploy via cloud-init) from the one
this whole effort has been about (the Ansible-driven `compose_project`
path). Left `docs/vm-deployment-operations.md` untouched and did not
investigate further — flagging it here rather than silently leaving it
undiscovered, but fixing it is out of this step's scope.

### Step 9 — `default_db` made a required field (completed)

Resolved the decision flagged at the end of Step 8: `modules/aws/database/locals.tf`
and `modules/gcp/database/locals.tf` read `var.config.default_db` directly
(no `try()`), a deliberate Step 6A.2–4 choice, which conflicted with the
schema still treating `default_db` as optional and the original requirement
that omitting it preserve `application`-mode behavior.

- **User decision**: drop the omission-compatibility requirement rather than
  add `try(..., "application")` back into the two `locals.tf` files. Asked
  explicitly rather than picking unilaterally, per Step 8's own flag.
- Added `default_db` to the root `required` array in
  `infrastructure/terraform/project-config.schema.json`. No other schema
  change was needed: the existing `default_db` property definition (string
  enum `application`/`cloud`) already had no `default` annotation to remove,
  and the `allOf` conditionals that reference `default_db` inside their own
  `if.required` already degrade harmlessly now that it's always present.
  Updated the one `$comment` that referenced "omitted default_db" so it no
  longer describes a case the schema now rejects.
- `project-config.example.json` already sets `"default_db": "application"`
  explicitly (done before this step, per Step 8's note that "the shipped
  example config now sets `default_db` explicitly") — no change needed there.
- `docs/database-modes.md`: changed "defaulting to `application` when
  omitted" to "required in every configuration."
- This plan document: updated the forward-looking "Schema" and
  "Infrastructure and configuration" sections (not the historical step
  entries above, which stay as a record of what was actually decided at the
  time) to state that `default_db` is required and that the direct
  `var.config.default_db` access in both provider `locals.tf` files is
  therefore correct as written, closing out the Step 8 flag.
- Did not touch `modules/aws/database/locals.tf` or
  `modules/gcp/database/locals.tf` — their direct access was already
  correct for this decision; only the schema needed to catch up to it.
- Did not create `project-config.cloud-example.json` (still listed under
  "Example configs and docs (new files)" as not yet created) — out of scope
  for this specific decision; remains open.

Validation: `jsonschema.Draft202012Validator.check_schema()` on the updated
schema passed. Using `.venv-ansible`'s `jsonschema`: the repo example
validated as-is; a copy with `default_db` deleted was correctly rejected
with `'default_db' is a required property`; an AWS cloud-mode variant
(`default_db: "cloud"`, no database-role VM, `database_profile`/
`database_profile_map`/`clouds.aws.rds_network` populated) validated
successfully, confirming the required field doesn't break the cloud path.
`terraform validate -no-color` from `infrastructure/terraform` passed
(`Success! The configuration is valid.`) — expected, since no `.tf` file
changed. `git diff --check` passed on all edited files. No `terraform plan`/
`apply`, live config read, or deployment was performed.

### Step 10 — Removed the dead GCP cloud-init auto-deploy path (completed)

Followed up on the Step 8 flag about `docs/vm-deployment-operations.md`
referencing a nonexistent `compose.deployment.yaml`. Investigated instead of
assuming, and found the whole mechanism is dead, not merely referencing one
missing file:

- Searched the full git history of `infrastructure/terraform/modules/gcp/vm/main.tf`
  for any reference to `cloud-config`/`templatefile`/`user_data`/`startup-script`
  targeting the workload instance: none exists at any commit. Confirmed via
  `google_compute_instance.workload`'s current `main.tf` that only
  `enable-oslogin`/`ssh-keys` metadata is set — no `metadata_startup_script`.
  Only the separate bastion VM uses a startup script
  (`bastion-startup.sh.tftpl`, unrelated and kept). This means
  `cloud-config.yaml.tftpl` (and the `oilscope-deploy.service`/`run.sh`/
  `compose.deployment.yaml` it would have written to a workload VM) has never
  actually run on any provisioned VM, at any point in this repository's history
  — not a live path silently failing, but inert template content.
- `run.sh`'s own health checks were also stale relative to this migration:
  `"pgmq_consumer":"ready"`, `"delivery":"pgmq"`, `"sessions":"postgresql"` —
  none of which the application has emitted since the RabbitMQ/Redis
  conversion. Consistent with this being an abandoned first-generation
  deployment mechanism (PR #108 "vm deployment automation"), superseded by
  the Ansible `compose_project`/`database_connection`/`rabbitmq`/`redis` role
  stack that Steps 7A–8 confirmed is what actually deploys workloads today.
- User decision, asked explicitly rather than picked unilaterally: remove it.
- Removed `infrastructure/terraform/modules/gcp/vm/templates/cloud-config.yaml.tftpl`,
  `infrastructure/terraform/modules/gcp/vm/templates/run.sh`, and
  `docs/vm-deployment-operations.md` (the runbook for operating a mechanism
  nothing started). Removed the now-pointless "Validate cloud-init syntax"
  step from `.github/workflows/pr-validation.yml`'s `terraform` job, which ran
  `cloud-init schema` against the deleted template on every Terraform change.
  Removed a stale paragraph in
  `infrastructure/ansible/oilscope/platform/roles/compose_project/README.md`
  claiming `compose.deployment.yaml.j2` "remains temporarily as input to the
  legacy Terraform cloud-init path" — that `.j2` file was already deleted in
  the RabbitMQ/Redis reconciliation pass (Step 8's addendum), and the cloud-init
  path it described is now gone too, so the paragraph no longer had a referent
  in either direction. Confirmed via repo-wide grep that nothing else
  references `vm-deployment-operations`, `cloud-config.yaml.tftpl`,
  `templates/run.sh`, `oilscope-deploy`, or `AUTOMATION_ROLE`.
- `docs/supported-compose-deployment.md` needed no change: its only
  cross-reference to the removed doc was the one-directional link from
  `vm-deployment-operations.md` into it, not the reverse.
- Deliberately did not touch `bastion-startup.sh.tftpl` or its wiring — it is
  a live, actually-used mechanism for a different VM (the bastion), unrelated
  to this dead workload-deployment path.

Validation: `terraform validate -no-color` and `terraform fmt -check -recursive`
from `infrastructure/terraform` both passed after the deletions, confirming
nothing referenced the removed files. `.github/workflows/pr-validation.yml`
parsed successfully with `yaml.safe_load` after the edit. `git diff --check`
passed on all edited files. No CI run, `terraform plan`/`apply`, or live GCP
read was performed.

### Review after Steps 8–10 (2026-09-14)

Reviewed the current working tree and documentation; this is a review record,
not another completed implementation step.

- The required `default_db` schema field now matches direct Terraform access
  and the user's explicit no-defaults decision. Keep that decision.
- Removing the unused GCP workload cloud-init templates is consistent with
  the current VM module, which does not reference them. Keep the live bastion
  startup mechanism and the Ansible deployment path.
- **Next blocking fix: bound the entire RabbitMQ publish attempt.** In
  `services/fetcher/internal/rabbitmq/publisher.go`, the socket deadline is set
  in the dial callback. Inspection of the installed `amqp091-go@v1.10.0`
  source shows `Connection.openComplete()` clears it after the handshake.
  The same library explicitly ignores the context passed to
  `PublishWithDeferredConfirmWithContext`. Channel opening, queue inspection,
  confirm setup, writes, and deferred graceful closes therefore are not all
  bounded by the configured attempt timeout. A stalled broker can delay the
  dispatcher and shutdown. Preserve an owned transport and ensure deadline
  expiry or cancellation forcibly closes it throughout the attempt, including
  cleanup; retain the separate DB-bookkeeping budget for recording backoff.
  This fix was proposed by the review and subsequently implemented in Step 11.
- Corrected the RDS runbook's enforcement claim: profile restrictions exist
  in the JSON schema, but Terraform currently decodes JSON directly and the
  database module accepts `config` as `any`, without equivalent preconditions.
  Direct Terraform invocation does not automatically validate that schema.
  Do not claim guaranteed rejection or add extra validation without deciding
  how it fits the user's preference for minimal validation.
- The cutover runbook exists, but scoped reset instructions still need concrete
  operator commands and ordering. Local Compose dependency startup remains
  incomplete; frontend asset rebuilding remains recorded as outstanding.
- Corrected the active remaining-work list below so completed local work is
  not presented as unimplemented. Historical progress entries remain history.

Review checks: inspected application/deployment code and installed AMQP library
source; `git diff --check` and publisher `gofmt -l` were clean. No automated
tests, cloud deployment, or live state changes were performed. Earlier entries'
test results describe earlier work and were not re-run during this review.

### Step 11 — Bound RabbitMQ attempts and cancellation (completed locally)

Implemented the review's timeout fix in
`services/fetcher/internal/rabbitmq/publisher.go`:

- Each `send()` creates a child context using the existing configured
  `p.Timeout`. Parent cancellation and earlier parent deadlines propagate;
  no new configuration field or fallback default was introduced.
- TCP dialing uses that context. Once connected, `context.AfterFunc` closes
  the owned raw socket when the context expires or is cancelled. This remains
  effective even when AMQP clears socket deadlines and covers TLS/AMQP
  handshakes, channel setup, queue inspection, publishing, and cleanup.
- Cancellation remains armed while deferred channel and connection closes
  run. Final transport cleanup unregisters the callback and closes the socket,
  including when connection setup fails. A callback already running may also
  close the same socket; concurrent `net.Conn` closes are supported.
- Use `PublishWithDeferredConfirm` rather than the misleading context variant;
  the transport handles interruption, and confirmation waiting uses the broker
  child context. Publisher confirms and mandatory-return handling remain intact.
- Keep the existing outer transaction budget (`p.Timeout + 5 seconds`) for
  recording retry backoff after a broker timeout. Parent cancellation still
  rolls back unfinished DB work, leaving the event pending. An ambiguous send
  may be delivered again; closing the socket does not prove non-delivery.

Documentation lookup: resolved and queried `/rabbitmq/amqp091-go` through
Context7. Its current generated snippets describe context support, but the
installed, pinned v1.10.0 source explicitly ignores publish contexts and clears
deadlines in `openComplete()`. The implementation follows that pinned source.

Checks: `gofmt`, `go build ./...`, `go vet ./...`, and `git diff --check` passed.
No tests were added or run, per the user's instruction. No live broker failure
simulation or deployment was performed; runtime verification remains outstanding.

Next: finish concrete scoped cutover/reset commands and operational examples.

## Current architecture — RabbitMQ and Redis (2026-09-14)

**User decision:** use RabbitMQ for Fetcher-to-History messaging and Redis
for UI session/preferences storage, following the earlier local application
architecture. Do not implement SQS, Google Cloud Pub/Sub, or another
provider-native queue. This replaces the earlier cloud-mode-only queue
selection and the PostgreSQL session-store design.

Use RabbitMQ and Redis in **both database modes, on both AWS and GCP**.
`default_db` selects only PostgreSQL hosting: the application VM container or
RDS/Cloud SQL. It does not select messaging or session backends. PostgreSQL
stores price observations and the durable publishing outbox; Redis stores UI
sessions, and RabbitMQ transports observation events. UI continues obtaining
price data through History and no longer needs direct PostgreSQL access for
sessions. No data transfer between old and new stores is introduced.

The architecture revision initially changed instructions only. Steps 7–11
subsequently implemented the local conversion: active PGMQ/SQL-session adapters
were replaced and obsolete migrations retired. Existing deployed database
objects are not automatically dropped. No cloud resources were deployed or
destroyed by this work.

## Earlier implementation to reuse

Git history confirms a matching layout in the current service structure:

- Before `cc66239` (RabbitMQ to PGMQ replacement):
  `services/fetcher/internal/broker/publisher.go`,
  `services/history/src/history_service/messaging.py`, and
  `infrastructure/docker/compose.history.yaml`. RabbitMQ ran on the History
  VM with its own persistent volume. Historical topology names were
  vhost `oil_tracker`, exchange `oil.price.events`, queue
  `history.price-observations`, and routing key `prices.observed`.
- Before `9476d03` (Redis to PostgreSQL replacement):
  `services/ui/backend/src/ui_service/main.py` used `redis.asyncio` for JSON
  session preferences and sliding expiration;
  `infrastructure/docker/compose.ui.yaml` ran Redis alongside UI with AOF
  persistence and a dedicated volume.

Inspect these files with `git show <commit>^:<path>` during implementation.
Adapt the relevant code to today's message schema, session API, secrets,
Ansible deployment, and dependency versions. Do not revert entire commits:
that would discard intervening fixes. Historical image tags, exposed ports,
and credentials handling are references, not instructions to copy unchanged.

## AWS RDS Free Tier requirement

**User requirement: AWS cloud mode must target a Free Tier–eligible RDS
for PostgreSQL configuration.** Use a single Single-AZ `db.t4g.micro`
instance (or `db.t3.micro` if needed for supported engine/region
availability), 20 GiB of General Purpose SSD (`gp2`) storage, and the
existing one-day backup retention. Disable storage autoscaling and omit
paid optional database features. Do not silently substitute a larger
instance, Multi-AZ deployment, or additional storage. Validate PostgreSQL
18 availability for the selected micro instance in the target region.

Apply this requirement consistently to the AWS schema, cloud example, and
deployment review. The schema rejects unsupported profiles; direct Terraform
execution does not automatically validate it. Step 12 must document that
boundary. Do not add another validator or automated tests without a new user
decision, and do not silently substitute a more expensive RDS instance.

**Free Tier–eligible does not guarantee a zero bill.** Before a live
deployment, verify the account's active Free Tier plan, remaining credits,
expiration, and aggregate usage against the current
[AWS RDS Free Tier terms](https://aws.amazon.com/rds/free/). New-account
offers use credits and a Free plan lasting up to six months; the legacy
offer was limited to 12 months after signup. Do not describe the database
as free when the account is ineligible or its credits have expired or
been exhausted. The deployment documentation must distinguish RDS costs
from other project services, which are not made free by this requirement.

## Schema (`infrastructure/terraform/project-config.schema.json`)

Require `default_db` (enum `["application","cloud"]`, no schema default).
In cloud mode also require `database_profile` (a nonempty string selecting a
named profile) and
`database_profile_map` (a dictionary of profiles with provider-specific
`aws`/`gcp` entries). Keep database profiles separate from VM `size_map`
and `disk_type_map`: RDS classes and managed-database storage settings are
not VM settings. Group compute, storage, availability, and backup settings
in one profile so there is one source of database sizing configuration.

Example AWS cloud-mode fragment:

```json
{
  "default_db": "cloud",
  "database_profile": "economy",
  "database_profile_map": {
    "economy": {
      "aws": {
        "instance_class": "db.t4g.micro",
        "engine_version": "18",
        "allocated_storage_gb": 20,
        "storage_type": "gp2",
        "max_allocated_storage_gb": 0,
        "multi_az": false,
        "backup_retention_days": 1
      }
    }
  }
}
```

Resolve the selected settings as
`database_profile_map[database_profile][default_cloud]` in cloud mode.
Name the example profile `economy`, not `free`: account eligibility and
credits determine actual cost. A profile may contain either or both
providers; only the selected provider must be present. GCP settings do not
imply equivalent capacity, pricing, or Free Tier eligibility.

Use root `properties`, `$defs`, and `allOf`/`if-then` consistent with the
existing schema. Each profile rejects unknown properties and references
`$defs.cloud_database_aws`/`$defs.cloud_database_gcp` for its provider entries.
This replaces the previously proposed `databases.cloud` structure; do not
implement both structures or permit competing inline overrides.

All fields in each supplied provider entry are **required**, with no schema
or Terraform/Ansible fallback defaults. Values must come from JSON; even
fixed values must be written explicitly. Missing fields fail validation.

`$defs.cloud_database_aws`: `instance_class` is `db.t4g.micro` or
`db.t3.micro`; `engine_version` is `18`; `allocated_storage_gb` is `20`;
`storage_type` is `gp2`; `max_allocated_storage_gb` is `0`; `multi_az` is
`false`; `backup_retention_days` is `1`.

`$defs.cloud_database_gcp`: nonempty `tier`, `disk_size_gb` at least `10`,
`database_version` fixed at `POSTGRES_18`, `backup_retained_count` at least
`1`, and `availability_type` either `ZONAL` or `REGIONAL`. Also require
explicit `edition` (`ENTERPRISE` or `ENTERPRISE_PLUS`), `disk_type`
(`PD_SSD` or `PD_HDD`), and boolean `disk_autoresize`. Terraform must pass
these JSON values through rather than relying on provider defaults. Validate
edition/tier/storage compatibility during infrastructure implementation;
the economy shared-core tier requires `ENTERPRISE`.

**Current Step 9 decision:** `default_db` is now required in
every configuration (root `required`), not optional with an implied
`application` default. The real config explicitly sets `default_db` to
`application` while its database VM remains configured.

Root `allOf` additions:
- `default_db == "cloud"` ⇒ `database_profile` and a nonempty
  `database_profile_map` required, and no `vms.*` entry may
  have `role: "database"` (enforced via
  `"vms": { "additionalProperties": { "properties": { "role": { "not": { "const": "database" } } } } } }`,
  which composes correctly under `allOf` since every `vms` key must satisfy
  both this and the existing `$ref: "#/$defs/vm"`).
- `default_db != "cloud"` ⇒ `vms` must contain at least one
  `role: "database"` entry — this makes today's *implicit* requirement
  explicit, closing a gap the current schema leaves open.
- In cloud mode, directly look up the selected profile and `default_cloud`
  entry. Missing keys produce the normal lookup error. Per the step 4
  decision, add no custom lookup validator or separate precondition and
  never fall back to another profile.
- In application mode, profile settings are optional and unused; retaining
  a profile dictionary does not provision managed databases or queues.
- Validate the resolved AWS profile against the Free Tier configuration
  above regardless of its name. A custom profile name cannot bypass the
  instance, storage, backup, or Single-AZ restrictions.

This gives a clear, early rejection for unsupported/inconsistent
`default_db` values. Per the Step 9 decision, `default_db` is required
rather than optional, so there is no omitted-value case left to preserve.

## Example configs and docs (new files)

- `project-config.example.json` (repo root, **already exists** — leave its
  application-mode shape as-is; `default_db` is set explicitly to
  `"application"`, matching the now-required schema field) — no change
  needed beyond confirming it still validates
  against the updated schema.
- `project-config.cloud-example.json` (repo root, new, next to the existing
  file) — cloud mode, no `database`-role VM, `database_profile: "economy"`,
  with `database_profile_map.economy.{aws,gcp}` populated. Show all AWS
  settings explicitly as in the fragment above; document GCP's independent
  sizing and storage settings with no promise of free hosting.
- `docs/database-modes.md` (new) — the two modes (both on PostgreSQL 18),
  "switching destroys the old database, no migration, ever," deletion-
  protection/backup posture, downtime window, link to the deploy sequence
  below. Explain profile selection, provider lookup, required explicit values, and the
  distinction between a low-cost profile and account-specific Free Tier
  eligibility.
- `docs/secrets.md` — add a section on the new admin/app DB credentials and
  the AWS-vs-GCP Terraform-state asymmetry from decision 5 above.

## Infrastructure and configuration

Keep the implemented database profiles, explicit JSON settings, RDS Free Tier
constraints, second AWS subnet, and database module foundation. Each provider
module accepts `config` and `network`, and resolves its own selected profile
internally. No separate settings input or custom profile-lookup validator.
Honor the user's direct `default_db` access choice (Step 9): the schema now
requires `default_db`, so the direct `var.config.default_db` lookup in both
provider `locals.tf` files is correct as written and needs no `try()`. Do not
silently insert defaults for profile fields.

Complete RDS/Cloud SQL with PostgreSQL 18, private access, credentials,
application database creation, disposable deletion settings, and connection
outputs. Remove the previously planned pg_cron preload/instance flags and
special extension privileges: Redis expiration replaces database cleanup.
Do not create cloud queue Terraform modules, resources, service-agent grants,
queue endpoints, or SQS/Pub/Sub adapters and dependencies.

Host RabbitMQ in a dedicated Compose project on the existing History VM;
host Redis in a dedicated Compose project on the existing UI VM. This follows
the earlier co-location without provisioning dedicated broker/cache VMs or
managed RabbitMQ/Redis products. Separate project names, files, networks, and
volumes let migrations and app restarts run without overwriting service files
or deleting broker/session storage. If multiple History/UI VMs exist, choose
one host for each shared service explicitly in JSON rather than starting
independent brokers/session stores on every host.

Add explicit non-secret JSON settings and schema entries for RabbitMQ/Redis
placement, pinned images, service ports, RabbitMQ vhost/exchange/queue/routing
key and retry/dead-letter topology, Redis database/key prefix, session TTL,
and retry/timeouts/resource limits needed by the implementation. Reuse the
historical names above as explicit example values. Put passwords in existing
provider secret managers and reference them through workload secret mappings;
never put secret values in JSON or logs. Resolve hosts from inventory once in
Ansible, not from cloud-specific application code.

Expose RabbitMQ's client listener only on private networking to Fetcher and
History. Keep the management interface unpublished or reachable only through
restricted operator access. Redis should be reachable only by UI through a
shared Docker network on the UI host; do not publish port 6379 publicly.
Configure service users/permissions, RabbitMQ persistent storage, Redis AOF,
and explicit memory limits. A single host is not a highly available service;
instance sizes must accommodate these processes as well as History/UI.

RDS/Cloud SQL access should allow only the remaining database clients and the
migration host: Fetcher for the outbox and History for observations/migrations.
Remove the obsolete UI-to-PostgreSQL grant after UI moves to Redis. Preserve
unrelated responsibilities when removing the former database VM.

## TLS and connection contracts

Keep `sslmode=verify-full` with mounted CA bundles for Fetcher, History, and
migration connections. RDS uses its endpoint DNS name and AWS CA bundle.
For Cloud SQL private services access, use shared CA mode, its appropriate
trust chain, and private DNS matching the certificate SAN. Validate the pinned
provider's shared-CA output behavior during implementation instead of assuming
a per-instance certificate output is a complete shared trust bundle.

Use PostgreSQL host/port/database/credential-reference/TLS settings, RabbitMQ
URL and topology settings, and Redis URL/session settings as the application
contracts. Render them consistently through Ansible. Use authenticated TLS
for RabbitMQ connections between VMs, with certificate verification and
mounted trust material. UI-to-Redis may stay within its private Docker network;
if Redis is moved across hosts, add verified TLS for that connection too.
Remove the proposed `DATABASE_SCHEDULER_DB`/scheduler connection contract.
Do not fall back to PGMQ, PostgreSQL sessions, or a different endpoint on failure.

## RabbitMQ publisher and durable outbox

Keep migration 006 and apply the outbox to RabbitMQ publishing in both modes.
Changing the broker does not remove the database/broker dual-write problem.

- Preserve `Publisher` and the current observation event schema/event key.
  Adapt the historical Go RabbitMQ adapter using current client documentation.
- Insert event key, payload, and explicit `status='pending'` in one database
  transaction. The existing column default `sent` is legacy compatibility,
  not the cloud or RabbitMQ publisher's intended initial state.
- Publish persistent messages to declared durable topology with publisher
  confirms and mandatory routing. Mark the outbox row sent only after broker
  confirmation and no unroutable return; confirms alone can acknowledge an
  unroutable publish. Treat timeout, connection loss, negative confirmation,
  or return as pending/retryable. Broker acceptance is not consumer completion.
- Keep the independent retry ticker, bounded eligible batches, per-attempt
  timeouts, and persisted `next_attempt_at`/`attempt_count`. Cap the exponent
  before computing the backoff interval. Do not allow failed early rows to
  starve later events. Serialize dispatch per process or use row leases if
  multiple dispatchers run; duplicates remain possible and must be harmless.
- Preserve History's unique `(instrument_code, scheduled_for)` insert so
  redelivery or a lost publish-confirm response cannot duplicate observations.

Reference: [RabbitMQ publisher confirms and consumer acknowledgements](https://www.rabbitmq.com/docs/confirms).

## RabbitMQ consumer and retries

Adapt the earlier History RabbitMQ consumer while retaining the current
observation validation and repository transaction. Disable automatic ACK;
acknowledge only after the database commit. On lost ACK or connection failure,
redelivery must remain safe. Set explicit prefetch and connection timeouts,
reconnect cleanly, and make readiness reflect an active usable consumer.

Define bounded retries and an inspectable dead-letter queue explicitly.
Do not carry over SQS receive counts or Pub/Sub delivery-attempt assumptions.
Avoid endless immediate `nack(requeue=true)` loops. A concrete safe approach
is to republish transient failures with an incremented retry header to a
durable delayed-retry topology, and permanent/exhausted failures to a durable
failure queue. Confirm routing and broker acceptance before ACKing the source.
If the retry topology uses TTL/dead-letter forwarding, select a queue type
and at-least-once forwarding policy supported by the pinned RabbitMQ version;
ordinary dead-letter forwarding is not automatically lossless. If safe
forwarding cannot be provided, use an explicit confirmed delayed retry worker
instead. Keep this choice documented. Integration-test scenarios below are
reference only under the user's no-tests instruction.

Reference: [RabbitMQ dead-letter safety](https://www.rabbitmq.com/docs/dlx).

## Redis UI sessions

Replace `PostgreSQLSessionStore` with a Redis-backed implementation using the
current session-store interface and `SessionPreferences` validation. Reuse the
historical session API behavior, not the old PostgreSQL extension dependencies.

- Store preferences as JSON under a namespaced session key. Preserve opaque
  cookie IDs, cookie security attributes, and current invalid-cookie behavior.
  Hash the session ID in the storage key to preserve the current protection
  against exposing usable cookie tokens through stored session keys.
- Use native Redis expiration with the explicitly configured session TTL.
  Reads refresh sliding expiration; writes atomically replace the value and
  set its TTL. Missing/expired sessions yield default preferences; malformed
  stored values are handled consistently with the current API.
- Avoid a read/create race that overwrites a concurrent preference update:
  use atomic read-and-expire and conditional creation, or a small atomic
  script/transaction. Concurrent get/update verification remains a reference
scenario; no automated tests are authorized.
- Use authenticated connections with timeouts, close the client on shutdown,
  and report Redis/History availability through UI health checks. Redis
  failure must not be silently presented as a healthy empty session store.
- Remove UI database URLs, DB credentials, hstore registration, pgcrypto calls,
  pg_cron readiness queries, and the proposed two-database readiness fix.
  Redis handles expiration; no SQL session-cleanup job is needed.
- Keep AOF storage across ordinary redeploys. Document its restart/durability
  limits and explicit memory/eviction behavior. Database-mode switches reset
  session state deliberately as described below.

Reference: [Redis session storage and sliding TTL](https://redis.io/docs/latest/develop/use-cases/session-store/).

## Revised migrations and already-written code

The completed migrations are historical implementation work, not the final
new layout. Reconcile them as a separate implementation step:

- Keep observation migrations 001/002, published-event migration 005, and
  outbox migration 006 as common SQL for both modes.
- Remove migration 004 (PGMQ setup) and application 007 (pg_cron cleanup)
  from the active fresh-deployment path after the services move to RabbitMQ.
- Remove PostgreSQL UI-session migration 003 from the active fresh path.
  hstore/pgcrypto/pg_cron are no longer needed for UI; verify no remaining
  application SQL uses them before removing database-image packages.
- Simplify the application database image to pinned PostgreSQL 18 without
  PGMQ/pg_cron once dependency checks pass. Shared SQL is sufficient for fresh
  application and cloud databases. Retire empty profile branching if it no
  longer serves a purpose, and update runner tests and README accordingly.
- For an existing deployment, stop old services first and explicitly disable
  the old named cleanup job before abandoning SQL sessions. Do not blindly
  run old extension migrations against managed databases or drop shared
  extensions with CASCADE. Obsolete tables can remain unused until a separate
  explicit cleanup; no record copying or conversion into Redis/RabbitMQ.
- Preserve admin/runtime role separation and grants for observations/outbox.
  No special pg_cron administration or scheduler-database grants are needed.

## Ansible and deployment ordering

Add RabbitMQ and Redis deployment roles/playbooks using the current Docker,
registry, secrets, and monitoring conventions. Each carries its own fresh-host
prerequisites. Pin images through JSON; use dedicated Compose projects and
named volumes. Render migration Compose separately from all running services.

For a fresh deployment:

1. Provision selected PostgreSQL hosting, VMs, and private networking through
   Terraform; export fresh connection outputs for Ansible.
2. Bootstrap hosts and make the required secret versions available.
3. Start RabbitMQ and Redis, configure credentials/topology, and verify them.
4. Initialize PostgreSQL and grants from the migration host using verified TLS.
5. Start History, then Fetcher, then UI, checking readiness at each stage.

For a database-mode switch or first cutover from PGMQ/SQL sessions:

1. Stop Fetcher including the retry dispatcher, then History and UI; prevent
   automatic restarts from reconnecting with obsolete settings during cutover.
2. Review the destructive Terraform plan and apply it only in the separately
   authorized deployment phase. Refresh Terraform outputs afterward.
3. Initialize the replacement database. No price/outbox data is transferred.
4. Explicitly reset this application's RabbitMQ main, retry, and failure queues
   and Redis session namespace while clients are stopped. These services now
   survive database switches, so their data is NOT removed by deleting the old
   database. Prevent delayed/in-flight events from repopulating the fresh DB.
   Use a scoped reset or generation change; never blanket-purge a shared broker
   or issue Redis FLUSHALL. Do not reset sessions/queues on routine redeploys.
5. Render all new endpoints/credentials, verify dependencies, and restart
   History, Fetcher, then UI. Discarded events and sessions are intentional;
   switching back creates fresh state, not a restoration.

The outage spans stopped producers through passing application health checks.
For the first RabbitMQ/Redis cutover even without a DB mode change, old queue
messages and SQL sessions are not migrated. Preserve existing price rows unless
PostgreSQL itself is being replaced under the destructive-switch requirement.

## Monitoring and verification reference

The automated test scenarios below are retained as design reference only. The
user declined tests: do not add, restore, or run them as part of the remaining
steps. Use focused static checks and, after deployment authorization, ordinary
operational readiness checks. Fault injection and destructive rehearsals need
separate explicit authorization.

Replace PGMQ health assumptions with RabbitMQ connectivity/consumer readiness
and Redis session-store readiness. Monitor broker queue depth, unacknowledged
messages, retry/failure queues, outbox age, and Redis memory/persistence errors.
Remove local-PostgreSQL monitoring assumptions only where managed mode applies.

If automated testing is explicitly authorized in the future, the relevant
scenarios would replace the superseded SQS/Pub/Sub/pg_cron scenarios with:

- Local PostgreSQL + RabbitMQ integration tests for outbox commit/crash,
  ambiguous confirms, unroutable messages, broker restarts, consumer DB
  failure, commit-before-ACK, duplicate delivery, reconnect, retry fairness,
  delayed retries, and inspectable dead-letter handling.
- Redis tests for session creation/update, sliding TTL, expiry, invalid data,
  concurrent access, unavailable Redis, cookie compatibility, and restart
  behavior. Use short TTLs only in tests.
- Repeated migration and deployment checks and application/cloud mode cases
  on both providers. Verify no cloud queue resources are planned.
- Local certificate hostname-rejection tests. Real RDS/Cloud SQL private DNS,
  CA chain, IAM/secrets access, VM firewall rules, and destructive switching
  need a disposable-cloud rehearsal before live deployment.

Distinguish static checks and mocks from actual service integration tests.
The local Docker daemon was unavailable during step 5; its pending SQL checks
remain pending until a server can run. Do not mark them as passed by this rewrite.

## Remaining implementation steps

This is the authoritative remaining-work list as of 2026-09-14, following
completed Step 11. There were originally **eight planned steps (12–19)**: six
local implementation/preparation steps and two deployment-dependent steps.
Step 14 was declined by explicit user decision (see its entry below) and is
no longer part of this list's remaining scope. The optional cleanup item
afterward is not a prerequisite for completion. This update documents scope
only; none of these steps was executed by writing this list. Older
completed-step entries are historical records, not new tasks.

Already implemented locally: database hosting modules, explicit configuration
and schema, Ansible database connections/migrations and restricted roles,
RabbitMQ/Redis deployment roles, outbox publisher and consumer, Redis sessions,
retired migrations, and publisher timeout/cancellation. Do not reimplement them.

### Step 12 — Complete configuration examples and deployment contracts

**Status:** completed after review correction (2026-09-14).
**Depends on:** completed Steps 1–11.

**Work:**
- Add root `project-config.cloud-example.json` with explicit `default_db:
  "cloud"`, no database-role VM, and an `economy` profile containing both AWS
  and GCP entries. Retain required explicit application-mode settings in the
  existing example. Show provider selection without implying both databases
  are created at once.
- Include all required network allocations, broker/cache host mappings,
  resource limits, images, topology, TTL, and secret references. Use non-secret
  example values; keep actual passwords and provider keys outside JSON.
- Reconcile credential examples with the documented PostgreSQL password
  lifecycle: application mode uses a shared login/password; cloud mode uses
  managed admin credentials and explicitly supplied runtime secrets. Remove
  stale UI DB-password instructions and do not describe secret upload alone
  as a complete database password rotation.
- Reconcile `docs/database-modes.md`, `docs/secrets.md`, and
  `docs/supported-compose-deployment.md` with the actual playbook order and
  separate migration project. In particular, cloud migrations do not run from
  History's application Compose file. Document which values Ansible derives
  and which the operator must supply for manual/local startup.
- Explain AWS schema enforcement versus direct Terraform JSON loading. Keep
  profile values explicit and require review of the selected profile and plan;
  do not silently add defaults, larger instances, or another validation layer.
- Document VM memory headroom for co-located RabbitMQ/History and Redis/UI,
  single-host availability limits, and account-specific RDS cost eligibility.

**Complete when:** both examples pass a focused schema check, referenced hosts
and secret names are internally consistent, and each documented deployment
command targets the actual project/file. No cloud creation is needed.

**Progress (2026-09-14):**
- Added `project-config.cloud-example.json` (repo root): `default_cloud:
  "aws"`, `default_db: "cloud"`, `database_profile: "economy"`, no
  `database`-role VM (`bastion`/`history`/`fetcher`/`ui` only). Reused the
  existing example's VM/registry/network/RabbitMQ/Redis/monitoring shape so
  the two example files stay comparable side by side, rather than
  introducing a second, divergent topology.
- `database_profile_map.economy` includes both `aws` (the Free Tier consts:
  `db.t4g.micro`, engine `18`, 20 GiB `gp2`, no autoscaling, Single-AZ, 1-day
  backups) and `gcp` (`db-f1-micro`-class `tier`, `ENTERPRISE`, 10 GiB
  `PD_SSD`, `ZONAL`, 1 retained backup) — matching Step 2 follow-up's
  historical GCP economy values — to show provider selection without
  implying both databases are created by one apply (only the `aws` entry is
  actually resolved, since `default_cloud` is `"aws"`).
- Added `clouds.aws.rds_network` (`secondary_subnet_cidr: "10.0.2.0/24"`,
  `secondary_availability_zone: "eu-central-1b"`), required by the schema's
  `allOf` conditional for AWS cloud-database mode; confirmed the subnet is
  inside the example's `10.0.0.0/16` VPC and doesn't overlap the management
  (`10.0.0.0/29`) or workload (`10.0.1.0/26`) subnets.
- Gave `history` and `fetcher` distinct `POSTGRES_PASSWORD` secret mapping
  values (`oilscope-dev-history-db-password` /
  `oilscope-dev-fetcher-db-password`) instead of the application example's
  single shared `example-db-password`, to demonstrate the cloud-mode
  credential lifecycle Step 7B–7D and `docs/secrets.md` already document:
  per-VM `oil_tracker_<vm-key>` runtime logins with independent passwords,
  versus application mode's one shared `oil_tracker` login/password. `ui`
  keeps no PostgreSQL secret in either example — it has none since moving to
  Redis. RabbitMQ/Redis topology, ports, TTL, and resource limits are
  unchanged from the application example, matching "RabbitMQ/Redis run in
  both database modes" — nothing about them is cloud-mode-specific.
- Investigated `docs/secrets.md` before editing it: already reconciled with
  the cloud-mode admin/runtime credential separation (`oil_tracker_<vm-key>`
  logins, RDS-managed vs. GCP Terraform-state password asymmetry, the
  explicit "rotation requires updating both the secret and the database
  login" caveat) and already states UI needs no PostgreSQL password. No
  change was needed there.
- `docs/database-modes.md`'s "Fresh deployment" section already correctly
  scoped cloud-mode migrations to `migrate.yml`, separate from application
  mode's in-place `database.yml` role. Found and fixed two real gaps instead:
  - `docs/supported-compose-deployment.md`'s "Starting each role" command
    block showed the *same* `-f /opt/oilscope/app/compose.yaml run --rm
    migrate` command annotated "(application mode) or (cloud mode)" — but
    cloud-mode migration never runs from that path. Verified the actual
    path/project name in `roles/database_migrate/{tasks/main.yml,vars/main.yml}`
    (`/opt/oilscope/migrate/compose.yaml`, project `oilscope-migrate`, invoked
    by the role itself with transient controller-supplied credentials, not
    hand-typed). Split the doc into the real application-mode command and a
    reference-only cloud-mode command pair with a note that there is no
    supported manual invocation for cloud mode.
  - `docs/database-modes.md` had a dead internal cross-reference ("see
    'Resetting RabbitMQ/Redis' below") pointing at a section heading that
    doesn't exist (the actual content is under "Database-mode switch, or the
    first cutover from PGMQ/SQL sessions"). Fixed the link while already
    editing this file for the same step.
  - `docs/database-modes.md` had no GCP-specific cost/capacity caveat at
    all (only an AWS Free Tier section) despite Step 12's explicit ask.
    Added a "GCP Cloud SQL sizing" section stating the `economy` profile is
    a low-cost development profile, not free or AWS-equivalent capacity,
    and that nothing enforces a GCP cost ceiling the way AWS's schema
    `const` values do.
  - Added a new "VM sizing and single-host availability for RabbitMQ/Redis"
    section: `rabbitmq.memory_mb`/`redis.memory_mb`/`maxmemory_mb` bound the
    broker/cache *container*, not the whole VM; computed illustrative
    headroom from the shipped example's actual sizes (`history` on
    `t3.small`/`e2-small` ~2 GiB with a 768 MB RabbitMQ limit leaves ~1.3 GiB
    for History+OS; `ui` on `t3.micro`/`e2-micro` ~1 GiB with a 256 MB Redis
    limit leaves ~750 MiB for UI+OS); and documented that neither service
    is clustered/replicated, so a History or UI VM outage takes its
    co-located broker/cache down with it — a deliberate scope decision.
  - "Explain AWS schema enforcement versus direct Terraform JSON loading"
    was already present in `docs/database-modes.md`'s AWS Free Tier section
    (added by an edit outside this step) — confirmed accurate, no change
    needed.

Validation: `jsonschema.Draft202012Validator` accepted both
`project-config.example.json` and the new `project-config.cloud-example.json`
against the current schema (`VALID` for both). Confirmed `rds_network`'s
subnet placement arithmetically against the VPC/subnet CIDRs. Confirmed the
`database_migrate` role's actual Compose directory/project name by reading
its `tasks/main.yml`/`vars/main.yml` rather than assuming. Confirmed
`infrastructure/ansible/oilscope/platform/roles/database_migrate/README.md`
(the doc's new cross-reference target) exists. `git diff --check` passed on
all edited/added files. No `terraform plan`/`apply`, live config read, image
build, or deployment was performed — this step is example/documentation
reconciliation only, matching "No cloud creation is needed."

### Step 13 — Make coordinated cutover and scoped reset executable

**Status:** completed after review correction (2026-09-14).
**Depends on:** Step 12.

**Work:**
- Expand `docs/database-modes.md` with concrete commands or a narrowly scoped
  operator helper for stopping Fetcher and its dispatcher, then History, then
  UI. Show how stopped clients remain stopped throughout the switch.
- Distinguish a fresh deployment, a routine redeploy, a database-mode switch,
  and the first PGMQ/SQL-session cutover. Only the latter two deliberately
  discard queued/session state; routine redeploys retain named volumes.
- Derive the exact application vhost, main/retry/failure queue names, Redis
  database, and key namespace from the selected configuration. Specify a
  reset sequence that accounts for delayed and in-flight dead-letter
  forwarding; do not assume three independent queue purges are race-free.
  Choose and document scoped topology recreation or a generation strategy
  if needed. Never use a blanket broker purge or Redis `FLUSHALL`.
- Include fresh Terraform output export, replacement DB initialization,
  dependency verification, and History → Fetcher → UI restart order.
- For the first cutover on an existing DB, explain how to disable the old
  named cron job while the old extension-capable environment is still
  available. Preserve price rows when PostgreSQL is not being replaced.
- State the failure procedure: leave clients stopped, diagnose the failed
  stage, and resume deliberately. Switching back does not restore discarded
  data, queues, or sessions.

**Complete when:** the operator has an ordered, application-scoped procedure
with explicit targets, prerequisites, expected observations, and stop points.
Writing the procedure does not authorize running destructive commands.

**Progress (2026-09-14):** Rewrote `docs/database-modes.md`'s cutover section
from five prose bullets into a concrete, numbered, copy-pasteable procedure.

- Added a "Which procedure applies" table up front distinguishing routine
  redeploy / fresh deployment / database-mode switch / first PGMQ-SQL-session
  cutover, and a short "Routine redeploy" section stating explicitly that
  named volumes and credentials survive an ordinary `up -d`/`restart` — the
  reset commands must never run there.
- Derived the exact RabbitMQ topology from
  `infrastructure/ansible/oilscope/platform/roles/rabbitmq/templates/definitions.json.j2`
  instead of assuming names: main queue `<rabbitmq.queue>`, retry
  `<rabbitmq.queue>.retry`, dead-letter `<rabbitmq.queue>.dead`, all in
  `<rabbitmq.vhost>`. Found that `.retry` carries a `reliable-retry` policy
  that dead-letters expired messages back into the main exchange/queue at
  the broker level, independent of any connected consumer — so a purge that
  clears main before `.retry`/`.dead` could have a `.retry` message land
  back in main seconds later. Ordered the documented purge `.dead` →
  `.retry` → main specifically to close that race, and explained why in the
  doc rather than just asserting an order.
- Derived the exact Redis session-key shape from
  `services/ui/backend/src/ui_service/session_store.py`
  (`key_prefix + sha256(session_id).hexdigest()`) to justify why a
  `--scan --pattern "<key_prefix>*"` reset reaches every session this
  application created and nothing else, then documented it as a `SCAN`
  (non-blocking) + `xargs -r redis-cli DEL` pair scoped to `redis.database`,
  reusing the `REDISCLI_AUTH` env-var pattern already used by the `redis`
  role's own Compose healthcheck rather than inventing new redis-cli usage.
- Verified the exact Compose install paths/project names for both broker and
  cache by reading the `rabbitmq`/`redis` roles' `tasks/main.yml` directly
  (`/opt/oilscope/rabbitmq/compose.yaml`, `/opt/oilscope/redis/compose.yaml`,
  both using their in-file `name:` directive with no `--project-name` flag,
  matching those roles' own `docker compose` invocation style) rather than
  guessing a path.
- Verified the exact `database_migrate` role's cloud-mode migration
  Compose path/project (`/opt/oilscope/migrate/compose.yaml`, project
  `oilscope-migrate`) is different from the application Compose path, and
  used `infrastructure/ansible/deploy.sh oilscope.platform.<playbook>`
  (matching the platform README's own "Deploy all workloads" convention,
  confirmed each of `database.yml`/`migrate.yml`/`history.yml`/`fetcher.yml`/
  `ui.yml` is independently runnable — each starts with the same
  `import_playbook: preflight.yml` plus a standalone `hosts:` play, not just
  an import-only fragment) for the restart commands, rather than the FQCN
  guess used in an earlier draft of this entry.
- Added a "First cutover on an existing database only" sub-step placing the
  existing `SELECT cron.unschedule('delete-expired-ui-sessions')` command
  (already documented below, in "Retired PGMQ/pg_cron objects") at the
  correct point in the sequence — after stopping the application, before the
  replacement database exists — with a cross-link instead of duplicating the
  rationale.
- Added a "If a cutover step fails" section: leave the application stopped,
  diagnose in place, resume the failed step rather than restarting from
  step 1, and switching back does not restore already-discarded state.
- Fixed an unrelated dead internal cross-reference found while editing this
  file: the intro pointed at a "Resetting RabbitMQ/Redis" heading that has
  never existed; repointed it at the actual section.
- For the resolved `rabbitmqctl purge_queue`/`-p <vhost>` flag syntax: two
  `ctx7` queries against `/rabbitmq/rabbitmq-website` didn't return the exact
  reference page, but did return several confirmed real examples using
  `-p <vhost>` with other `rabbitmqctl` subcommands (`set_permissions`,
  `list_policies`), which is the same global vhost-scoping flag
  `purge_queue` documented elsewhere uses — used that confirmed convention
  rather than an unverified guess.

Deliberately did not write an executable script/role for this procedure —
the step's own "Complete when" only asks for a documented, copy-pasteable
procedure, and turning it into automation is a separate scope decision this
step doesn't make unilaterally.

Validation: confirmed every referenced file/path exists
(`infrastructure/ansible/deploy.sh`, the two inventory files, both role
`tasks/main.yml`/template files, `infrastructure/docker/smoke-test.sh`).
Confirmed `services/ui/backend/src/ui_service/session_store.py`'s actual key
construction and `infrastructure/ansible/oilscope/platform/roles/rabbitmq/templates/definitions.json.j2`'s
actual queue/policy definitions by reading them directly. `git diff --check`
passed. No command in the new procedure was executed against any real
broker/cache/database — this step is documentation only, consistent with
"Writing the procedure does not authorize running destructive commands."

### Step 14 — Restore a usable standalone local Compose workflow (declined by decision)

**Status:** declined (2026-09-14). Removed from the remaining-work scope.

**User decision:** explicitly declined this step. Do not add local RabbitMQ/
Redis Compose definitions, do not wire the database/History/Fetcher/UI
Compose files to them, and do not touch the Vagrant provisioning path. This
was asked about directly (not assumed) after Steps 12–13, and the user
answered "I don't need local compose at all" — repeated and reconfirmed here
as an explicit decision rather than an oversight.
- This leaves the local-dev Compose gap exactly as Step 8 already found and
  documented it: `infrastructure/docker/compose.*.yaml` and the legacy
  Vagrant topology still have no RabbitMQ/Redis service definitions, so
  that path cannot start a full working stack in one command.
- `README.md`'s "Vagrant deployment" section already states this plainly
  ("their Compose files have not been updated to start RabbitMQ or Redis
  alongside the application services... not part of the currently supported
  deployment path") without promising future work, so it needed no change
  for this decision — it was never claiming Step 14 as planned.
- Superseded work items 2 and 3 from the original "Concrete open items"
  list at the start of this engagement, which described this same gap
  before it was formalized as Step 14.
- If this decision is ever reversed, the original work items (local
  RabbitMQ/Redis Compose definitions reusing the Ansible topology, cert/
  network wiring, Vagrant support decision) are preserved in this entry's
  edit history via version control, not restated here.

### Step 15 — Rebuild and reconcile the frontend artifact

**Status:** completed after review correction (2026-09-14).
**Depends on:** existing frontend source
changes; can run independently of Steps 12–13 (Step 14 is declined, not a
dependency).

**Work:**
- Resolve the recorded local native dependency/binding installation problem
  using the existing package manifest and lockfile; avoid unrelated upgrades.
- Build the frontend and refresh tracked backend static assets according to
  the repository's artifact convention. Confirm the generated page references
  the new assets and displays RabbitMQ rather than the obsolete PGMQ label.
- Verify the UI Docker build still regenerates assets from source. Its
  existing frontend stage already does this; stale checked-in assets do not
  prove a freshly built container contains the same stale bundle.

**Complete when:** type checking/build succeeds, the served artifact matches
source, and any lockfile/artifact changes are explained in the progress entry.
If the build environment remains unavailable, record the blocker explicitly.

**Progress (2026-09-14):**
- The blocker was actually a stale/partial local `node_modules`, not a
  genuinely broken toolchain: `node_modules/@rolldown/` contained only
  `pluginutils`, missing the platform-specific
  `@rolldown/binding-darwin-arm64` native package (this machine is Apple
  Silicon; the earlier session's diagnosis said `-darwin-universal`, which
  turned out not to be an actual optional-dependency name in this lockfile —
  the runtime error message itself tries `-darwin-arm64` first, then falls
  back to `-darwin-universal` before failing, which is what produced that
  name in the earlier stack trace). `rm -rf node_modules && npm ci` against
  the existing, untouched `package-lock.json` installed the missing binding
  cleanly — no lockfile edit, no dependency upgrade, no `.npmrc` or registry
  change involved. `npm config get omit` was already empty (no optional-deps
  skip configured), so this was a corrupted local install state, not an
  environment/config problem.
- `npm run build` (`tsc --noEmit && vite build`) then succeeded: 2374 modules
  transformed, output written to
  `services/ui/backend/src/ui_service/static/`. `tsc --noEmit` passing means
  type checking is clean; no type errors were suppressed or worked around.
- Confirmed the rebuilt output: `grep -rl PGMQ` over the static directory
  returns nothing (clean); `grep -rl RabbitMQ` matches the new main bundle.
  `index.html` was regenerated referencing the new content-hashed filenames
  (`index-Bt6k_nLg.js`, `ChartPanel-COrsyPU7.js`); the old hashed files
  (`index-CyLDPGxW.js`, `ChartPanel-CRJOf61S.js`) are now `git`-deleted. The
  CSS file's hash didn't change (`index-B2DVAxdF.css`), consistent with the
  only source change being a text label, not styling.
- Verified `infrastructure/docker/Dockerfile.ui`'s `frontend` build stage
  independently: it does its own `COPY package.json package-lock.json` +
  `npm ci` + `COPY . ` + `npm run build` inside a clean
  `node:24.13.0-bookworm-slim` container, then copies only the built
  `static/` output into the final Python image — so it was never actually
  affected by this machine's local macOS binding gap (a Linux container
  resolves `@rolldown/binding-linux-*`, a completely different optional
  dependency, not the one that was missing here). Read the Dockerfile
  directly to confirm this rather than assuming Step 8's note was still
  accurate; did not run an actual `docker build` since the Docker daemon
  remains unavailable in this environment (checked with `docker info`,
  consistent with Step 5A/8's prior findings).
- `git status`/`git diff --stat` confirmed `package-lock.json` has zero diff
  after the reinstall — no unrelated upgrade was introduced, satisfying "no
  lockfile/artifact changes" beyond the expected regenerated static assets
  and `index.html`.

Validation: `npm ci` (clean, matched lockfile exactly), `npm run build`
(passed, includes `tsc --noEmit`), `grep` over the rebuilt static assets for
`PGMQ` (absent) and `RabbitMQ` (present), `git status`/`git diff --stat` on
the lockfile (no changes) and static directory (expected regeneration only),
manual read of `Dockerfile.ui`'s frontend stage. No `docker build` was run
(daemon unavailable); no test was added, per the standing no-new-tests
decision — `tsc --noEmit` and `vite build` are the project's existing build
checks, not new test coverage.

### Step 16 — Finish operational visibility for the new dependencies

**Status:** completed after review correction (2026-09-14).
**Depends on:** existing service adapters;
coordinate with Steps 12 and 14 (Step 14 is declined — nothing to coordinate).

**Work:**
- Trace current AWS/GCP dashboards, alarms, log collection, and service health
  checks against RabbitMQ/Redis behavior. Reuse working checks; remove only
  obsolete PGMQ/session-cleanup or self-hosted-DB assumptions.
- Account for the metrics already required by this plan: pending outbox count
  and oldest-event age; main/retry/failure queue depth and unacknowledged
  messages; Redis memory pressure and persistence errors. Document which are
  collected automatically and which require operator inspection.
- Add missing collection/visibility through existing monitoring conventions
  where needed. Keep collection endpoints private and credentials out of
  logs. Put new operator-selectable intervals/thresholds explicitly in JSON.
  Do not introduce a separate monitoring platform to close this gap.
- Document how an operator distinguishes broker outage, DB outage, delayed
  backlog, exhausted retries, and Redis failure, including where to inspect
  failure messages without replaying them automatically.

**Complete when:** every listed signal has an implemented collection path or
an explicit manual inspection command, with no claim that unimplemented
alarms already exist. Record any intentionally deferred automation.

**Progress (2026-09-14):**

Investigated the actual current monitoring surface via a dedicated read-only
pass before changing anything (`infrastructure/terraform/modules/{aws,gcp}/monitoring/`,
the `monitoring` schema block, `monitoring_agent` role, all three `/health`
handlers, and a repo-wide grep for any existing Prometheus/OTel/metrics
exporter). Findings that shaped scope:
- Current monitoring is entirely host-level (CloudWatch Agent/Ops Agent
  CPU/memory/disk) plus one log file (`traefik-access.log`, UI-role VMs
  only, for HTTP error-rate alarms) — **no PGMQ-specific or self-hosted-DB
  assumption exists anywhere in the Terraform monitoring modules or the
  `monitoring_agent` role**, so "remove only obsolete PGMQ/session-cleanup
  assumptions" was a no-op: there was nothing to remove.
- No custom-application-metric or metrics-exporter convention exists
  anywhere in the repository (confirmed via grep: zero real hits for
  `prometheus`/`/metrics`/`expvar`/`otel`). The only existing
  operator-visibility convention for application state is the `/health`
  JSON endpoints.
- The exact SQL needed for outbox backlog already had a ready-made partial
  index (`ix_published_queue_events_pending`, from migration 006) that
  nothing was querying yet.

**Added automated collection**, reusing the existing `/health` convention
rather than a new platform:
- `services/fetcher/cmd/fetcher/main.go`: new `outboxBacklog()` helper adds
  an `"outbox"` field to `/health` — `pending_count` and
  `oldest_pending_seconds` from `SELECT COUNT(*), MIN(created_at) FROM
  published_queue_events WHERE status = 'pending'`. A query failure is
  reported as `{"outbox":{"error":...}}`, not a `503` — this is a
  diagnostic addition, not a new readiness gate; Fetcher's existing
  readiness semantics (`publisher.Ready`) are unchanged.
- `services/ui/backend/src/ui_service/session_store.py`: new
  `RedisSessionStore.diagnostics()` method calls `INFO memory` and `INFO
  persistence` (verified the exact field names — `aof_enabled`,
  `aof_last_write_status`, `aof_last_bgrewrite_status`,
  `rdb_last_bgsave_status` — against Redis's own command reference before
  using them, rather than guessing) and returns memory/AOF/RDB status.
  Wired into UI's `/health` as a new `"redis"` field in
  `services/ui/backend/src/ui_service/main.py`. Same non-fatal-error
  pattern as the outbox field; readiness stays governed solely by the
  existing `PING`-based `is_ready()`.
- Both fields are pull-based (visible on every `/health` call, including the
  existing smoke test and any manual `curl`) — **not** pushed, graphed, or
  alarmed metrics. Documented that distinction explicitly rather than
  implying they're equivalent to a real alarm.

**Documented, not automated**: RabbitMQ queue depth and unacknowledged
messages per queue. Decided against adding this to Fetcher/History
application code (would mean a new dependency on the RabbitMQ Management
HTTP API, which the architecture deliberately keeps unpublished/restricted —
see "Infrastructure and configuration" above) and against building a new
cross-cloud Terraform log-shipping pipeline for it (real, separate
infrastructure work spanning both `modules/aws/monitoring` and
`modules/gcp/monitoring`, not a documentation-pass change). Documented the
exact `rabbitmqctl list_queues` inspection command instead, which the
step's own "Complete when" explicitly accepts as sufficient.

**New file `docs/monitoring.md`**: what's automated vs. manual-only for each
signal, and — the step's own explicit ask — a "Distinguishing failure modes"
section giving an operator an actual order of checks (broker reachable? →
DB reachable? → backlog draining or stuck? → retries exhausted? → Redis
outright down or just failing to persist?) with the specific command or
`/health` field for each, rather than just listing signals in isolation.
Explicitly warns against running the `database-modes.md` reset commands in
response to a routine failure — those are cutover-only.

**Updated `README.md`**: the three `/health` table rows in "HTTP API" now
mention the new fields; added a cross-reference to `docs/monitoring.md`
after the UI endpoint table.

**Deliberately deferred** (recorded, not silently dropped, per this step's
own instruction): automated, alarmed CloudWatch/Ops-Agent collection of all
three signal groups, with configurable thresholds in the `monitoring` JSON
schema block matching the existing `cpu_threshold_percent` pattern. Full
rationale and the concrete extension point (`agent.tf`'s existing `ui_vms`-style
role-keyed conditional, mirrored for `rabbitmq.host_vm`/`redis.host_vm`) is
recorded in `docs/monitoring.md`'s "Deliberately deferred" section rather
than duplicated here.

Validation: `go build ./...`/`go vet ./...`/`gofmt -l .` clean in
`services/fetcher`; `ruff check services/ui/backend` clean; the existing
Python suite via `.venv/bin/python -m pytest services/history
services/ui/backend` (11/11 pass, unchanged — no test asserted the old
`/health` shape, confirmed by grep before editing, so nothing needed
updating for the new fields); `git diff --check` clean on all edited/added
files. Verified the exact Redis `INFO persistence` field names against
Redis's own command documentation before using them (one `ctx7` query
against `/redis/redis-py` for the async `info()` signature, plus a direct
fetch of Redis's own `commands/info.md` for the field names themselves,
since `ctx7` didn't surface that specific page). No `/health` response was
exercised against a live broker/database/Redis instance — these are static
code-level checks; the query logic itself is unverified against a running
system, consistent with this step being local/documentation work, not
Step 18's live verification.

#### Dashboard comparison follow-up (implemented 2026-09-15)

The user requested a more useful Terraform dashboard before continuing Step
17: one chart per comparable metric with all EC2/GCE VMs shown as separate
lines, instead of repeating one chart for every VM. Implemented that design in
both provider modules:

- `modules/aws/monitoring/dashboard.tf` now produces shared CPU, EC2 status,
  memory, root-disk, received-network, and sent-network charts. Every series is
  labelled with the stable JSON VM/workload key and uses a deterministic color
  that stays the same across host charts. HTTP 500 and all-5xx counts now share
  one count chart. Synthetic success and duration remain separate because their
  units differ.
- `modules/gcp/monitoring/dashboard.tf` now produces the equivalent shared CPU,
  memory, disk, uptime, and directional-network charts. Each VM is a separate
  labelled data set, letting Cloud Monitoring render distinct colored lines.
  Disk series are reduced to the maximum per VM and network interfaces are
  summed per VM, so each comparison has one workload line. The two HTTP log
  metrics share one count chart and are reduced across UI instances.
- Existing alarm resources remain per VM and signal on both clouds. Dashboard
  consolidation does not combine alert evaluation or change thresholds.
- The same review found that the AWS HTTPS canary still required the retired
  `sessions=postgresql` response. Updated its runtime assertion, existing test
  fixture, module README, and monitoring-plan example to the implemented
  `sessions=redis` contract. This prevents a healthy Redis-backed UI from being
  reported as failed when synthetics are enabled; no test was run.
- Reviewed managed-database, RabbitMQ, Redis, and outbox visibility. They were
  not added as misleading dashboard placeholders: the monitoring modules have
  no managed-database input and no time-series collector for the pull-based
  health fields/manual RabbitMQ inspection. Their current visibility remains
  exactly as documented in `docs/monitoring.md`; real panels require a later
  collection implementation.

Decision: keep one dashboard per provider/environment and group only series
with the same unit and meaning. This makes cross-host comparison immediate
without hiding which workload owns a line. No JSON setting or default was
added, and no automated test was added or run. Current provider syntax was
checked through Context7 before implementation. `terraform fmt` and
`terraform validate` passed against the installed AWS 6.63.0 and Google 7.44.0
providers. No Terraform plan/apply or cloud-side dashboard change was made.

### Step 17 — Prepare a concrete deployment review

**Status:** partially complete (2026-09-14); current images and deployable
revision are not prepared. **Depends on:** Steps 12–16.

**Work:**
- Perform focused static/build checks for changed components: Go build/vet,
  Python lint/syntax, frontend build, Compose rendering, Ansible syntax,
  Terraform format/validate, example schema checks, and diff hygiene as
  applicable. Do not add or run automated tests.
- Confirm reproducible image builds and record the intended immutable image
  identifiers. Publishing images is a separate external action unless already
  authorized; never substitute an older image just to finish preparation.
  Use the working-commit tag route below: the user cannot push to `main` or
  `develop`, so neither branch is a prerequisite for publishing new images.
- Prepare the exact deployment invocation, selected configuration/provider,
  inventory and output-file locations, workload/admin secret requirements,
  controller access requirements, and expected resource changes.
- Obtain a read-only Terraform plan when the required credentials/state are
  available. Review creation/destruction, private connectivity, selected DB
  version/class/storage, and co-located VM capacity. Handle plan artifacts as
  sensitive. If access is unavailable, record what remains unverified.
- Verify current provider support and account-specific RDS eligibility before
  deployment, using current official documentation/account information. GCP's
  economy profile and the rest of the VM fleet are not promised to be free.

**Complete when:** local changes and a concrete deployment proposal are ready
for review, and outstanding access/runtime assumptions are explicit. This is
where deployment approval can be requested; preparation alone is not approval.

**Progress (2026-09-14):**

**Unrelated but significant discovery, resolved in-conversation, not by this
step's own work:** an initial read-only `terraform plan` attempt (intended
purely as this step's static/build check) surfaced a real, currently-tracked
local `terraform.tfstate` — a live AWS deployment (application mode,
`eu-central-1`, 5 EC2 instances, full VPC/monitoring/secrets stack, state
serial 198) that this plan document's "Execution boundaries" section had
never recorded, existing entirely outside this session's and this
document's tracked history. Stopped immediately, took no action against it
(only read-only `terraform state list`), and asked the user directly rather
than assuming. The user confirmed it was their own, told me not to touch it,
then separately destroyed it themselves outside this conversation. This is
flagged here because it means the plan document's "nothing has been
validated against real cloud resources" claim was not accurate for the
period this state existed — recorded for the record, not as something this
step fixed or should generalize from.

**Static/build checks — ran across the whole working tree, not just this
session's own edits:**
- Go: `go build ./...`, `go vet ./...`, `gofmt -l .` in `services/fetcher` — clean.
- Python: `ruff check services/history services/ui/backend database/tests` —
  clean; `py_compile` on every `.py` file in those trees — clean.
- Frontend: `npm run build` — clean, and reran a second time to confirm
  byte-identical content-hashed output (`git status` showed zero additional
  diff after the rebuild), i.e. actually reproducible, not just "didn't crash."
- `database/tests`: `python3 -m unittest discover` — 5/5 pass.
- Example schema checks: both `project-config.example.json` and
  `project-config.cloud-example.json` re-validated against the current
  schema — both valid.
- Terraform: `terraform fmt -check -recursive` and `terraform validate` —
  both clean (as in every prior step).
- Ansible syntax: `ansible-playbook --syntax-check` against all eight
  standalone playbooks (`database`, `migrate`, `rabbitmq`, `history`,
  `fetcher`, `ui`, `deploy_workloads`, `bootstrap_bastion`) — all clean.
  Refreshed a stale installed copy of the `oilscope.platform` collection at
  `~/.ansible/collections/ansible_collections/oilscope/platform` first (it
  predated `migrate.yml`'s existence, dated 2026-09-11, so it would have
  syntax-checked old content, not the current working tree) by replacing it
  with a symlink to the actual repo source — a local dev-tooling fix, not a
  repo change.
- `ansible-lint` (now installed, unlike Step 8's environment): found 12
  pre-existing findings, none touched by this session — 9 are the project's
  own deliberate shared cross-role fact-naming convention
  (`oilscope_database_mode` etc., documented back in Step 7A) which
  `var-naming[no-role-prefix]` doesn't recognize as intentional; 2 are lines
  over the 200-character default limit; 1 is a missing explicit
  `changed_when` on an already-conditionally-gated certificate-generation
  task. All predate this session and this whole migration; not fixed, since
  they're cosmetic and ansible-lint has never previously gated this
  project's completion criteria — flagged for awareness only.

**Compose rendering — found and fixed two real, previously-undetected
bugs** in `roles/compose_project/tests/test.yml`, the project's own
documented command for "render and validate all four [five, with `proxy`]
definitions" (`compose_project/README.md`). Running it for the first time in
this whole effort (Step 8 explicitly said Ansible lint/syntax-check wasn't
run; this is a different, role-specific test harness, also apparently never
executed before) surfaced:
1. `compose.history.yaml.j2`/`compose.fetcher.yaml.j2` read
   `oilscope_database_mode`/`oilscope_broker_ca`/`oilscope_database_ca` —
   facts the real deployment playbooks set via `database_connection`/
   `broker_connection` before `compose_project` runs, but this isolated
   role test never ran those roles (correctly — they need real inventory,
   live SSH access to slurp a broker CA, and a real `terraform_outputs_path`,
   none of which an isolated localhost test can provide) and never faked
   their output either, so every render failed with `'oilscope_database_mode'
   is undefined`.
2. Once fixed, `docker compose ... config --quiet` (the harness's second
   validation stage) failed too: the `environment:` block used to satisfy
   Compose's required (`:?`) variable interpolation had never been updated
   since RabbitMQ/Redis env vars became required — it still only had the
   four pre-migration variables.

Fixed both: added a `set_fact` task faking only the specific shape these
templates read (documented inline why, and why running the real prerequisite
roles isn't feasible here), and copied the exact real path constants from
`database_connection/vars/main.yml` rather than inventing new ones. Expanded
the environment block to the full 21-variable set, extracted directly via
`grep -oE '\$\{[A-Z_]+:\?' *.j2` across all templates rather than trusting
`docs/supported-compose-deployment.md`'s table from memory. Verified against
**both** example configs (exercising both the application and cloud Jinja
branches) — all five workloads render and `docker compose config --quiet`
validate cleanly for each.

**Terraform — found and fixed one real bug, confirmed no others of the same
kind exist.** A read-only `terraform plan` (the step's own explicit ask,
attempted first against the real state directory before the live-deployment
discovery above, then redone in an isolated scratchpad copy with zero state
after reverting the real directory) surfaced:
`modules/gcp/vm/monitoring.tf:7`: `for_each = local.monitoring_metrics_enabled
? local.gcp_vms : {}` — a real "Inconsistent conditional result types" error.
`local.gcp_vms` is a map of multi-attribute VM objects; Terraform infers the
literal `{}` as an object type with zero attributes, and the two branches of
a ternary must unify to one type — this only surfaces when `for_each` is
evaluated against concrete values during a real plan, not during `validate`,
which is why every prior step's `terraform validate` never caught it despite
this line existing since Step 6C. Fixed it using the same idiom the sibling
resource two lines below already uses correctly: a `for` comprehension with
an `if` filter (`{ for name, vm in local.gcp_vms : name => vm if
local.monitoring_metrics_enabled }`), which naturally produces an empty map
of the *same* type when the condition is false instead of forcing a
type-incompatible literal.
- Found the same `condition ? map_of_objects : {}` shape at 6 other call
  sites (`modules/{aws,gcp}/monitoring/alarms.tf` ×2 each,
  `modules/{aws,gcp}/monitoring/logs.tf` ×1 each) and did not assume they
  shared the bug just because they looked structurally similar. Verified
  empirically instead, in the isolated scratch copy (a full repo copy under
  the scratchpad directory with all state files removed, `-backend=false`,
  and a scratch-only `providers.tf` override adding fake AWS credentials
  with `skip_credentials_validation`/`skip_requesting_account_id` — never
  applied to the real directory, and the real directory's `providers.tf` was
  reverted to a clean zero-diff state immediately after the one diagnostic
  attempt made there, confirmed via `git diff --check`): a full offline plan
  against `project-config.example.json` (GCP/application) completed with
  **zero errors** (`Plan: 47 to add, 0 to change, 0 to destroy`), and a full
  offline plan against `project-config.cloud-example.json` (AWS/cloud)
  produced zero type errors (`Plan: 35 to add`, plus 5 unrelated failures
  from `data` sources — AMI SSM parameter lookups and an STS caller-identity
  read — that need real credentials regardless of plan vs. apply). This
  confirms the other 6 occurrences do **not** share the bug; left them
  untouched rather than "fixing" working code.

**Reproducible image builds and identifiers:** did not build the four
Docker images (no Docker daemon available, consistent with every prior
step) and did **not** execute the already-documented tag-push/publish
route below — pushing a Git tag and triggering a real GHCR publish is a
visible, external, hard-to-reverse action requiring separate explicit
authorization, which this step's own instructions require ("Publishing
images is a separate external action unless already authorized"). The
route itself was already fully documented in a prior session; nothing
new was needed here. Confirmed the frontend half of image reproducibility
directly (byte-identical rebuild, above); the Go/Python image layers were
not independently re-verified for reproducibility since that needs an
actual container build.

**Verified current provider support against live documentation** (not
training-data assumptions):
- AWS: fetched `aws.amazon.com/rds/free/` — confirmed `db.t3.micro`/
  `db.t4g.micro` still qualify for PostgreSQL under the current Free Tier
  terms (6-month/credits for new accounts; legacy 12-month for accounts
  activated before 2025-07-15), matching what's already in
  `docs/database-modes.md`. Fetched AWS's RDS PostgreSQL release notes:
  confirmed PostgreSQL 18 is generally available on RDS (up to minor
  version 18.6; PostgreSQL 19 exists only in the RDS Preview environment/beta) —
  the schema's `const: "18"` is current, not stale. Could **not** verify the
  specific `db.t4g.micro`/`db.t3.micro` × PostgreSQL 18 × `eu-central-1`
  combination — that requires a live `aws rds describe-db-engine-versions
  --region eu-central-1` call against a real account, which this environment
  doesn't have. Recorded as unverified, per this step's own allowance.
- GCP: confirmed PostgreSQL 18 is now Cloud SQL's **default** major version
  (regular support began 2025-09-25) — current and, if anything, stronger
  than what the schema assumed. No documented tier/edition restriction was
  found for PostgreSQL 18 on shared-core tiers beyond what's already
  captured in the schema's `ENTERPRISE`-edition-for-economy-tier requirement
  and `docs/database-modes.md`'s existing SLA caveat.

**Deployment proposal (the step's own explicit ask) — prepared generically
against both example configs, since no real target config exists in this
repository to propose deploying:**
- *Application/GCP* (`project-config.example.json`): `infrastructure/ansible/deploy.sh
  oilscope.platform.deploy_workloads -i infrastructure/ansible/inventory/oilscope.yml
  -e project_config_path=<path>`. No `terraform_outputs_path` needed (no
  managed database). Expected resources per the offline plan above: 47
  created, 0 changed, 0 destroyed, for a database VM + 4 workload VMs +
  networking + monitoring + 2 secret containers, entirely within GCP.
- *Cloud/AWS* (`project-config.cloud-example.json`): Terraform apply first
  (RDS + AWS networking + secrets + monitoring: 35 resources per the
  offline plan, plus real AMI/account lookups unverifiable here), export
  `terraform output -json`, then the same `deploy_workloads` command with
  `-i infrastructure/ansible/inventory/oilscope-aws.yml` and
  `-e terraform_outputs_path=<path>` added — this run additionally executes
  `migrate.yml` (skipped entirely in application mode) and creates no
  database-role VM.
- Workload/admin secrets: every `secret_mappings` value in the chosen config
  must be uploaded via `oilscope.platform.upload_secret_versions` before
  deployment (`docs/secrets.md`); the RDS administrator password is
  AWS-managed (never manually uploaded), the GCP administrator password is
  Terraform-generated and lives in state (documented AWS/GCP asymmetry,
  `docs/secrets.md`).
- Controller access: SSH via bastion with `OILSCOPE_SSH_USER` matching
  `ssh_users`; cloud-mode additionally needs the operator's AWS CLI/gcloud
  credentials with read access to the administrator secret (for
  `database_migrate`) and, separately, `secretsmanager:PutSecretValue`
  (AWS) or `secretVersionAdder` (GCP) to upload workload secrets.
- This proposal is preparation only — it does not request or imply
  deployment approval, per this step's own completion criterion.

Validation: every check above was actually run, with output captured to
`/tmp/plan-app.log`/`/tmp/plan-cloud.log`/`/tmp/plan-app-gcp.log` during this
session (not committed — scratch diagnostic output). `git diff --check`
clean on every edited file
(`modules/gcp/vm/monitoring.tf`, `roles/compose_project/tests/test.yml`,
and confirmed zero-diff on `providers.tf` after reverting the diagnostic
edit). No `terraform apply`, no image publish, no tag push, and no action
of any kind against the real (now-destroyed) AWS state were performed.

#### Step 17 publishing route — Build on GitHub without pushing protected branches

**User constraint (2026-09-14):** cannot push to `main` or `develop`. New
Fetcher, History, UI, and database images must still be buildable on GitHub
from the intended working-branch commit before deployment.

**Chosen route:** reuse the existing tag trigger. In
`.github/workflows/publish-images.yaml`, pushes to `main`/`develop` and pushes
of tags matching `v*` are separate trigger alternatives. A matching tag can
point to a working-branch commit; that commit does not have to be merged into
either protected branch. The tagged commit must contain the publishing
workflow, its reusable workflow, and all intended source/configuration changes.
No workflow edit is required for this route.

The reusable workflow checks out the triggering revision, builds all four
Dockerfiles, and publishes to
`ghcr.io/<repository-owner>/push-and-pray/{fetcher,history,ui,database}` with
the full `${{ github.sha }}` as the image tag. The Git tag triggers the build;
it is not the image tag used by deployment. The UI Dockerfile builds its
frontend on GitHub, so publishing does not depend on locally installed native
frontend bindings.

**Operator procedure (documented, not executed):**

Registry ownership clarification (2026-09-14): the current Git remote is
`ua-academy-projects/push-and-pray`. When the workflow runs in that repository,
`${{ github.repository_owner }}` is `ua-academy-projects`, regardless of which
contributor pushed the tag. Images therefore go to GitHub Container Registry
(GHCR), under the shared organization namespace:

```text
ghcr.io/ua-academy-projects/push-and-pray/fetcher:<full-commit-sha>
ghcr.io/ua-academy-projects/push-and-pray/history:<full-commit-sha>
ghcr.io/ua-academy-projects/push-and-pray/ui:<full-commit-sha>
ghcr.io/ua-academy-projects/push-and-pray/database:<full-commit-sha>
```

These are organization-owned packages shared according to package permissions,
not personal packages for the contributor who triggered the build. Repository
membership alone is not a promise that every member can read/write each
package; actual visibility, inherited access, and organization policy must be
checked on GitHub. This update does not assert that the packages are public.

Ansible's application Compose templates pull from
`registry.repository/<service>:registry.image_sha`. For the repository above,
the base is `ghcr.io/ua-academy-projects/push-and-pray`. `registry.username`
identifies the GitHub account owning the pull token; it does not change the
image namespace. The existing `registry_auth` role logs into GHCR with the
workload's secret-managed `GHCR_TOKEN`, while GitHub Actions publishes with
its own repository `GITHUB_TOKEN`. No Docker Hub/ECR/Artifact Registry is used
for these four application images by the current workflow.

A workflow run in a personal fork would instead resolve `repository_owner`
to that fork's owner and target `ghcr.io/<fork-owner>/push-and-pray/...`, subject
to that account's Actions/package permissions. Using that route would also
require changing the deployment's explicit registry base and pull credentials.
Current decision: retain the existing shared organization namespace; this
clarification does not switch the project to a personal registry.

1. Finish and review the intended changes on the working branch. Commit all
   required source/workflow changes; uncommitted working-tree files are not
   included in GitHub builds. Confirm `origin` is the intended publishing
   repository and the commit contains both workflow files.
2. Choose a new, never-reused tag beginning with `v`, for example
   `v0.0.0-preview-db-20260914-1`. Use an unused suffix for subsequent builds.
   The following creates a lightweight tag on the current commit and pushes
   only that tag, without changing `main` or `develop`:

   ```sh
   git status --short
   git rev-parse HEAD
   git tag v0.0.0-preview-db-20260914-1 HEAD
   git push origin refs/tags/v0.0.0-preview-db-20260914-1
   ```

   Stop if there are intended changes still uncommitted. Do not force-update
   an existing tag. Publishing the tag also uploads its reachable commit
   history; select the commit deliberately. A GitHub Release is not required.
3. Open GitHub Actions → **Publish application images** and inspect the run
   for this tag/commit. Wait for **all four** image jobs to succeed; they run
   independently, so one published image does not mean the set is complete.
   These workflows build/publish images; this route adds no automated tests
   and does not itself deploy the application.
4. Record the full commit SHA and published image digests. After confirming
   that all four images exist and the deployment identity can pull them,
   explicitly set `registry.image_sha` in the real project JSON to that full
   SHA. Set `registry.repository` to the matching
   `ghcr.io/<repository-owner>/push-and-pray` namespace. Do not set it to the
   preview Git tag or `latest`, or update it before the builds succeed.
5. Continue Step 17's review and the separately authorized deployment. A
   SHA-named registry tag gives revision traceability but is not technically
   immutable; record digests and do not overwrite published revision tags.

**Permissions and limits:** branch protection and tag creation permissions
are distinct. This route requires permission to create the selected tag,
Actions to be enabled/allowed, and the repository's `GITHUB_TOKEN` to have
write access to the GHCR packages. The workflows already request
`contents: read` and `packages: write`; organization policy and existing
package access can still restrict them. No additional PAT is required when
those permissions are sufficient. None of these repository/account policies
was verified by this local documentation update.

If tag creation is also restricted, arrange an approved tag namespace with a
maintainer. A possible alternative is a publishing push trigger restricted
to an allowed feature/build branch; that requires a reviewed workflow change
and repository/package permissions, not a branch-protection bypass. Do not
assume `workflow_dispatch` alone solves the constraint: it is absent from the
current publishing workflow, and manual dispatch requires the workflow to
exist on the default branch. Do not publish untrusted PR code through a
privileged `pull_request_target` workaround.

Sources checked through Context7:
[GitHub branch/tag trigger syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
and [manual workflow requirements](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow?tool=webui).
Repository evidence: `publish-images.yaml`, `reusable-build-image.yaml`, and
`infrastructure/docker/Dockerfile.ui`.

**Status (updated 2026-09-15):** image publication completed; real JSON update
and deployment-identity pull verification remain the next preparation work.
This is a subtask of Step 17, not a ninth remaining step.

The clean `monitoring` branch commit
`42e84f633f10101aaf3f2fa2aa18932faadb183c` was tagged with the new annotated
tag `v-pavlo-20260915-1` and pushed without pushing `main`, `develop`, or the
working branch. GitHub Actions run `34956386777` completed successfully and
all four independent build-and-publish jobs succeeded. The workflow published
the full commit SHA as the deployment image tag under the shared organization
GHCR namespace. Recorded manifest digests:

```text
fetcher  sha256:a60a637b45b5bbe7b68df3c4717fb980ccfbbb9520c269f54e3498b715e1f166
history  sha256:ef2dddc648b59ca5808f4c8b795e016a8fb704f273672d285ae94646f5557b92
ui       sha256:42793f38ab0a041a55b914ae3cdcdbe2ace9843d52a9a1464a6eb9b49477ed4d
database sha256:3054116b5d4d6604410e68772577ddb06853e269a5341b3ea976b1f7866b596e
```

Evidence was read from the completed GitHub run and its Buildx manifest-push
log lines. The tag resolves locally to the same commit. No image was pulled and
no VM identity was used yet, so GHCR read access from the deployment remains
unverified. The real Desktop configuration still points to the older
`7075d461...` image tag and must be updated explicitly in the next step; the
Git preview tag itself must not be used as `registry.image_sha`.

**Deployment JSON update (completed 2026-09-15):** the user updated the
existing `/Users/pavlo/Desktop/project-config.new.json` in place; no second
deployment JSON is used. `registry.repository` remains
`ghcr.io/ua-academy-projects/push-and-pray` and `registry.image_sha` now equals
the published full commit SHA
`42e84f633f10101aaf3f2fa2aa18932faadb183c`. The selected first deployment is
`environment=prod`, `default_cloud=aws`, `default_db=cloud`, so this run targets
AWS with managed RDS rather than the application PostgreSQL VM. Validation
against `project-config.schema.json` passed with `jsonschema` Draft 2020-12.
The documented `uvx check-jsonschema` wrapper was unavailable in the current
shell, so the installed `.venv-ansible` Python environment performed the same
schema evaluation directly. No secret value was read and no cloud operation
was performed during this check.

**AWS preflight checkpoint (2026-09-15, incomplete):** the local Terraform
state is not empty. State lineage `1755ab10-5074-d60e-d633-7cf9fb77b2ce`,
serial 256, still tracks the AWS VPC, public/private routing, NAT/EIPs, five EC2
instances (including the application-mode `infra` database VM), their IAM
roles/profiles and the synthetic-canary S3 bucket. This conflicts with treating
the next run as a fresh deployment and also conflicts with the JSON's new
cloud/RDS selection. No state entry was removed and no resource was changed.

A read-only `aws sts get-caller-identity` check from the Codex tool process
failed with `InvalidClientTokenId`; `aws configure list` there showed an older
key from the shared credentials file and region `eu-central-1`. The user's
interactive shell later supplied valid session credentials and successfully
refreshed/planned the state. Credentials exported in that terminal are not
inherited by the separate Codex tool process, so its authentication failure is
not evidence that the user's terminal session expired.

**AWS plan review (2026-09-15, apply not authorized):** after credentials were
refreshed, Terraform successfully refreshed the tracked resources in AWS account
`441955873558` and produced a plan of 53 additions, 2 in-place changes, and 3
destroys. This proves the state is active rather than merely an unreadable stale
file. The action set structurally matches an application-to-cloud database
transition: create private PostgreSQL 18 RDS (`db.t4g.micro`, 20 GiB `gp2`,
Single-AZ, encrypted, AWS-managed administrator password), its parameter/subnet/
security groups and second-AZ subnet; create the configured secrets and new
monitoring stack; add RabbitMQ TLS ingress from Fetcher; remove UI from the old
database security-group ingress; and destroy only the stopped `infra` EC2
database VM plus its instance profile and IAM role. The existing `infra` root
volume is configured `delete_on_termination=true`, so applying the plan destroys
that database storage. This is a real destructive mode switch, not a fresh
deployment or routine redeploy. No saved plan file was produced (`-out` was not
used), and nothing was applied.

One blocking credential-design issue was found before apply. The real cloud-mode
JSON maps both Fetcher and History `POSTGRES_PASSWORD` to the same
`oilscope-db-password` secret. The migration role creates predictable separate
SQL usernames (`oil_tracker_fetcher` and `oil_tracker_history`) using that same
password. A compromised workload could therefore use the shared password with
the other workload's username and bypass the intended table-level separation.
Before replanning, use separate secret IDs and values for Fetcher and History;
Terraform should then create two runtime secret containers instead of the shared
database-password container. Secret containers will initially have no values,
so versions must still be uploaded after apply and before workload deployment.
The plan's monitoring alarms and synthetic canary will also begin evaluating
before agents/workloads are deployed, so temporary missing-data/health alarms
are expected during bootstrap. These observations do not authorize apply.

**Revised saved-plan review (2026-09-15):** the user replaced the shared
runtime mapping with `oilscope-prod-db-password-fetcher` and
`oilscope-prod-db-password-history`, then created
`/tmp/oilscope-prod-aws.tfplan`. The plan now contains 54 additions, 2 in-place
changes, and the same 3 destroys. Full `terraform show -json` inspection
confirmed separate secret containers and workload IAM policies; the retained
Bastion, Fetcher, History, and UI EC2 instances, EIPs, VPC, NAT and existing
routes are all `no-op`. The only deletes remain the old `infra` EC2 instance,
its instance profile, and its IAM role. The only updates remain removal of UI
from old PostgreSQL security-group ingress and addition of RabbitMQ TLS ingress
from Fetcher to History. RDS and the second-AZ subnet, monitoring resources,
six workload secret containers, three secret-access policies, and four agent
publishing policies are creates. This is the expected action shape.

The saved plan was concrete but could not be applied safely without an
explicit decision about the old database: deleting `infra` also deletes its
50 GiB root EBS volume (`delete_on_termination=true`), with no database export,
snapshot, or data transfer in this procedure. Subsequent read-only EC2/RDS
queries from the Codex process still used its older credentials; they did not
invalidate the user's authenticated saved plan. At this review point no apply
had been attempted. The plan file was under `/tmp`, outside the repository.

**Destructive transition authorization (2026-09-15):** the operator renewed
AWS credentials and `sts get-caller-identity` resolved to IAM user
`arn:aws:iam::441955873558:user/oilscope-admin` in the same account used by the
saved plan. A read-only instance query confirmed Bastion, Fetcher, History, UI,
and the old `infra` database VM are all stopped. The user then explicitly
authorized permanent deletion of the old database VM and its EBS data without
backup or migration. This satisfies the shutdown/data-loss decision required
before applying the saved mode-switch plan; it does not change the recorded
decision that queued/session state is not transferred. Apply result, RDS
readiness, output export, secret versions, workload deployment, and runtime
verification remain pending and must be recorded separately.

**Terraform apply result (2026-09-15):** the user applied the exact saved plan.
Terraform state advanced from serial 256 to 319. State now records RDS instance
`db-P5C7UVVPGGI3PEPTUA4QH6ZRTQ` as `available`, PostgreSQL actual version 18.3,
`db.t4g.micro`, 20 GiB `gp2`, encrypted, private, Single-AZ, with an active
AWS-managed administrator secret. The endpoint output is
`oilscope-prod-database.c5q000geouyp.eu-central-1.rds.amazonaws.com:5432` with
database `oil_tracker` and `sslmode=verify-full`. The old `infra` instance is
absent from state. All six intended workload secret containers, monitoring
resources and policies are present in state, and outputs contain only the four
retained VMs.

This verification used the post-apply Terraform state and outputs. Direct AWS
API checks from the separate Codex process still cannot use the session
credentials exported in the user's shell, so cloud-side status is not claimed
independently beyond Terraform's successful provider result. No secret value
was read. Output export, secret-version upload, host startup/deployment, DNS and
runtime verification remain pending.

**EC2 power-state clarification (2026-09-15):** the four retained instances
remain stopped because they were stopped before the mode-switch plan and the
AWS VM module manages `aws_instance` configuration without an
`aws_ec2_instance_state` resource. Terraform therefore treated them as `no-op`
and did not assert `running`. Keep them stopped while secret versions are being
prepared: starting them early could boot old workload configuration against the
now-removed application database. The chosen order is upload secrets first,
then explicitly start Bastion/Fetcher/History/UI, wait for EC2 status checks,
and immediately run the Ansible deployment so the current RDS/RabbitMQ/Redis
configuration replaces the old workload configuration.

**Workload secret upload (completed 2026-09-16):** the user ran the uploader
in check mode successfully (`changed=0`, `failed=0`), then uploaded all six
versions from the same terminal environment. Actual upload recap:
`ok=39 changed=14 unreachable=0 failed=0`. The private payload file was removed
by the role's cleanup task. Recorded non-secret version IDs:

```text
oilscope-ghcr-token                 a8c08566-bcc1-427b-b431-e3e071878f61
oilscope-oilpriceapi-key             3811e90e-0246-43bc-9547-5dea52f1e383
oilscope-prod-db-password-fetcher    9d90d200-e2b8-4a82-939d-3f1de7990800
oilscope-prod-db-password-history    168fc758-d07e-43b3-ac19-5e6bd07fd1a1
oilscope-prod-rabbitmq-password      d42acf42-6316-46ef-94d3-af4de6048b9c
oilscope-prod-redis-password         35103d9d-48a3-4f99-9176-e0181baee28c
```

Evidence is the user's successful Ansible output; no secret values were read
or displayed. RDS's administrator secret remains AWS-managed and was not
uploaded manually. Upload success establishes stored versions, not token/API
validity or VM read access; image pulls, runtime grants, and application
connectivity remain deployment checks. Next: explicitly start the four retained
EC2 instances, wait for status checks, then verify SSH/inventory and deploy the
current workloads.

### Step 18 — Deploy the selected mode and verify ordinary operation

**Status:** in progress (2026-09-16) for the authorized AWS cloud-database
deployment. Images were published, the reviewed Terraform plan was applied,
fresh outputs were exported, and workload secret versions were uploaded.
Host configuration and live application verification remain pending.

**Host startup and SSH decision (2026-09-16):** the user reported completing
the explicit start/wait commands for the four retained EC2 instances. No
status table was supplied, so this records user-reported completion rather
than an independent live AWS check. Next, verify dynamic inventory and SSH
before running workload deployment. Use the existing real config at
`/Users/pavlo/Desktop/project-config.new.json`, SSH user `operator`, and
`/Users/pavlo/.ssh/petroscope_gcp_ed25519`: its corresponding public key
matches the configured operator key (no private-key contents were read).
The configured bastion port is already `22`; no temporary port override or
security-group bootstrap rule is required. Workload SSH uses the bastion
proxy configured in inventory group variables. Set `OILSCOPE_PROJECT_CONFIG`
for inventory discovery and pass the same path as `project_config_path`
for playbook/group-variable use.

**Inventory and SSH verification (completed 2026-09-16):** the user's
inventory graph contains exactly the retained bastion, Fetcher, History,
and UI hosts, with the expected workload groups. All four returned
`SUCCESS` and `ping: pong`; workload access through the bastion and remote
Python execution are confirmed. Ansible reported the deprecated/reserved
`tags` host variable and interpreter-discovery warnings (`python3.14`);
these did not prevent connectivity. Proceed with the existing
`deploy_workloads` wrapper using the real config and
`/Users/pavlo/Desktop/terraform-outputs.aws.json`. In cloud mode the local
database play skips, followed by managed migrations from History, RabbitMQ,
History, Fetcher, and UI (including Redis). This order prepares the database
and broker before their application clients. Deployment success and live
application checks remain pending; SSH success alone does not prove them.

**Deployment correction (2026-09-16):** the first workload deployment stopped
in History's monitoring role with recursive templating of
`monitoring_agent_config_path`. Recap: History `ok=142`, `changed=21`,
`failed=1`; other hosts had no failures or unreachable results. This was a
partial deployment, not application readiness verification. Removed the
self-referencing role parameter from Database, History, Fetcher, and UI;
the role now inherits the explicitly supplied variable. The earlier command
also omitted this required path. Monitoring now selects the current cloud's
output from the existing full Terraform output file, retaining compatibility
with a single-output wrapper. Updated the role documentation and comments.
Decision: reuse `/Users/pavlo/Desktop/terraform-outputs.aws.json` for both
`terraform_outputs_path` and `monitoring_agent_config_path`, with no extra
JSON export. Rerun the full deployment with both arguments so all plays can
converge after the partial run. The installed collection is a symlink to
the repository, so these Ansible changes take effect immediately without
collection reinstallation or application image rebuilding. No automated
tests or live deployment were run by the assistant for this correction.

**Single Terraform output argument (2026-09-16):** at the user's request,
replaced the monitoring role's `monitoring_agent_config_path` input with
`terraform_outputs_path` directly. Both database connection and monitoring
now read the explicitly provided path; no path default or duplicate argument
is needed. This supersedes the two-argument command above. Monitoring still
requires this argument in application database mode. Updated role docs,
playbook comments, collection changelog, and existing role fixture invocations
to match the renamed input; no new tests were added or run. Changed YAML
was checked for parsing and whitespace errors. Next command:

```bash
infrastructure/ansible/deploy.sh oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG" \
  -e terraform_outputs_path=/Users/pavlo/Desktop/terraform-outputs.aws.json
```

**GPG conversion correction (2026-09-16):** the user reported the deployment
appearing stuck at the CloudWatch public-key conversion task. The command
used `gpg --dearmor --output keyring.gpg` without unattended/overwrite flags;
on a rerun with an existing keyring it can prompt for overwrite. This is a
code-level explanation, not a confirmed remote process diagnosis. Added
`--batch --yes --no-tty` to conversion, and `--batch --no-tty` to fingerprint
inspection. Conversion continues to run on every deployment so a refreshed
downloaded public key is reflected in the verification keyring. Fingerprint
pinning and package signature verification remain in place. Corrected the
conversion comment to describe a binary OpenPGP keyring rather than a keybox.
Decision: interrupt the current deployment and rerun the same single-output
argument command; repository edits do not change an already running task.
YAML parsing and whitespace checks passed; no automated tests or remote
process inspection were performed. Live deployment remains in progress.

**Manual RDS access decision (2026-09-16):** the administrator login is
`oil_tracker_admin`, created by Terraform/RDS, with its generated password
in the AWS-managed Secrets Manager secret referenced by
`aws_database_connection.value.admin_secret_arn`. Migrations create the
restricted `oil_tracker_fetcher` and `oil_tracker_history` logins from their
respective workload password secrets; no UI PostgreSQL login is created.
Their creation has not been independently inspected during the partial run.
For manual laptop access, tunnel through the bastion to History, then forward
to the private RDS endpoint: the RDS security group permits History/Fetcher,
not direct bastion or public laptop connections. Preserve `verify-full`
using the real RDS hostname and AWS CA bundle; with psql, use `host` for
the RDS name and `hostaddr=127.0.0.1` for the local tunnel. No credentials
were retrieved and no manual database connection was made by the assistant.

**Work after authorization:**
- Apply the reviewed plan, export fresh outputs, make required secret versions
  available, and execute the documented Ansible sequence. For an existing
  deployment, use the approved cutover procedure where applicable.
- Verify actual RDS/Cloud SQL hostname/CA validation, private DNS and routing,
  migration execution, and restricted runtime credentials. Static Terraform
  validation cannot establish these properties on the target provider.
- Observe normal operation: a fetched event enters the outbox, is confirmed
  through RabbitMQ, and reaches History; UI reads history and stores session
  preferences in Redis. Confirm readiness and the Step 16 inspection paths.
- Record provider, database mode, image/config revision, observed results,
  limitations, and any corrective changes. Do not generalize results from
  one provider/mode to an environment that was not exercised.

**Complete when:** the authorized target operates normally with documented
observations. No automated tests or fault injection are implied by this step.

#### Review of claimed completion through Step 18 (2026-09-14)

The local implementation is substantial and its basic static/build checks are
healthy, but review does **not** support marking every step through 18 complete.
No application code was changed by this review; the findings below remain open.

1. **Step 12 — cloud example is ignored by Git.**
   `project-config.cloud-example.json` exists and validates against the schema,
   but root `.gitignore` ignores `*.json` and allowlists only
   `project-config.example.json`. `git check-ignore` confirms the cloud example
   is ignored, and `git ls-files` confirms it is untracked. Unless an explicit
   exception such as `!project-config.cloud-example.json` is added, the example
   cannot be committed or reach other contributors. Step 12 therefore needs a
   small repository fix before completion.
2. **Step 13 — use RabbitMQ's documented argument order.** The runbook writes
   `rabbitmqctl purge_queue <queue> -p <vhost>`. RabbitMQ's current command
   reference specifies `rabbitmqctl purge_queue [-p vhost] queue`. Put `-p`
   before the queue in all three commands rather than depending on undocumented
   option permutation. The rest of the scoped reset and service ordering is
   coherent on static review. Reference:
   <https://www.rabbitmq.com/docs/man/rabbitmqctl.8>.
3. **Step 15 — the rebuilt UI still describes Redis sessions as PostgreSQL.**
   `services/ui/frontend/src/App.tsx` displays `"PostgreSQL session saved"`.
   The successful frontend rebuild copied the same stale wording into the
   generated bundle. Change the source to Redis-neutral or Redis-accurate text
   and rebuild the tracked assets again.
4. **Step 16 — outbox monitoring disappears during broker failure.** Fetcher's
   `/health` returns immediately with `503` when `publisher.Ready` is false,
   before calling `outboxBacklog()`. Consequently the response omits precisely
   the backlog diagnostic needed during a RabbitMQ outage. The documentation
   also incorrectly says `publisher.Ready` only means the dispatcher started;
   the dispatcher actually updates it from the latest publish/probe result.
   Compute the diagnostic for both ready and not-ready responses, bound its DB
   query with a short timeout so health cannot hang indefinitely, and avoid
   exposing raw database error details in the public JSON response. Correct
   `outbox_pending_count` in `docs/monitoring.md` to the implemented field name
   `pending_count`.
5. **Step 17 — no deployable revision or current images exist yet.** The working
   tree contains the implementation as uncommitted changes. There is no `v*`
   tag for the current revision and no GitHub image publication was recorded.
   The real Desktop configuration still sets `registry.image_sha` to
   `7075d461...`, an older ancestor commit from 2026-08-31, so it cannot deploy
   the current RabbitMQ/Redis/database changes. Docker is currently unavailable
   locally, so the four image builds were not verified here either. Finish the
   corrections above, commit them, publish all four images from that commit,
   record their digests, and only then update the real config to the new full
   commit SHA.
6. **Step 18 — no current deployment evidence.** The Step 17 record explicitly
   says no tag push, image publication, or deployment happened, and Step 18 has
   no progress entry containing a provider, database mode, deployed image SHA,
   Terraform/Ansible results, or runtime observations. Static validation cannot
   substitute for RDS/Cloud SQL TLS, private networking, migration, RabbitMQ,
   Redis, or application readiness verification. Keep Step 18 pending until an
   explicitly authorized deployment of the corrected, published revision is
   observed and recorded.

Review checks actually run: `go build ./...`, `go vet ./...`, and `gofmt` for
Fetcher; Ruff and Python byte-compilation for History/UI/database code;
frontend type-check/build; Terraform format check and `terraform validate`
(provider execution outside the sandbox); Draft 2020-12 schema validation for
both example configs; syntax checks for all eight Ansible playbooks; and
`git diff --check`. These checks passed. No automated tests were run, honoring
the user's instruction. No Docker image build, tag push, registry lookup,
Terraform plan/apply, secret access, SSH, or live deployment action occurred.
Current Google documentation confirms that shared CA supports hostname
verification for private services access and that the regional CA bundle URL
shape used by the GCP module is published; this remains runtime-unverified.
References: <https://docs.cloud.google.com/sql/docs/postgres/authorize-ssl> and
<https://docs.cloud.google.com/sql/docs/postgres/manage-ssl-instance>.

#### Resolution of review findings 1–4 (2026-09-14)

The user authorized the four local corrections; all were implemented:

- `.gitignore` now explicitly includes `project-config.cloud-example.json`.
  `git check-ignore` no longer matches it, so it appears as an ordinary
  untracked file ready to add with the rest of the change. Both application
  and cloud examples still validate against the current Draft 2020-12 schema.
- All three RabbitMQ cutover commands in `docs/database-modes.md` now follow
  the documented `purge_queue -p <vhost> <queue>` argument order. Queue order
  remains dead → retry → main for the delayed-forwarding reason already given.
- The UI source now says `Redis session saved`. Rebuilt the production assets;
  the generated bundle contains the new wording and `index.html` references
  the new content-hashed files.
- Fetcher's `/health` now queries outbox diagnostics before choosing HTTP 200
  or 503, so a broker-not-ready response still includes backlog information.
  The query uses the explicitly configured RabbitMQ timeout as its bound; this
  adds no default or configuration field. Detailed DB errors stay in server
  logs while the public response returns `{"error":"unavailable"}`. Updated
  `docs/monitoring.md` to describe actual `publisher.Ready` semantics and fixed
  the stale `outbox_pending_count` name to `pending_count`.

Checks actually run after the fixes: Fetcher `gofmt`, `go build ./...`, and
`go vet ./...`; frontend `npm run build` (including TypeScript checking); both
example schema validations; cloud-example ignore check; and `git diff --check`.
All passed. No automated tests, Docker image build, cloud action, secret access,
tag push, or deployment was performed.

**Next step:** complete Step 17 by committing the corrected revision and
publishing all four SHA-tagged images. Record their digests, then update the
real configuration to that full commit SHA. Step 18 remains pending until a
concrete deployment review and explicit deployment authorization.

### Step 19 — Close remaining provider/mode and cutover verification gaps

**Status:** pending; depends on Step 18 and separately authorized environments
and any destructive switch/rehearsal.

**Work:**
- Maintain an explicit matrix for AWS/application, AWS/cloud,
  GCP/application, and GCP/cloud: locally reviewed, actually deployed, or not
  verified. Cover remaining combinations only within authorized resources
  and budget; never provision all combinations implicitly.
- Where authorized, perform a controlled mode switch using Step 13 and verify
  that the new DB starts fresh, old queued/session state cannot reappear, and
  the restarted services target the new endpoints. Check routine redeploy
  retention separately from intentionally destructive switching.
- Confirm first-cutover handling for any existing extension-based database;
  do not mistake successful fresh provisioning for an upgrade rehearsal.
- Reconcile README, runbooks, examples, and this progress log with actual
  outcomes. Mark unavailable/unapproved cases explicitly unverified rather
  than claiming complete cross-provider operational coverage.

**Complete when:** authorized verification is documented and every remaining
coverage gap is explicitly accepted or still open. Local implementation may
be complete earlier; full operational coverage is not inferred from it.

### Optional follow-up — Remove retired database objects

Not part of the eight required steps and not needed for fresh deployments.
After a successful cutover, inspect dependencies and separately authorize any
removal of unused `ui_sessions`, PGMQ queues/extensions, or cron objects on an
existing database. Disabling the old cleanup job belongs to Step 13's cutover;
dropping obsolete objects later is optional. Never use blind `CASCADE` drops
or delete price/outbox records as incidental cleanup.

### Recording progress for every remaining step

After each step, add a dated progress entry naming the files changed, final
behavior, decisions and rationale, actual checks/results, and limitations.
Update that step's status and the next dependency. Do not mark planning,
static validation, deployment, or runtime verification as interchangeable.
Preserve explicit JSON/no-defaults, RabbitMQ/Redis in both modes, no data
transfer, no automated tests, and the deployment authorization boundary.

Documentation update (2026-09-14): expanded the previous three-item outline
into Steps 12–19, made local Compose and monitoring gaps explicit, separated
preparation from authorized deployment/verification, and retained optional
legacy cleanup outside required scope. Corrected stale current-state prose
and references that conflicted with required `default_db` and the no-tests
decision. No implementation or deployment was performed in this update.

## Execution boundaries and documentation

Credential clarification (2026-09-14): inspected only non-secret fields in the
real Desktop JSON. At that time it selected AWS/application mode; `infra`,
`history`, and `fetcher` map `POSTGRES_PASSWORD` to `oilscope-db-password`.
With the configured `oilscope-prod-` prefix, the upload variable resolves to
`OILSCOPE_DB_PASSWORD`. Documented initial upload, VM-identity retrieval,
container environment injection, and admin/runtime separation in
`docs/secrets.md`. Application mode requires the same password for its shared
`oil_tracker` login; cloud mode may use separate runtime secret IDs. Image
read permissions do not grant secret access. Existing-volume password rotation
needs a SQL login update as well as a secret version and client restart;
application-mode automation does not currently perform that SQL update.
No secret values were read, generated, uploaded, or changed. No VM/DB actions
were performed. Step 12 still includes reconciliation of older generic secret
examples with the current architecture. The 2026-09-15 deployment JSON update
above supersedes the mode observation: the file now selects AWS/cloud mode.

This implementation remains local: no Terraform apply, cloud deployment,
live database switch, live data transfer, or live queue/session reset without
separate deployment authorization. Progress above records local code changes.
The user declined automated tests; do not add or restore them without a new
request. Earlier testing scenarios remain reference material, not completed work.

Update README, database-mode/secrets/deployment documentation and examples to
show RabbitMQ and Redis in both modes, their host placement, resource needs,
credentials, TLS, retained volumes, and scoped reset commands. Explain that
AWS RDS eligibility does not make RabbitMQ/Redis hosting or the whole project
free. Keep the completed-step history, but treat this active plan as the source
of truth for subsequent work.
