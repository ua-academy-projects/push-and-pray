# Monitoring and budgets

Terraform defines the cloud resources; Ansible installs the agents and a small
Python collector on workload VMs. **Bastion is excluded** from dashboards,
alarms, agent publisher permissions, application collection and EC2 detailed
monitoring. No additional credentials are stored in collector configuration.

## Enable the features

Merge these settings into your existing project JSON, replacing the email and
hostname. The checked-in examples keep the new paid features disabled.

```json
{
  "monitoring": {
    "enabled": true,
    "email_recipients": ["ops@example.com"],
    "logs_enabled": true,
    "service_logs_enabled": true,
    "agent_metrics_enabled": true,
    "application_metrics_enabled": true,
    "database_metrics_enabled": true,
    "detailed_monitoring_enabled": true,
    "alarms_enabled": true,
    "dashboard_enabled": true,
    "log_retention_days": 7,
    "synthetics": {
      "enabled": true,
      "clouds": ["aws", "gcp"],
      "hostname": "your-site.pp.ua",
      "path": "/health",
      "period_minutes": 5,
      "browser_enabled": true
    }
  },
  "budgets": {
    "aws": {
      "enabled": true,
      "monthly_amount": 100,
      "currency": "USD",
      "actual_thresholds": [50, 100],
      "email_recipients": ["billing@example.com"]
    },
    "gcp": {
      "enabled": true,
      "billing_account_id": "000000-111111-222222",
      "monthly_amount": 100,
      "currency": "USD",
      "actual_thresholds": [50, 100],
      "email_recipients": ["billing@example.com"]
    }
  }
}
```

Enable only the clouds you use for budgets/probes. GCP needs an actual
`clouds.gcp.project_id`; its budget also needs the billing account ID and
permission to manage that account's budgets. Currency must match that account.
Budget recipients are independent of `monitoring.email_recipients`.

`synthetics.clouds` chooses **where probes run**, not where the application is
hosted. Null/omitted preserves selection based on workload VM presence. Explicit
`["aws"]` can run an AWS browser probe against a GCP-only deployment; explicit
`["gcp"]` can run GCP uptime checks against an AWS-only deployment. Both probe the
same configured public hostname. GCP uses native HTTPS/dependency uptime checks;
the optional browser journey runs in AWS, so `browser_enabled=true` requires AWS
probe selection and a period of at least three minutes. The default is five.

The AWS browser checks HTTPS health, a rendered chart with observations, the
Clear control, persistence after reload through Redis, and Select all. Each run
uses its own anonymous session. Cloudflare must allow the probes to reach the
application; a challenge page will correctly fail the journey.

## Signals and defaults

Host charts compare workload VMs by CPU, memory, disk, network and status/uptime.
Guest metrics use CloudWatch Agent/Ops Agent. Native database metrics require
`database.mode=cloud` and `database_metrics_enabled`; they do not depend on a
self-hosted database VM.

| Signal | Source | Default alert threshold |
| --- | --- | --- |
| Collector failed / service unhealthy | Minute collector; workload health/readiness | 1 |
| Outbox pending events | Fetcher `/health`, including 503 diagnostics | 100 |
| Oldest pending outbox event | Fetcher `/health` | 600 seconds |
| RabbitMQ ready + retry messages | Local `rabbitmqctl`, read-only | 1,000 |
| RabbitMQ unacknowledged messages | Main + retry queues | 100 |
| RabbitMQ dead messages | Dead queue, ready + unacknowledged | 1 |
| Redis memory | `INFO`, used_memory / maxmemory | 85% |
| Redis persistence failed | AOF enabled, write/rewrite and RDB status | 1 |
| Persisted data age | Oldest latest `fetched_at` across WTI, Brent, RBOB | 28,800 seconds |
| RDS / Cloud SQL CPU | Provider-native metrics | 80% |
| RDS free storage | Provider-native metric | Below 1 GiB |
| Cloud SQL disk utilization | Provider-native metric | 85% |
| Database connections | RDS / Cloud SQL PostgreSQL metrics | 80 |

Threshold settings are listed in `project-config.example.json` and the JSON
schema. Freshness measures ingestion, not the market's source observation time;
tune it to your fetch schedule. RDS charts also show read/write latency and IOPS;
Cloud SQL charts show read/write operation rates. These are operational metrics,
not query-level profiling or a database backup monitor.

Application alarms require sustained threshold breaches (roughly 5–10 minutes).
AWS treats missing application samples as breaching. GCP adds a 10-minute
collector-absence policy and marks missing established application/database
series active. GCP absence policies need previously observed data: verify initial
samples after deployment instead of treating an empty dashboard as healthy.
A failed diagnostic emits `CollectionFailed=1`; unavailable values are omitted,
never replaced with healthy zeroes. Missing instruments fail collection.

