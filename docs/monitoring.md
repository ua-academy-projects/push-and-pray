# Monitoring and budgets

Terraform defines the cloud resources; Ansible installs the agents and a small
Python collector on workload VMs. **Bastion is excluded** from dashboards,
alarms, agent publisher permissions, application collection and EC2 detailed
monitoring. No additional credentials are stored in collector configuration.

Azure is the one exception to the agent split. The Azure Monitor Agent is a VM
extension configured from cloud-side data collection rules, not a file dropped
on the host, so Terraform owns the extension, the rules and their associations.
Ansible prepares the log files the rules read and verifies the agent; it must
not create a competing rule. `azure_monitoring.agent_configurations` therefore
describes what Terraform already created rather than something to install.

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
    },
    "azure": {
      "enabled": true,
      "monthly_amount": 100,
      "currency": "USD",
      "actual_thresholds": [50, 100],
      "email_recipients": ["billing@example.com"],
      "start_date": "2026-10-01T00:00:00Z"
    }
  }
}
```

Enable only the clouds you use for budgets/probes. GCP needs an actual
`clouds.gcp.project_id`; its budget also needs the billing account ID and
permission to manage that account's budgets. Currency must match that account.
Azure's budget is scoped to `clouds.azure.resource_group_name`, so enabling it
creates that resource group even with no Azure VMs. Budget recipients are
independent of `monitoring.email_recipients`.

`log_retention_days: 7` above is a CloudWatch value. Azure's workspace accepts
30–730 days only; where the shared enum and Azure's range overlap you can use
30, 60, 90, 120, 150, 180, 365, 400 or 545.

`synthetics.clouds` chooses **where probes run**, not where the application is
hosted. Null/omitted preserves selection based on workload VM presence. Explicit
`["aws"]` can run an AWS browser probe against a GCP-only deployment; explicit
`["gcp"]` can run GCP uptime checks against an AWS-only deployment. Both probe the
same configured public hostname. GCP uses native HTTPS/dependency uptime checks;
the optional browser journey runs in AWS, so `browser_enabled=true` requires AWS
probe selection and a period of at least three minutes. The default is five.

Azure runs an Application Insights **standard** availability test: an HTTPS
request with a status-code check, a certificate check and a text match on `ok`.
It is neither AWS's browser journey nor GCP's `$.status` JSON-path assertion, so
`browser_enabled` stays AWS-only and the text match is a weaker stand-in for
GCP's predicate. Azure accepts `period_minutes` of 5, 10 or 15 only — the shared
enum's 30 and 60 have no Azure equivalent.

`detailed_monitoring_enabled` is an EC2 setting. GCP already ignores it, and so
does Azure; there is no paid per-VM sampling tier to map it onto.

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
Azure runs the application and guest signals as log queries over Log Analytics,
with a separate row-counting rule per VM that fires when the agent or the
collector stops reporting — a never-seen measurement does not read as a healthy
zero. Azure's workspace retention is 30–730 days, so an Azure deployment has to
set `log_retention_days` to at least 30; the shared default of 7 is a CloudWatch
value that Azure rejects.
A failed diagnostic emits `CollectionFailed=1`; unavailable values are omitted,
never replaced with healthy zeroes. Missing instruments fail collection.

The collector runs as a root systemd oneshot (`oilscope-metrics.timer`) because
local Docker diagnostics require access to the daemon. It reads existing
container credentials internally for Redis, never exports them, and logs only
failed probe names. On AWS it writes bounded, rotated EMF events to
`/var/log/oilscope/application-metrics.jsonl`, shipped by CloudWatch Agent. On GCP
it publishes custom GAUGE metrics using the VM service account metadata token.
On Azure it writes flat JSON lines to the same path — one
`{Timestamp, VMKey, Role, Metric, Value}` object per measurement — which the
Azure Monitor Agent ingests into the `OilscopeMetrics_CL` table; Azure has no
per-VM custom metric namespace to publish into, and nested records will not
ingest. No inbound monitoring ports are opened. RabbitMQ resides on History and Redis
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
Azure ingests them into three custom tables in one workspace —
`OilscopeAccess_CL` for Traefik, `OilscopeService_CL` for container output and
`OilscopeMetrics_CL` for the collector — created with their schemas by Terraform
along with one data collection rule per role. All destinations use
`log_retention_days`. Logs include container output, not
container environment dumps. Do not make application code log secret values.

## Budgets

AWS's budget covers the **whole AWS account**. GCP's budget covers the configured
**project** within its billing account. Azure's covers the deployment's own
**resource group** — narrower than either, so spending elsewhere in the
subscription is not counted. They each default to 100 currency units
per month, with actual-spend notifications at fixed amounts — $50 and $100 by
default — rather than percentages of the budget: `actual_thresholds` is a list
of absolute currency amounts (in the budget's own `currency`) to notify at, not
fractions of `monthly_amount`. AWS supports this natively (`threshold_type =
"ABSOLUTE_VALUE"`); GCP's API only accepts a percentage, so its module converts
each configured amount into `amount / monthly_amount` internally, and Azure's
does the same conversion into `100 * amount / monthly_amount` — set each
budget's own `monthly_amount` accordingly if you want its notifications to land
on the same dollar figures as AWS's. Azure additionally needs an explicit
first-of-month `start_date`: the API requires a start date, and a computed one
would replace the budget on every apply. Its `currency` is recorded but not
sent, because Azure bills in the subscription's own currency and the budget
resource takes no currency argument. They are independent budgets, not a
combined $100 multicloud cap, and remain available with `monitoring.enabled=false` or no
workload VMs. Billing data and notifications can be delayed; these are alerts,
not hard spending limits or automatic shutdowns. Credits/refunds can reduce the
spend tracked by these budgets.

Find them in AWS **Billing and Cost Management → Budgets**, GCP **Billing →
Budgets & alerts**, and Azure **Cost Management → Budgets**. Confirm requested email subscriptions/channels and check
recipient delivery. `terraform output -json budgets` reports their identities,
scopes, configured amounts and thresholds without exposing credentials.

## Deploy and verify

1. Set real configuration values and valid credentials. Every plan in this root
   needs an Azure subscription resolvable from `ARM_SUBSCRIPTION_ID` or
   `az login`, even for an AWS or GCP deployment — see the README. Run
   `terraform init`, then `terraform plan` using
   `-var=project_config_path=/absolute/path/config.json`.
   Review the resource changes, then apply the plan. Existing deployments may
   need imports if matching budget/log resources were created manually.
2. Export fresh outputs: `terraform -chdir=infrastructure/terraform output -json
   > /absolute/path/terraform-outputs.json`. Rebuild/install the Ansible collection
   as described in its README and run the workload deployment with your usual
   inventory, `project_config_path` and `terraform_outputs_path`.
3. Verify agents, `systemctl status oilscope-metrics.timer` and
   `journalctl -u oilscope-metrics.service` on workloads. Confirm fresh custom
   metrics and every service log stream in the cloud console. Verify no bastion
   appears on operational dashboards. On Azure the agent is
   `azuremonitoragent.service` — Ansible only checks it, since Terraform
   installed it — and the first samples land in `OilscopeMetrics_CL`,
   `OilscopeAccess_CL` and `OilscopeService_CL` rather than in a metric
   namespace:

   ```kusto
   OilscopeMetrics_CL | summarize count() by VMKey, Metric | order by VMKey asc
   ```
4. Confirm budget recipients and operational SNS/channel/action-group
   subscriptions. AWS and GCP email recipients must confirm a subscription;
   an Azure action group's email receivers do not. Check browser canary runs
   and the expected database dimensions. In a test deployment,
   induce and restore a controlled failure to verify alert delivery/recovery.

Disabling application metrics stops its timer on the next Ansible run. Disabling
Terraform flags alone removes cloud resources/permissions; run Ansible too. On
Azure the reverse also holds and matters more: the agent is a Terraform-owned
VM extension, so Ansible cannot remove it. Re-apply with monitoring disabled —
a run that finds the extension still installed says so rather than stopping a
service the next apply would restart.
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
