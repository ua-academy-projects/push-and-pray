# Terraform cloud monitoring implementation plan

Status: the AWS monitoring module is now implemented locally; see [its README](modules/aws/monitoring/README.md) for the actual interface, defaults, tests, and deployment limits. No infrastructure was applied. The remaining sections retain the broader AWS/GCP design; their illustrative code is not the authoritative implemented interface.
Implement AWS and GCP monitoring through Terraform and the existing deployment system.
Console resource-creation walkthroughs have been removed. Existing resources must be inventoried and imported where appropriate.

## 1. Scope and decisions

- Separate monitoring modules for AWS and GCP; separate budget modules for each cloud.
- Existing VM modules own instance settings, runtime identities, agent permissions, and bootstrap integration.
- Monitoring modules own telemetry destinations, alerts, dashboards, and synthetic checks.
- Budget modules work independently of VM count and monitoring enablement.
- Resolve each VM's cloud from `vm.cloud`, falling back to `default_cloud`; never select all agents using only the default cloud.
- Preserve existing deployments when new settings are absent. Paid features require explicit enablement.
- Operator supplies email addresses. Both clouds use monthly budgets of **100 USD**, with **actual-spend notifications at $50 and $100** (50% and 100%). No shutdown actions.
- Cover CPU, memory, root filesystem usage, infrastructure/application availability, missing telemetry, HTTP 500 and all HTTP 5xx errors.
- Use public `/health` synthetic tests initially. Browser journeys and private service/fetcher freshness probes are separate follow-up work.
- No production application, Terraform configuration, or external JSON is changed by writing this plan.

## 2. Proposed layout and ownership

```text
infrastructure/
├── terraform/
│   ├── monitoring.tf                  # root composition
│   ├── budgets.tf                     # independent root composition
│   ├── project-config.schema.json
│   └── modules/
│       ├── aws/
│       │   ├── vm/                    # extend, preserve current resources
│       │   ├── monitoring/
│       │   │   ├── versions.tf
│       │   │   ├── variables.tf
│       │   │   ├── locals.tf
│       │   │   ├── logs.tf
│       │   │   ├── notifications.tf
│       │   │   ├── alarms.tf
│       │   │   ├── dashboard.tf
│       │   │   ├── synthetics.tf
│       │   │   ├── outputs.tf
│       │   │   └── canary/nodejs/node_modules/health.js
│       │   └── budget/{versions,variables,main,outputs}.tf
│       └── gcp/
│           ├── vm/
│           ├── monitoring/
│           │   ├── versions.tf
│           │   ├── variables.tf
│           │   ├── locals.tf
│           │   ├── logs.tf
│           │   ├── notifications.tf
│           │   ├── alerts.tf
│           │   ├── dashboard.tf
│           │   ├── uptime.tf
│           │   └── outputs.tf
│           └── budget/{versions,variables,main,outputs}.tf
└── ansible/oilscope/platform/
    ├── roles/monitoring_agent/         # existing-VM installation/configuration
    └── roles/compose_project/          # optional Traefik access logging
```

Budget modules own their notification recipients/channels. Do not reference monitoring-module notification outputs from budgets: disabling monitoring must not remove budget notifications.

Provider configuration remains in the root; child modules declare required providers, not credentials or provider configurations. Retain existing pinned AWS/Google versions. If canary packaging uses `archive_file`, add and pin the archive provider and update the lock file during implementation.

## 3. Configuration contract

Proposed additions to `project-config.example.json` (illustrative settings, all opt-in):

