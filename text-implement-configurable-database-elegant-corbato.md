# Configurable database hosting — implementation and deployment handoff

Last updated: 2026-09-16. This document keeps current decisions and deployment
progress for subsequent chats. Detailed procedures belong in the linked runbooks.

## Current state and next action

**Step 18 is in progress: AWS / prod / cloud database.** Terraform provisioning,
image publication, secret uploads, and SSH checks are complete. Application
deployment has not yet completed successfully.

The latest run appeared stuck converting the CloudWatch Agent public GPG key.
The local fix is applied; stop the old run and rerun the deployment command
below. Await the recap before claiming the application works. GCP has not been
live deployed or verified in this work.

## Decisions to preserve

- `default_db` is required: `application` means PostgreSQL in a database VM
  container; `cloud` means AWS RDS or GCP Cloud SQL. It selects only database
  hosting. Cloud mode forbids database-role VMs.
- Use RabbitMQ for Fetcher-to-History messages and Redis for UI sessions in
  both database modes and on both providers. No SQS, Pub/Sub, PGMQ, or
  PostgreSQL-backed UI sessions. UI obtains prices through History.
- All selected infrastructure/profile settings come explicitly from JSON.
  No fallback database mode, profile, or sizing values. Keep the existing
  schema checks; the user declined extra custom lookup validation.
- The user declined automated tests. Do not add, restore, or run them without
  a new request. Static checks and actual deployment observations are separate.
- Use the real Desktop config directly; do not create a temporary config copy.
- Database-mode switches intentionally start with fresh data; no data transfer.
  The coordinated cutover stops producers, consumer, and UI before changing
  stores and discards old queued/session state. Follow the scoped runbook.
  Ordinary redeploys retain persistent volumes; do not reset them incidentally.
- The user cannot push to `main` or `develop`. Publish images by pushing a
  new `v*` tag referencing the intended committed source. Uncommitted edits
  are not included in GitHub builds.
- Use the shared organization GHCR namespace. Personal tags select a source
  revision; they do not make packages private to their tag author. Pull access
  depends on package visibility, organization policy, and the pull token.
- Current AWS deployment is authorized. The user explicitly authorized deleting
  the old database without backup. Do not infer authorization to provision GCP,
  every provider/mode combination, or another destructive reset.
- Update this document after each completed step, material change, or decision.
  Distinguish local implementation, user-supplied output, and live verification.

## Architecture and host placement

| Component | Host / endpoint | Access |
|---|---|---|
| Bastion | `oilscope-prod-bastion`, public `35.157.234.183` | SSH port 22, user `operator` |
| Fetcher | `oilscope-prod-fetcher`, private `10.10.1.12` | Publishes observations through durable DB outbox |
| History + RabbitMQ | `oilscope-prod-history`, private `10.10.1.11` | RabbitMQ authenticated TLS port 5671 |
| UI + Redis + reverse proxy | `oilscope-prod-ui`, private `10.10.0.13`, public `52.28.215.30` | Redis in the local Docker network |
| PostgreSQL | `oilscope-prod-database.c5q000geouyp.eu-central-1.rds.amazonaws.com:5432` | Private RDS, database `oil_tracker` |

These are configured placements; the complete application runtime is still
awaiting deployment verification. Public hostname: `oilscope.skynet-zrg.pp.ua`.
DNS/HTTPS and external health have not yet been confirmed for this deployment.

PostgreSQL stores price observations and the durable publishing outbox.
Outbox inserts explicitly use `status='pending'` and include payload; mark sent
only after broker confirmation and successful routing. Persist retry counters
and next-attempt time, cap backoff exponents, and bound publish attempts/batches.
History acknowledges only after its DB transaction commits; its unique
observation key makes redelivery safe. RabbitMQ uses durable quorum queues,
confirmed retry/dead-letter publishing, and at-least-once delayed forwarding.
Single-host RabbitMQ is not a highly available cluster.