The collector runs as a root systemd oneshot (`oilscope-metrics.timer`) because
local Docker diagnostics require access to the daemon. It reads existing
container credentials internally for Redis, never exports them, and logs only
failed probe names. On AWS it writes bounded, rotated EMF events to
`/var/log/oilscope/application-metrics.jsonl`, shipped by CloudWatch Agent. On GCP
it publishes custom GAUGE metrics using the VM service account metadata token.
No inbound monitoring ports are opened. RabbitMQ resides on History and Redis
on UI, matching the existing deployment topology.

## Central logs

`logs_enabled` retains existing Traefik JSON access logs and HTTP 500/5xx metrics.
`service_logs_enabled` independently collects Docker stdout/stderr for UI,
History, Fetcher, PostgreSQL (application mode), RabbitMQ, Redis and Traefik.
Compose explicitly selects `json-file`, with three 10 MB local files per
container. Ansible creates explicit per-service symlinks for CloudWatch Agent
rather than relying on a wildcard that might follow only one container log.
GCP Ops Agent reads the Docker JSON files directly.

AWS sends these to `/<project>/<environment>/application`; metric events use
separate streams from service logs. GCP routes them into a dedicated application
Logging bucket and excludes that stream from `_Default` after the sink exists.
Both destinations use `log_retention_days`. Logs include container output, not
container environment dumps. Do not make application code log secret values.

## Budgets

AWS's budget covers the **whole AWS account**. GCP's budget covers the configured
**project** within its billing account. They each default to 100 currency units
per month, with actual-spend notifications at fixed amounts — $50 and $100 by
default — rather than percentages of the budget: `actual_thresholds` is a list
of absolute currency amounts (in the budget's own `currency`) to notify at, not
fractions of `monthly_amount`. AWS supports this natively (`threshold_type =
"ABSOLUTE_VALUE"`); GCP's API only accepts a percentage, so its module converts
each configured amount into `amount / monthly_amount` internally — set GCP's own
`monthly_amount` accordingly if you want its notifications to land on the same
dollar figures as AWS's. They are independent budgets, not a combined $100
multicloud cap, and remain available with `monitoring.enabled=false` or no
workload VMs. Billing data and notifications can be delayed; these are alerts,
not hard spending limits or automatic shutdowns. Credits/refunds can reduce the
spend tracked by these budgets.

Find them in AWS **Billing and Cost Management → Budgets**, and GCP **Billing →
Budgets & alerts**. Confirm requested email subscriptions/channels and check
recipient delivery. `terraform output -json budgets` reports their identities,
scopes, configured amounts and thresholds without exposing credentials.

## Deploy and verify

1. Set real configuration values and valid AWS/GCP credentials. Run `terraform
   init`, then `terraform plan` using `-var=project_config_path=/absolute/path/config.json`.
   Review the resource changes, then apply the plan. Existing deployments may
   need imports if matching budget/log resources were created manually.
2. Export fresh outputs: `terraform -chdir=infrastructure/terraform output -json
   > /absolute/path/terraform-outputs.json`. Rebuild/install the Ansible collection
   as described in its README and run the workload deployment with your usual
   inventory, `project_config_path` and `terraform_outputs_path`.
3. Verify agents, `systemctl status oilscope-metrics.timer` and
   `journalctl -u oilscope-metrics.service` on workloads. Confirm fresh custom
   metrics and every service log stream in both cloud consoles. Verify no bastion
   appears on operational dashboards.
4. Confirm budget recipients and operational SNS/channel subscriptions. Check
   browser canary runs and the expected database dimensions. In a test deployment,
   induce and restore a controlled failure to verify alert delivery/recovery.

Disabling application metrics stops its timer on the next Ansible run. Disabling
Terraform flags alone removes cloud resources/permissions; run Ansible too.
Docker log links are refreshed after service redeployments. New features add
potential log ingestion, custom-metric, alarm, dashboard, detailed EC2 metric and
synthetic costs; enabling a budget does not enable those features automatically.

## Local validation

```sh
terraform -chdir=infrastructure/terraform init -backend=false
terraform -chdir=infrastructure/terraform validate
terraform -chdir=infrastructure/terraform test
uv run pytest infrastructure/monitoring/tests
node --test infrastructure/terraform/modules/aws/monitoring/canary/health.test.js
```

Terraform tests use mocked providers and never create live resources. Collector
tests cover unavailable diagnostics, backlog, persistence failure, stale/missing
data, and cloud payload contracts. Browser runtime, cloud IAM propagation and
actual email delivery additionally require deployment verification.

Implementation references: [AWS embedded metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format_Specification.html),
[GCP time-series writes](https://cloud.google.com/monitoring/api/ref_v3/rest/v3/projects.timeSeries/create),
[AWS Synthetics browser API](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Canaries_Library_Nodejs.html).

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