```json
{
  "monitoring": {
    "enabled": false,
    "email_recipients": [],
    "agents_enabled": false,
    "logs_enabled": false,
    "alerts_enabled": false,
    "dashboards_enabled": false,
    "collection_interval_seconds": 60,
    "log_retention_days": 7,
    "cpu_threshold_percent": 80,
    "memory_threshold_percent": 85,
    "disk_threshold_percent": 85,
    "aws": { "detailed_monitoring_enabled": false },
    "synthetics": {
      "enabled": false,
      "clouds": [],
      "hostname": "oilscope.example.com",
      "path": "/health",
      "period_seconds": 300,
      "timeout_seconds": 30,
      "aws_runtime_version": ""
    }
  },
  "budgets": {
    "email_recipients": [],
    "aws": {
      "enabled": false,
      "monthly_amount": 100,
      "currency": "USD",
      "actual_thresholds": [0.5, 1.0]
    },
    "gcp": {
      "enabled": false,
      "billing_account_id": "",
      "monthly_amount": 100,
      "currency": "USD",
      "actual_thresholds": [0.5, 1.0]
    }
  }
}
```

Tasks:

1. Add optional schema properties with `additionalProperties: false`, typed booleans/numbers/arrays, positive amounts, percent ranges, and supported collection periods.
2. Normalize defaults once in root locals; existing JSON without these properties must work unchanged. Validate semantic relationships through typed module inputs and preconditions.
3. Require recipients when alerts or budgets are enabled. Limit budget recipient channels to supported provider/API limits (GCP at most five channels).
4. Require agents for memory/disk alerts; require logs for HTTP error metrics; require synthetics before synthetic alarms.
5. Require a hostname and supported pinned AWS runtime only if AWS synthetics is selected. An empty runtime is an invalid enabled configuration, not a working default.
6. Validate budget currency against the GCP billing account. GCP budgets must use that account's currency; do not silently convert a non-USD account to USD.
7. Endpoint checks are explicitly assigned to clouds, independently of where the UI VM runs. Do not create two duplicate paid checks implicitly.
8. Keep secrets and provider credentials out of this JSON and all agent configurations.

Example default normalization (repeat for all schema fields; snippets are not complete modules):

```hcl
locals {
  monitoring = merge({
    enabled                       = false
    email_recipients              = []
    agents_enabled                = false
    logs_enabled                  = false
    alerts_enabled                = false
    dashboards_enabled            = false
    collection_interval_seconds   = 60
    log_retention_days            = 7
    cpu_threshold_percent         = 80
    memory_threshold_percent      = 85
    disk_threshold_percent        = 85
  }, try(local.config.monitoring, {}))

  monitoring_prefix = "${local.config.name_prefix}-${local.config.environment}"
  access_log_group  = "/${local.config.name_prefix}/${local.config.environment}/traefik"
}
```

Nested objects need their own normalization; shallow `merge` does not supply missing nested defaults.

## 4. Root wiring and module interfaces

Retain the existing unconditional VM module calls and their resource addresses. Monitoring modules receive maps keyed by stable configuration VM names; instance IDs are values, never `for_each` keys.

Extend existing VM outputs without removing fields:

```hcl
# Add to each object in AWS output "vms":
instance_id = instance.id
role        = local.aws_vms[name].role

# Add to each object in GCP output "vms":
instance_id = instance.instance_id
zone        = instance.zone
role        = local.gcp_vms[name].role
```

Proposed root composition:

```hcl
module "aws_monitoring" {
  source = "./modules/aws/monitoring"

  enabled        = local.monitoring.enabled
  name_prefix    = local.monitoring_prefix
  region         = local.config.region_map[local.config.region].aws.region
  vms            = module.aws_vm.vms
  settings       = local.monitoring
  log_group_name = local.access_log_group
}

module "gcp_monitoring" {
  source = "./modules/gcp/monitoring"

  enabled     = local.monitoring.enabled
  name_prefix = local.monitoring_prefix
  project_id  = try(local.config.clouds.gcp.project_id, null)
  vms         = module.gcp_vm.vms
  settings    = local.monitoring
}
```

Each module internally gates resources according to feature settings and its VM map. Synthetic resources use explicit cloud selection, so they can monitor a public endpoint without local VMs. Disabled GCP resources must not evaluate a missing project ID through data sources.

Example AWS input contract:

```hcl
variable "vms" {
  type = map(object({
    instance_id = string
    name        = string
    role        = string
    role_name   = string
  }))
}
```