Redis stores JSON preferences with native sliding TTL and hashed session keys;
AOF persists session data across ordinary redeploys. UI health checks Redis and
History. There is no SQL UI-session cleanup job or scheduler database contract.

PostgreSQL connections use `sslmode=verify-full` with mounted CA trust material.
AWS uses the RDS DNS endpoint and public AWS CA bundle. The implemented GCP
module uses private services access, shared CA, and private DNS matching the
certificate SAN; provider plumbing remains live-unverified.

## Implemented work

| Steps | Final result |
|---|---|
| 1–4 | Required DB mode, explicit AWS/GCP profile dictionaries and schema relationships; extra custom validation skipped |
| 5 | Idempotent common migrations and durable outbox schema; retired active PGMQ, SQL sessions, and cron setup |
| 6 | AWS RDS networking/database module and GCP Cloud SQL/private-networking module; profiles read directly from config |
| 7 | Ansible connection/CA wiring, managed migrations, separate runtime roles and grants, RabbitMQ and Redis integration |
| 8–11 | Coordinated cutover/reconciliation, required mode, removal of obsolete GCP auto-deploy, bounded RabbitMQ publishing/cancellation |
| 12–13 | Configuration/deployment contracts and scoped cutover/reset runbook |
| 14 | Standalone local Compose restoration declined by user |
| 15–16 | Rebuilt frontend, Redis wording, readiness/outbox diagnostics, dependency inspection and monitoring docs |
| 17 | Committed source, tag-triggered GHCR publication, real config update and reviewed AWS deployment plan |
| 18 | AWS provisioned; secret uploads and SSH verified; application deployment and runtime verification pending |
| 19 | Remaining provider/mode and cutover coverage pending; provision only separately authorized targets |

Monitoring dashboards now compare all VMs on each metric chart instead of
separate CPU/etc. charts per host. AWS uses consistent explicit colors; GCP
uses one series per VM. Per-VM alarms remain. Dependency health/inspection is
available, but dedicated RDS/RabbitMQ/Redis/outbox time-series panels are not
implemented by this change.

Migrations rerun SQL files on each deployment without an applied-migrations
ledger, so SQL must be idempotent. Migration 006 includes a guarded constraint,
nullable payload with a pending-payload check, and persisted retry fields.
Cloud migration runs from History before applications, includes fresh-host
prerequisites, creates roles before tables, reconciles grants after migration,
and verifies restricted runtime access. No cron scheduling is needed.

## Active configuration, images, and credentials

- Real config: `/Users/pavlo/Desktop/project-config.new.json`.
- Full Terraform outputs: `/Users/pavlo/Desktop/terraform-outputs.aws.json`.
- Terraform directory: `infrastructure/terraform`; Ansible environment: `.venv-ansible`.
- AWS account `441955873558`, operator IAM user `oilscope-admin`, region
  `eu-central-1`, environment `prod`, profile `economy`, DB mode `cloud`.
- RDS profile: `db.t4g.micro`, PostgreSQL major 18, 20 GiB `gp2`, Single-AZ,
  autoscaling limit 0, one-day backups. This targets Free Tier eligibility;
  account eligibility/credits and aggregate usage determine actual charges.
  Other project resources are not made free. See [database modes](docs/database-modes.md).
- GCP economy mapping is configured for `db-f1-micro`, `ENTERPRISE`,
  `POSTGRES_18`, 10 GiB `PD_SSD`, no autoresize, `ZONAL`, one retained backup.
  It is a low-cost profile, not free hosting; live compatibility remains unverified.
- Registry base: `ghcr.io/ua-academy-projects/push-and-pray`.
- Image/source commit: `42e84f633f10101aaf3f2fa2aa18932faadb183c`.
- Published tag: `v-pavlo-20260915-1`; successful Actions run `34956386777`.
  Images are `<registry-base>/{fetcher,history,ui,database}:<full-commit-sha>`.
  The working branch is `monitoring`; pushing its tag uploaded the source commit
  without pushing the branch or protected branches. Later local Ansible fixes
  do not require rebuilding application images.

