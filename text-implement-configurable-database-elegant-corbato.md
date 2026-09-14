# Configurable database hosting (`default_db`)

## Implementation progress (historical record)

The entries below describe work actually performed. The RabbitMQ/Redis decision
on 2026-09-14 supersedes earlier PGMQ, managed-queue, and PostgreSQL-session
targets. Completed code has not yet been converted to the new architecture.

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

The architecture revision updated instructions only. Existing PGMQ/session SQL
and application code are not yet removed, and no resources are deployed or
destroyed. Subsequent infrastructure progress is recorded above.

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

Apply this requirement consistently to the AWS schema, cloud example,
Terraform module, and tests. Reject settings outside this configuration
with an actionable error rather than provisioning a more expensive RDS
instance.

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

Add optional `default_db` (enum `["application","cloud"]`, no schema default),
`database_profile` (a nonempty string selecting a named profile), and
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

The existing omitted-`default_db` compatibility behavior remains application
mode; this is separate from profile settings. The real config explicitly
sets `default_db` to `application` while its database VM remains configured.

Root `allOf` additions:
- `default_db == "cloud"` ⇒ `database_profile` and a nonempty
  `database_profile_map` required, and no `vms.*` entry may
  have `role: "database"` (enforced via
  `"vms": { "additionalProperties": { "properties": { "role": { "not": { "const": "database" } } } } } }`,
  which composes correctly under `allOf` since every `vms` key must satisfy
  both this and the existing `$ref: "#/$defs/vm"`).
- `default_db != "cloud"` (including omitted) ⇒ `vms` must contain at least
  one `role: "database"` entry — this makes today's *implicit* requirement
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
`default_db` values, and preserves exact current behavior when `default_db`
is omitted (the new "must have a database VM" rule is already true of every
existing config).

## Example configs and docs (new files)

- `project-config.example.json` (repo root, **already exists** — leave its
  application-mode shape as-is; `default_db` stays omitted, demonstrating
  the default) — no change needed beyond confirming it still validates
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
Honor the user's direct `default_db` access choice; reconcile the repository
example and schema's omitted-setting promise before calling compatibility
complete. Do not silently insert defaults for profile fields.

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
instead. Keep this choice documented and covered by broker integration tests.

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
  script/transaction. Test concurrent get/update behavior.
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

## Monitoring and tests

Replace PGMQ health assumptions with RabbitMQ connectivity/consumer readiness
and Redis session-store readiness. Monitor broker queue depth, unacknowledged
messages, retry/failure queues, outbox age, and Redis memory/persistence errors.
Remove local-PostgreSQL monitoring assumptions only where managed mode applies.

Keep schema/profile tests and existing Terraform module checks. Replace planned
SQS/Pub/Sub mocks, IAM tests, and pg_cron session tests with:

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

Continue with reviewable parts, updating this document after each completed
part with changes, decisions, checks, and limitations:

1. RDS and Cloud SQL infrastructure modules are implemented locally. Wire
   their connection outputs, CA bundles, and administrator secrets into Ansible
   and create restricted runtime roles; retain database profile constraints.
2. Add explicit RabbitMQ/Redis configuration, secrets mappings, network access,
   and Compose/Ansible service deployment based on the historical layout.
3. Replace PGMQ publishing/consumption with RabbitMQ, keeping the durable
   outbox and implementing reliable confirms, retries, and consumer ACKs.
4. Replace PostgreSQL UI sessions with Redis and native TTL.
5. Reconcile migrations/database images, remove obsolete adapter dependencies,
   scheduler configuration and monitoring, and update service connection roles.
6. Implement coordinated cutover/reset, configuration
   examples, and operator documentation. Include runtime compatibility/example
   reconciliation for the user's explicit `default_db` decision.

## Execution boundaries and documentation

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