GCP counterpart: `instance_id`, `name`, `role`, `zone`, and `service_account_email`. Define a typed settings object with optional defaults, not `any`, in new modules. Output dashboard identifiers, alarm identifiers, log destination identifiers, and synthetic names for operations.

Avoid dependency cycles: VM bootstrap must not reference monitoring module outputs if that module already consumes VM IDs. Pass deterministic log destination names from root locals. Agents must retry initial publication until destinations/IAM are ready; alternatively provision destinations as a distinct foundation stage before VM rollout.

## 5. Native agents and EC2 base monitoring

### AWS VM module changes

- Set `aws_instance.workload.monitoring` from the explicit detailed-monitoring switch; leave it false by default.
- Attach a nonexclusive IAM policy to each monitored VM's existing role. Initially use `CloudWatchAgentServerPolicy`; later narrow permissions if practical. Never replace secret-access policies or instance profiles.
- Collect memory and root filesystem usage at 60 seconds; avoid duplicate CPU metrics since EC2 already supplies CPU.

```hcl
resource "aws_iam_role_policy_attachment" "monitoring_agent" {
  for_each = var.monitoring_agents_enabled ? local.aws_vms : {}

  role       = aws_iam_role.ec2_role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
```

Use partition-aware ARN construction if expanding beyond the current commercial regions.

Proposed CloudWatch configuration as an HCL value for `jsonencode`:

```hcl
locals {
  agent_metrics = {
    agent = { metrics_collection_interval = 60 }
    metrics = {
      namespace         = "CWAgent"
      append_dimensions = { InstanceId = "$${aws:InstanceId}" }
      metrics_collected = {
        mem = { measurement = ["mem_used_percent"] }
        disk = {
          measurement = ["used_percent"]
          resources   = ["/"]
          drop_device = true
        }
      }
    }
  }
}
```

The doubled dollar sign escapes Terraform interpolation. Published disk dimensions include InstanceId, path, and filesystem type. Do not create InstanceId-only disk alarms against these unaggregated metrics. Discover filesystem type during deployment and supply it as an explicit per-VM setting, or deliberately change the agent contract to publish an InstanceId-only root-disk aggregation. Test the selected contract before writing alarms.

On UI VMs with logging enabled, merge a `logs.logs_collected.files.collect_list` entry containing:

```json
{
  "file_path": "/var/log/oilscope/traefik-access.log",
  "log_group_name": "/oilscope/dev/traefik",
  "log_stream_name": "{instance_id}"
}
```

Render the project/environment log group rather than hardcoding the example.

### GCP VM module changes

Grant additive roles to the existing VM identities:

```hcl
resource "google_project_iam_member" "agent_metrics" {
  for_each = var.monitoring_agents_enabled ? local.gcp_vms : {}
  project  = var.config.clouds.gcp.project_id
  role     = "roles/monitoring.metricWriter"
  member   = "serviceAccount:${google_service_account.workload[each.key].email}"
}

resource "google_project_iam_member" "agent_logs" {
  for_each = var.monitoring_agents_enabled ? local.gcp_vms : {}
  project  = var.config.clouds.gcp.project_id
  role     = "roles/logging.logWriter"
  member   = "serviceAccount:${google_service_account.workload[each.key].email}"
}
```

Preserve the existing `cloud-platform` scopes and SSH metadata. Enable Monitoring/Logging APIs with a single clear owner in the root/foundation layer, before agent deployment. Use `disable_on_destroy = false` for shared project APIs.

Proposed Ops Agent UI logging configuration, merged with existing settings:

```yaml
logging:
  receivers:
    oilscope_access:
      type: files
      include_paths: [/var/log/oilscope/traefik-access.log]
  processors:
    oilscope_json:
      type: parse_json
  service:
    pipelines:
      oilscope_access:
        receivers: [oilscope_access]
        processors: [oilscope_json]
metrics:
  receivers:
    hostmetrics:
      type: hostmetrics
      collection_interval: 60s
  service:
    pipelines:
      default_pipeline:
        receivers: [hostmetrics]
```

### Installation and existing-VM rollout