Published manifest digests:

```text
fetcher  sha256:a60a637b45b5bbe7b68df3c4717fb980ccfbbb9520c269f54e3498b715e1f166
history  sha256:ef2dddc648b59ca5808f4c8b795e016a8fb704f273672d285ae94646f5557b92
ui       sha256:42793f38ab0a041a55b914ae3cdcdbe2ace9843d52a9a1464a6eb9b49477ed4d
database sha256:3054116b5d4d6604410e68772577ddb06853e269a5341b3ea976b1f7866b596e
```

| PostgreSQL login | Credential source / purpose |
|---|---|
| `oil_tracker_admin` | RDS-generated password; AWS-managed secret ARN in `aws_database_connection.value.admin_secret_arn`; migration/manual administration |
| `oil_tracker_fetcher` | `oilscope-prod-db-password-fetcher`; restricted outbox DML |
| `oil_tracker_history` | `oilscope-prod-db-password-history`; restricted observation DML |

UI has no PostgreSQL login. Do not reuse Fetcher/History passwords: predictable
separate usernames with a shared password defeat their intended separation.
Other uploaded secrets: `oilscope-ghcr-token`, `oilscope-oilpriceapi-key`,
`oilscope-prod-rabbitmq-password`, `oilscope-prod-redis-password`.

The controller reads administrator/runtime secrets for migration using operator
credentials. Workload VMs read only their scoped runtime/registry secrets;
no RDS administrator secret read access is granted to them. Secret values
are not recorded here. AWS session exports in the user's terminal are not
inherited by Codex tool processes; a tool authentication failure does not prove
that the user's terminal credentials expired.

## Deployment evidence and latest fixes

- **2026-09-15:** reviewed saved plan: 54 add, 2 change, 3 destroy. User authorized
  old `infra` database VM/EBS deletion without backup and applied it. Post-apply
  Terraform state records private encrypted RDS as available, actual PG 18.3,
  and the old database VM absent. Four existing EC2 instances were retained.
  This evidence comes from Terraform state/provider results, not a separate
  live AWS API verification from Codex.
- **2026-09-16:** full outputs exported; six workload secret versions uploaded.
  User recap: `ok=39 changed=14 unreachable=0 failed=0`. Temporary payload cleaned.
- **2026-09-16:** user completed EC2 start/wait commands. All four inventory hosts
  subsequently returned SSH `SUCCESS` / `ping: pong`, including workloads through
  the bastion. `operator`'s configured public key matches
  `/Users/pavlo/.ssh/petroscope_gcp_ed25519.pub`; no private-key contents inspected.
  Deprecation/reserved `tags` and Python 3.14 discovery warnings did not block SSH.
- **First deployment failure:** History monitoring hit a self-referencing
  `monitoring_agent_config_path` role parameter. History recap:
  `ok=142 changed=21 failed=1`. Removed the recursion from all four playbooks.
  This was a partial deployment, not evidence of full application readiness.
- **Input simplification:** monitoring now reads the required
  `terraform_outputs_path` directly, selecting its provider's monitoring output.
  One complete output file and one CLI argument serve DB and monitoring roles,
  including application DB mode. Updated role docs/comments/changelog and existing
  fixture invocations; no new tests added or run.
- **Latest stall:** GPG keyring conversion lacked unattended overwrite options.
  Added `--batch --yes --no-tty`; fingerprint inspection uses `--batch --no-tty`.
  Fingerprint pinning/signature verification remain enabled. Overwrite prompting
  is the likely cause, not a confirmed remote process diagnosis. Changed YAML
  parses and whitespace checks pass. Successful rerun is still awaiting evidence.