Terraform provisions agent IAM and startup integration; Ansible installs/configures agents on already-running VMs. Do not use Terraform SSH provisioners or replace VMs to install an agent.

Implementation tasks:

1. Add `monitoring_agent` role with AWS/GCP task files selected from inventory's effective cloud. Unsupported values fail explicitly.
2. Download official Ubuntu packages/repository installers for the detected architecture; pin/review versions and supported OS combinations. Validate downloads using vendor-supported verification.
3. Render JSON/YAML from the same contract used by Terraform. Restart only when configuration changes; enable the agent service at boot.
4. Add health checks that verify the agent process and recent cloud telemetry. Retry transient IAM/API propagation failures with a bounded timeout.
5. If first-boot installation is required, compose AWS `write_files`/`runcmd` with existing SSH cloud-init, and GCP startup metadata with existing metadata. Keep all unrelated bootstrap content intact.
6. AWS user-data changes do not rerun first-boot installation automatically and can cause instance lifecycle changes. Use the Ansible rollout for existing hosts and review Terraform plans for stop/start or replacement.
7. No inbound monitoring ports. Verify NAT/endpoint access for APIs and package downloads; do not silently create new paid NAT gateways or VPC endpoints.

## 6. Traefik logging through the existing deployment

Update the actual Compose template and edge-proxy tasks, controlled by `logs_enabled`:

```yaml
# Proposed additions to Traefik command:
- "--accesslog=true"
- "--accesslog.format=json"
- "--accesslog.filepath=/var/log/oilscope/traefik-access.log"
- "--accesslog.fields.defaultmode=drop"
- "--accesslog.fields.names.StartUTC=keep"
- "--accesslog.fields.names.DownstreamStatus=keep"
- "--accesslog.fields.names.Duration=keep"
- "--accesslog.fields.headers.defaultmode=drop"
# Proposed volume:
# - /var/log/oilscope:/var/log/oilscope
```

Create the directory with suitable owner/mode before starting the proxy. Add size/retention-bounded rotation and a tested file-reopen mechanism. Cloud retention does not bound the VM source file. Test that deployment preserves logging across proxy recreation and rotation.

This application has no ALB: errors come from Traefik logs, not `AWS/ApplicationELB`. UI `/health` can return 503, so retain both exact-500 and all-5xx counters. These counters cover requests through the proxy, not direct private-service traffic.

## 7. AWS monitoring module

### Notifications and logs

```hcl
resource "aws_sns_topic" "alerts" {
  count = local.alerts_enabled ? 1 : 0
  name  = "${var.name_prefix}-monitoring"
}

resource "aws_sns_topic_subscription" "email" {
  for_each  = local.alerts_enabled ? toset(var.settings.email_recipients) : toset([])
  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_log_group" "access" {
  count             = local.logs_enabled ? 1 : 0
  name              = var.log_group_name
  retention_in_days = var.settings.log_retention_days
}

resource "aws_cloudwatch_log_metric_filter" "http" {
  for_each = local.logs_enabled ? {
    HTTP500Count = "{ $.DownstreamStatus = 500 }"
    HTTP5xxCount = "{ $.DownstreamStatus >= 500 && $.DownstreamStatus < 600 }"
  } : {}
  name           = "${var.name_prefix}-${each.key}"
  log_group_name = aws_cloudwatch_log_group.access[0].name
  pattern        = each.value
  metric_transformation {
    name          = each.key
    namespace     = "${var.name_prefix}/HTTP"
    value         = "1"
    default_value = 0
  }
}
```

SNS recipients must confirm email subscriptions; report pending confirmation as an incomplete notification setup, not a Terraform failure. Do not send test notifications until rollout testing is authorized.

### Alarm contract