The installed collection at
`~/.ansible/collections/ansible_collections/oilscope/platform` is a symlink to
`infrastructure/ansible/oilscope/platform`; local role edits apply on the next run
without collection reinstall. They do not modify an already running task.

## Next deployment command

Use the activated Ansible environment and the terminal with valid AWS credentials.
Abort any old stuck run first (Ctrl+C, then `A` if prompted).

```bash
cd /Users/pavlo/Documents/Projects/Softserve/2
export OILSCOPE_PROJECT_CONFIG=/Users/pavlo/Desktop/project-config.new.json
export OILSCOPE_SSH_USER=operator
export OILSCOPE_SSH_KEY=/Users/pavlo/.ssh/petroscope_gcp_ed25519

infrastructure/ansible/deploy.sh oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path="$OILSCOPE_PROJECT_CONFIG" \
  -e terraform_outputs_path=/Users/pavlo/Desktop/terraform-outputs.aws.json
```

Order: local DB play skips in cloud mode → managed migration from History →
RabbitMQ → History → Fetcher → UI including Redis/proxy. Do not use a limit
that omits prerequisites. Await recap with no failed/unreachable hosts.

## Remaining work

1. Finish deployment; capture recap and resolve the first failure if any.
2. Verify real RDS TLS/private access, migration/grants, service health, and image
   pulls. Do not infer runtime user creation solely from partial task counts.
3. Observe Fetcher → outbox → confirmed RabbitMQ publish → History DB insert.
   Confirm UI price reads and Redis session/preferences persistence/expiration.
4. Check public DNS/HTTPS/health and actual dashboard/log/agent data. Distinguish
   temporary bootstrap alarms from persistent faults.
5. Record deployed image SHA, actual observations, and any limitations; then
   mark Step 18 complete. Keep unexercised provider/mode combinations unverified.
6. Step 19: perform only separately authorized GCP/provider-mode/cutover checks.
   Fresh provisioning does not prove upgrade or destructive switch safety.
   Optional removal of retired SQL objects is outside normal deployment.

## Manual database access

RDS is private and its security group accepts PostgreSQL only from Fetcher and
History. Laptop access goes through bastion → History → RDS, not directly from
bastion. Retrieve the administrator password from the RDS-managed secret in
AWS Console; do not paste it into chats.

Leave this SSH tunnel running:

```bash
ssh -N -i "$OILSCOPE_SSH_KEY" \
  -o "ProxyCommand=ssh -i $OILSCOPE_SSH_KEY -W %h:%p operator@35.157.234.183" \
  -L 127.0.0.1:15432:oilscope-prod-database.c5q000geouyp.eu-central-1.rds.amazonaws.com:5432 \
  operator@10.10.1.11
```

Download [AWS's CA bundle](https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem).
For psql use the RDS hostname for certificate verification and `hostaddr` for
the tunnel; replace the CA path with the downloaded file:

```bash
psql "host=oilscope-prod-database.c5q000geouyp.eu-central-1.rds.amazonaws.com hostaddr=127.0.0.1 port=15432 dbname=oil_tracker user=oil_tracker_admin sslmode=verify-full sslrootcert=/absolute/path/global-bundle.pem" -W
```

No manual connection has been verified in this work.

## Detailed references

- [Architecture and development](README.md)
- [Database modes, TLS, cutover and scoped reset](docs/database-modes.md)
- [Secret upload, retrieval and rotation](docs/secrets.md)
- [Supported Compose deployment](docs/supported-compose-deployment.md)
- [Monitoring, readiness and dependency inspection](docs/monitoring.md)
- [Ansible inventory and bastion access](infrastructure/ansible/inventory/README.md)

**Documentation cleanup (2026-09-16):** consolidated superseded plans, repeated
review logs, and obsolete blockers into this current handoff. Preserved decisions,
image digests, deployment evidence, latest fixes, commands and remaining work.
No implementation, credential, cloud resource, or deployment state changed.