| Signal | Statistic and threshold | Evaluation | Missing data |
| --- | --- | --- | --- |
| CPUUtilization | Average >= 80% | 2 × 300s | missing |
| mem_used_percent | Average >= 85% | 2 × 300s | missing |
| disk_used_percent per filesystem | Maximum >= 85% | 2 × 300s | missing |
| StatusCheckFailed | Maximum >= 1 | 2 × 60s | breaching for always-on VMs |
| Agent heartbeat from memory | Minimum < 0 | 2 × 300s | breaching |
| HTTP500Count / HTTP5xxCount | Sum >= 1 | 1 × 300s | notBreaching |
| Canary SuccessPercent | Average < 100 | 2 × 300s | breaching while enabled |

The impossible negative-memory threshold makes the separate heartbeat alarm detect absence rather than high usage. Tune maintenance behavior deliberately. Infrastructure status does not replace application availability checks.

Representative per-VM CPU alarm:

```hcl
resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each = local.alerts_enabled ? var.vms : {}

  alarm_name          = "${var.name_prefix}-${each.key}-cpu"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { InstanceId = each.value.instance_id }
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.settings.cpu_threshold_percent
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts[0].arn]
  ok_actions          = [aws_sns_topic.alerts[0].arn]
}
```

Generate corresponding resources from a local map of signal definitions; agent metrics depend on agent enablement and HTTP alarms on log enablement. All resource keys derive from configuration, not unknown IDs.

### Dashboard

```hcl
resource "aws_cloudwatch_dashboard" "operations" {
  count          = local.dashboards_enabled ? 1 : 0
  dashboard_name = "${var.name_prefix}-operations"
  dashboard_body = jsonencode({
    widgets = [{
      type = "metric", x = 0, y = 0, width = 12, height = 6
      properties = {
        title = "CPU by VM", region = var.region, period = 300, stat = "Average"
        metrics = [for name, vm in var.vms :
          ["AWS/EC2", "CPUUtilization", "InstanceId", vm.instance_id, { label = name }]
        ]
      }
    }]
  })
}
```

Expand with memory, disk, status checks, network, applicable CPU credits, HTTP counts, synthetic success/duration, and alarm status. Generate metrics from the same definitions as alarms. Omit disabled-feature widgets and avoid an empty dashboard with no monitored targets.

## 8. GCP monitoring module

### Notifications and HTTP counters

```hcl
resource "google_monitoring_notification_channel" "email" {
  for_each     = local.alerts_enabled ? toset(var.settings.email_recipients) : toset([])
  project      = var.project_id
  display_name = "${var.name_prefix} operations ${each.value}"
  type         = "email"
  labels       = { email_address = each.value }
}

resource "google_logging_metric" "http" {
  for_each = local.logs_enabled ? {
    http500 = "jsonPayload.DownstreamStatus = 500"
    http5xx = "jsonPayload.DownstreamStatus >= 500 AND jsonPayload.DownstreamStatus < 600"
  } : {}
  project = var.project_id
  name    = "${var.name_prefix}-${each.key}"
  filter  = "resource.type=\"gce_instance\" AND log_id(\"oilscope_access\") AND (${local.ui_instance_filter}) AND ${each.value}"
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
  }
}
```

Build `local.ui_instance_filter` as an OR of monitored UI instance IDs. If no local UI exists, omit these metrics. Verify the actual Ops Agent log ID in a test deployment before freezing the filter. Use a dedicated log bucket and sink if seven-day retention is required; prevent duplicate storage in `_Default` with a narrowly scoped exclusion only for these logs. Do not change project-wide retention for unrelated logs.

### Per-VM alert examples

```hcl
resource "google_monitoring_alert_policy" "cpu" {
  for_each     = local.alerts_enabled ? var.vms : {}
  project      = var.project_id
  display_name = "${var.name_prefix}-${each.key}-cpu"
  combiner     = "OR"
  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.name]
  conditions {
    display_name = "CPU sustained high"
    condition_threshold {
      filter          = "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${each.value.instance_id}\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.settings.cpu_threshold_percent / 100
      duration        = "600s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MEAN"
      }
      trigger { count = 1 }
    }
  }
}
```

Add policies for:

- `agent.googleapis.com/memory/percent_used`, selecting `metric.labels.state="used"`, threshold 85.
- `agent.googleapis.com/disk/percent_used`, selecting used state and the intended device/filesystem, threshold 85. Verify agent descriptors/labels against a real sample rather than copying CloudWatch dimensions.
- `condition_absent` on each VM's memory series for 600 seconds, to detect missing agents/stopped hosts after telemetry has been observed.
- HTTP counter metrics `logging.googleapis.com/user/<metric-name>` with `ALIGN_SUM` over 300 seconds, threshold > 0, duration `0s`. Do not use a rate threshold for a count requirement.
- Uptime failures as described below; use infrastructure uptime/absence signals separately from public endpoint health.

Document unit differences: Compute CPU utilization uses 0–1; agent percentage metrics use 0–100. Keep resource filters per VM. Avoid project-wide averages masking one unhealthy VM.

### Dashboard example

```hcl
resource "google_monitoring_dashboard" "operations" {
  count   = local.dashboards_enabled ? 1 : 0
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "${var.name_prefix} operations"
    gridLayout = {
      columns = 2
      widgets = [for name, vm in var.vms : {
        title = "${name} CPU"
        xyChart = {
          dataSets = [{
            plotType = "LINE"
            timeSeriesQuery = {
              timeSeriesFilter = {
                filter = "resource.type=\"gce_instance\" AND resource.labels.instance_id=\"${vm.instance_id}\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\""
                aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_MEAN" }
              }
            }
          }]
        }
      }]
    }
  })
}
```

Expand from the same signal inventory as AWS with native GCP metric units and filters. Include incident/availability information and useful runbook links.

## 9. Synthetic checks

### AWS canary

Package a Node.js API canary using a currently supported pinned runtime. Keep its source under the monitoring module and use `archive_file` to build the runtime-required ZIP layout. The runtime string must be validated against AWS during implementation, not copied from an old example.

```hcl
data "archive_file" "health" {
  count       = local.synthetics_enabled ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/canary"
  output_path = "${path.root}/.terraform/${var.name_prefix}-health.zip"
}

resource "aws_synthetics_canary" "health" {
  count                = local.synthetics_enabled ? 1 : 0
  name                 = "${var.name_prefix}-health"
  artifact_s3_location = "s3://${aws_s3_bucket.canary[0].bucket}/results/"
  execution_role_arn   = aws_iam_role.canary[0].arn
  handler              = "health.handler"
  runtime_version      = var.settings.synthetics.aws_runtime_version
  zip_file             = data.archive_file.health[0].output_path
  start_canary         = true
  success_retention_period = 7
  failure_retention_period = 7
  schedule {
    expression = "rate(5 minutes)"
  }
  run_config {
    timeout_in_seconds = 30
    environment_variables = {
      HEALTH_URL = "https://${var.settings.synthetics.hostname}${var.settings.synthetics.path}"
    }
  }
  depends_on = [aws_iam_role_policy.canary]
}
```

The literal schedule/timeout above illustrates the initial values; implementation renders validated settings. Enforce canary name constraints for the selected runtime/API and use collision-safe shortening if needed.

Proposed handler behavior, using the runtime's Synthetics library:

```javascript
const synthetics = require('Synthetics');
exports.handler = async () => {
  const url = new URL(process.env.HEALTH_URL);
  await synthetics.executeHttpStep('health', {
    hostname: url.hostname,
    protocol: url.protocol,
    port: 443,
    method: 'GET',
    path: url.pathname + url.search
  }, async (response) => {
    if (response.statusCode !== 200) throw new Error(`HTTP ${response.statusCode}`);
    let body = '';
    for await (const chunk of response) body += chunk;
    const result = JSON.parse(body);
    if (result.status !== 'ok' || result.history !== 'connected' || result.sessions !== 'postgresql') {
      throw new Error('Health dependency check failed');
    }
  });
};
```

Validate handler/library compatibility against the pinned runtime before adopting this example. Add a response-size bound and redact captured headers/bodies. Do not record authentication cookies or secrets.

Supporting tasks are mandatory, not implicit in the snippet:

- Private S3 artifact bucket with public-access block, encryption, and seven-day lifecycle expiry; globally unique name.
- Lambda-trusted execution role with scoped artifact/log permissions and namespace-restricted metric publishing; no broad administrator policy.
- Log retention for canary-generated logs and tracking/cleanup of implicit Lambda resources.
- SuccessPercent alarm and duration widget. Keep latency alert optional until a baseline is known.
- Account for ZIP change detection, explicit dependencies, retry policy, and failed cleanup during destroy.

### GCP uptime check

```hcl
resource "google_monitoring_uptime_check_config" "health" {
  count        = local.synthetics_enabled ? 1 : 0
  project      = var.project_id
  display_name = "${var.name_prefix}-health"
  timeout      = "30s"
  period       = "300s"
  http_check {
    path         = var.settings.synthetics.path
    port         = 443
    use_ssl      = true
    validate_ssl = true
    accepted_response_status_codes { status_value = 200 }
  }
  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = var.settings.synthetics.hostname
    }
  }
  content_matchers {
    content = "ok"
    matcher = "MATCHES_JSON_PATH"
    json_path_matcher {
      json_path    = "$.status"
      json_matcher = "EXACT_MATCH"
    }
  }
}
```

GCP currently supports one effective content matcher. The API's HTTP-200 contract covers dependencies; full multi-field validation needs a function-backed synthetic test. Do not describe this as equivalent to a browser journey.

Build an alert scoped to this check's ID on `monitoring.googleapis.com/uptime_check/check_passed`. Align booleans using `ALIGN_NEXT_OLDER`, reduce across checker locations with `REDUCE_COUNT_FALSE`, and alert on at least two failing locations for a sustained window. Validate emitted labels and minimum checker-location coverage. Add a separate absence policy for missing check data; absence is not a false boolean.

## 10. Independent budget modules

Root `budgets.tf` creates each budget based only on that cloud's explicit budget enablement, not monitoring or VM count. Use typed inputs: `enabled`, `name_prefix`, `monthly_amount`, `currency`, `actual_thresholds`, `email_recipients`; GCP also takes project/billing account.

### AWS

```hcl
resource "aws_budgets_budget" "monthly" {
  count        = var.enabled ? 1 : 0
  name         = "${var.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_amount)
  limit_unit   = var.currency
  time_unit    = "MONTHLY"
  dynamic "notification" {
    for_each = var.actual_thresholds
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value * 100
      threshold_type             = "PERCENTAGE"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = var.email_recipients
    }
  }
}
```

No service/tag filter for the first AWS budget: it covers the whole account, including NAT, EBS, IPv4, monitoring, and other services. Name/scope this explicitly so multiple environments do not accidentally create redundant account budgets. Do not attach shutdown actions.

### GCP

```hcl
data "google_project" "budget" {
  count      = var.enabled ? 1 : 0
  project_id = var.project_id
}
resource "google_monitoring_notification_channel" "budget_email" {
  for_each = var.enabled ? toset(var.email_recipients) : toset([])
  project  = var.project_id
  type     = "email"
  labels   = { email_address = each.value }
}
resource "google_billing_budget" "monthly" {
  count           = var.enabled ? 1 : 0
  billing_account = var.billing_account_id
  display_name    = "${var.name_prefix}-monthly"
  budget_filter {
    projects        = ["projects/${data.google_project.budget[0].number}"]
    calendar_period = "MONTH"
  }
  amount {
    specified_amount {
      currency_code = var.currency
      units         = tostring(var.monthly_amount)
    }
  }
  dynamic "threshold_rules" {
    for_each = var.actual_thresholds
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }
  all_updates_rule {
    monitoring_notification_channels = [for channel in google_monitoring_notification_channel.budget_email : channel.name]
    disable_default_iam_recipients    = true
  }
}
```

Require whole-dollar monthly amounts for this `units` example; support `nanos` explicitly if fractional budgets are later allowed. Require at least one recipient before disabling default recipients. Ensure Monitoring/Billing Budgets APIs and billing-account permissions are available independently of VM monitoring. User ADC may require root-provider `billing_project` and `user_project_override`; configure these deliberately, preserving the existing authentication approach.

Budget notifications are delayed spending notifications, not hard caps. Choose and document treatment of credits/tax consistently; display the AWS-account versus GCP-project scope in outputs.

## 11. Cost controls and resource lifecycle

- Keep detailed EC2 monitoring and synthetics disabled until explicitly enabled in configuration.
- Calculate metric series, alarms, log volume, canary runs, artifact storage, and network processing before rollout. Free allowances are account-wide and must not be assumed unused.
- Five VMs × two guest metrics already yields approximately ten custom series before HTTP/synthetic metrics or additional filesystem dimensions.
- One check per five minutes produces 8,640 runs in 30 days; estimate supporting services separately and use current regional pricing.
- Bound both cloud and host retention. Short cloud retention does not eliminate ingestion charges.
- Disabling Terraform resources can destroy log groups/history. Document retention/import/removal behavior, and decide whether logs need a separate persistence switch before implementation.
- Budgets stay enabled independently when monitoring is disabled. Removing all VMs must not remove budget alerts.

## 12. Implementation order and completion criteria

1. **Contract:** add schema/defaults/validation and examples. Confirm old configs still validate and monitoring remains opt-in.
2. **Identity/output changes:** extend VM outputs and add conditional agent permissions without changing resource addresses.
3. **Budget modules:** implement independent AWS/GCP modules, API prerequisites, recipients, $50/$100 thresholds, and scope outputs.
4. **Telemetry destinations:** implement log destinations/retention and API ownership. Resolve dependency ordering before installing agents.
5. **Agents and proxy:** add cloud-selected deployment role, bootstrap integration, minimal logs, and tested rotation. Roll out to existing VMs without replacement.
6. **Monitoring modules:** notifications, per-VM alerts, error metrics, dashboards. Share metric definitions between dashboards/alarms.
7. **Synthetics:** package/pin AWS runtime and artifact resources; configure GCP uptime check and failure/absence alerts.
8. **Import existing resources:** inventory any previously created log groups, agents, budgets, alarms, SNS topics, and dashboards. Import supported resources using actual IDs; do not create duplicates or erase live configuration.
9. **Validate:** run formatting/schema checks and Terraform validation with pinned providers; use targeted Terraform tests/mock providers for enablement and resource wiring. Review real plans for AWS-only, GCP-only, mixed cloud, and fully disabled configurations.
10. **Deployment verification:** confirm no VM replacement, SSH metadata loss, IAM permission removal, unexpected cross-cloud resources, or duplicate notifications. In an authorized test environment verify metric dimensions, structured logs, one controlled 500 versus a nonmatching 200, synthetic failure/recovery, email delivery, reboot persistence, and log rotation.
11. **Handoff:** expose identifiers and links, document required email confirmation, record costs/retention, and provide troubleshooting/rollback notes. Do not claim live validation from `terraform validate` alone.

Definition of done: all ten original monitoring requirements have cloud-specific automated ownership; budgets remain independent; cloud selection respects VM overrides; every configured signal has observed telemetry and a tested alert path; no unexpected VM lifecycle changes occur.

## References to verify during implementation

The code above is an implementation blueprint with representative resource fragments. Variables, local feature gates, IAM details, packaging, and tests must be completed and validated together; this document itself has not been Terraform-planned or applied.

- [AWS provider resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS canary resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/synthetics_canary)
- [CloudWatch Agent configuration](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html)
- [Traefik access logs](https://doc.traefik.io/traefik/observability/access-logs/)
- [GCP Ops Agent configuration](https://docs.cloud.google.com/logging/docs/agent/ops-agent/configuration)
- [GCP alert policy resource](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_alert_policy)
- [GCP uptime resource](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/monitoring_uptime_check_config)
- [GCP budget resource](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/billing_budget)
- [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/)
- [AWS Budgets pricing](https://aws.amazon.com/aws-cost-management/aws-budgets/pricing/)
