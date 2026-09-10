# AWS monitoring module

This module manages the AWS monitoring resources for the VM map supplied by the root module. It does not create or replace EC2 instances, install software on them, alter Traefik, or create budgets. The associated AWS VM module adds scoped agent publishing permissions to existing instance roles. Nothing is automatically applied by editing these files.

## How the modules connect

The root passes `config = local.config` and `vms = module.aws_vm.vms`.

- `config` supplies project/environment names, AWS region, VM roles, and monitoring settings.
- `vms` supplies real instance IDs keyed by stable configuration names. It contains only the AWS instances, so mixed-cloud configurations monitor the correct hosts.
- IDs are values, not resource keys. Terraform can plan monitoring resources before EC2 IDs are known.
- With no AWS VMs, this module creates no monitoring resources, including no canary.
- EC2 names and tags do not automatically propagate. Naming and tags follow the existing project conventions through module locals.

The root output `aws_monitoring` exposes resource identifiers and per-VM agent JSON. Budget modules remain independent future work: spending notifications must not depend on whether these VMs exist.

## Files and their responsibilities

| File | Responsibility |
| --- | --- |
| `variables.tf` | Typed inputs, optional defaults, validation |
| `locals.tf` | Naming, feature gates, VM signal definitions, UI selection |
| `logs.tf` | Traefik log group, retention, exact-500 and all-5xx metric filters |
| `notifications.tf` | SNS topic and one subscription per unique email |
| `alarms.tf` | Host, HTTP, and synthetic alarms with recovery actions |
| `dashboard.tf` | CPU/status/network, optional guest/log/synthetic charts and alarm status |
| `agent.tf` | Deployment-ready CloudWatch Agent JSON for each relevant VM |
| `synthetics.tf` | Canary ZIP, execution identity, private artifact storage, lifecycle |
| `canary/health.js` | Public HTTPS and dependency-response validation |
| `outputs.tf` | Resource identifiers and agent configuration contract |
| `versions.tf` | AWS and archive provider requirements |
| `tests/` | Offline plan tests with mocked providers |
| `../vm/monitoring.tf` | Additive permissions on existing EC2 IAM roles |

## Configuration and defaults

Add settings under the existing top-level `monitoring` object. No second copy of instance IDs or VM tags is needed. The checked-in example contains every supported field; the external Desktop JSON was not modified during this implementation.

```json
"monitoring": {
  "enabled": true,
  "email_recipients": ["YOUR_EMAIL"],
  "logs_enabled": true,
  "alarms_enabled": false,
  "dashboard_enabled": false,
  "agent_metrics_enabled": false,
  "log_retention_days": 7,
  "cpu_threshold_percent": 80,
  "memory_threshold_percent": 85,
  "disk_threshold_percent": 85,
  "http_error_threshold": 1,
  "disk_fstype": "ext4",
  "synthetics": {
    "enabled": false,
    "hostname": "oilscope.example.com",
    "path": "/health",
    "period_minutes": 5,
    "runtime_version": "syn-nodejs-puppeteer-17.0"
  }
}
```

Replace the illustrative email and hostname before enabling features. Optional defaults preserve the log-group behavior already implemented: absent monitoring settings still create the log group when AWS VMs exist. Set `enabled=false` to disable the module. This differs from the original plan's fully disabled default because a log group was already part of the working module.

| Setting | Default | Meaning |
| --- | --- | --- |
| `enabled` | true | Master gate, combined with nonempty AWS VM map |
| `logs_enabled` | true | Log group and HTTP metric filters; UI log configuration |
| `email_recipients` | empty | No topic/subscriptions unless addresses are supplied |
| `alarms_enabled` | false | Host and enabled-feature alarms; requires recipients |
| `dashboard_enabled` | false | One operational dashboard |
| `agent_metrics_enabled` | false | Memory/disk configurations, publisher IAM, and guest charts/alarms |
| `synthetics.enabled` | false | A paid scheduled public health check |

Memory/disk alarms also require `alarms_enabled`; setting the agent flag does not install or start an agent. Synthetic checks can run without alarms, but no email outage notification is sent until alarms are enabled. Dashboard and log resources can operate without email recipients.

The schema accepts these fields and rejects unknown monitoring keys. Terraform also validates retention, thresholds, recipients and enabled synthetic endpoint settings. The module uses typed optional attributes, so defaults apply even when Terraform is run without a separate JSON-schema validator.

## Logs and error metrics

The group name stays `/<name_prefix>/<environment>/traefik`, preserving the existing Terraform address `aws_cloudwatch_log_group.traefik[0]`. Retention defaults to seven days.

Two metric filters count new JSON access-log events:

- `HTTP500Count`: `DownstreamStatus = 500`.
- `HTTP5xxCount`: `DownstreamStatus >= 500` and `< 600`.

Their namespace includes project/environment to prevent cross-environment mixing. Each matching event contributes one; no per-request dimensions are added. An exact 500 contributes to both metrics, so enabling both alarms can produce two related emails. HTTP alerts cover responses through Traefik only.

Your deployed Traefik must already emit numeric `DownstreamStatus` JSON into `/var/log/oilscope/traefik-access.log`. The module does not alter the proxy Compose template. Source-file rotation must also be configured in deployment; cloud retention does not bound local disk usage.

## Notifications

A single standard SNS topic receives alarm and recovery actions. Subscriptions use email addresses as stable keys and deduplicate repeated addresses. Empty recipient lists create no topic; enabled alarms reject an empty list.

AWS sends a confirmation email after subscription creation. Until each recipient confirms, its subscription cannot deliver notifications. Terraform cannot confirm on the user's behalf. No test emails were sent during implementation.

## Host and HTTP alarm behavior

| Signal | Condition | Evaluation | Missing data |
| --- | --- | --- | --- |
| CPU | average >= configured percentage | 2 of 2 five-minute periods | missing |
| EC2 status | maximum StatusCheckFailed >= 1 | 2 of 2 one-minute periods | breaching |
| Memory | average >= configured percentage | 2 of 2 five-minute periods | missing |
| Root disk | maximum >= configured percentage | 2 of 2 five-minute periods | missing |
| Agent missing | memory minimum < 0, normally impossible | 2 of 2 five-minute periods | breaching |
| HTTP 500 / 5xx | sum >= configured count | one five-minute period | not breaching |
| Synthetic success | average SuccessPercent < 100 | two scheduled periods | breaching |

Status and agent-absence alarms assume always-on VMs; an intentional shutdown can alarm. Missing error events are not treated as an outage because healthy sites can have no errors. The synthetic check supplies positive evidence of application availability.

CPU uses existing EC2 metrics at five-minute periods. Detailed EC2 monitoring is not enabled or required. There are no extra agent CPU series. EC2 status checks detect infrastructure issues; they do not establish that Docker or the application is working.

## Agent configuration and permissions

The module exports valid JSON but never opens SSH connections or uses Terraform provisioners. Install/reconfigure CloudWatch Agent through deployment after applying IAM/log destinations.

- With logs only, only UI VMs receive a logs-only JSON configuration.
- With `agent_metrics_enabled`, all supplied AWS VMs receive memory and root-disk settings at 60 seconds.
- Traefik log collection is added only to UI configurations when logs are enabled.
- `InstanceId` is resolved by the agent from instance metadata. Terraform escaping preserves the literal `${aws:InstanceId}` in the generated JSON.

The AWS VM module adds an inline policy to the existing EC2 role. It permits `PutMetricData` only for `CWAgent`, plus stream creation/description and event publishing only in the project's Traefik group on UI roles. Terraform creates the group; agents do not receive log-group creation or retention-changing permission. Existing role policies and SSH/user data are preserved.

The disk metric dimensions are exactly `InstanceId`, `path=/`, and `fstype=<disk_fstype>`, with the device dimension suppressed. The default is Ubuntu's usual `ext4`, but verify the actual filesystem. This module currently assumes the same root filesystem type across its AWS VMs; heterogeneous filesystem types need an interface extension. Do not enable guest alarms against mismatched or absent metrics.

Configuration replacement must be deliberate: an agent may already collect other telemetry. Merge the exported JSON with that configuration if needed. The module doesn't remove manually attached managed policies; review redundant permissions separately.

## Dashboard

Charts reuse the alarm signal definitions and dimensions, preventing CPU/disk charts from silently pointing at different series than their alarms. Network byte charts are added for each instance. HTTP and synthetic charts appear only when their source feature is enabled. The alarm-status widget appears only with alarms enabled.

The dashboard does not include budget totals or CPU-credit charts. Budget scope is separate; CPU-credit monitoring can be added for relevant burstable types once instance-type metadata is part of the interface. It is not needed for the baseline CPU/memory/availability requirements.

## Synthetic check

The optional canary tests public HTTPS every five minutes by default. It requires HTTP 200 and JSON values `status=ok`, `history=connected`, and `sessions=postgresql`. It fails on non-200/redirect responses, invalid JSON, failed dependencies, network/TLS errors, response bodies over 64 KiB, or timeout. A response body is never deliberately logged or attached as an artifact.

It uses the current Puppeteer runtime's `@aws/synthetics-puppeteer` step API without launching a browser. The default runtime is pinned, not automatically advanced; verify availability in your AWS region before applying. This is an API health test, not a browser journey or a private service probe.

The archive provider packages only `health.js` at ZIP root. The output filename includes the source hash so source changes change the canary input. The execution role can publish only the Synthetics namespace, write under its artifact prefix, and manage its own generated log-group prefix.

Artifact storage is private, encrypted with S3-managed keys, and expires results after seven days. Run history is also retained seven days. The runner applies the configured retention to its own Lambda log group because AWS chooses that group's suffix; this avoids a race between Terraform creation and the first run. A runner that never reaches its handler cannot set retention, so inspect generated groups after failed initialization.

`delete_lambda=true` requests deletion of the canary's supporting Lambda resources. Its artifact bucket deliberately does not force-delete contents. Empty/retain the bucket before destroying it; inspect remaining generated logs as part of teardown.

## Deployment and import sequence

1. Review settings and costs; this implementation has not applied anything to AWS.
2. Run `terraform init` for the archive provider and module references.
3. Import the previously created Traefik group before applying, if it already exists:

   ```sh
   terraform -chdir=infrastructure/terraform import \
     'module.aws_monitoring.aws_cloudwatch_log_group.traefik[0]' \
     '/oilscope/dev/traefik'
   ```

   Use the actual project/environment name. Inventory existing SNS topics/alarms before creating duplicates.
4. Plan with your actual project configuration. Inspect IAM changes and resource creation/deletion. Changing a feature from enabled to disabled can destroy its resources; preserve/import logs deliberately.
5. Apply the reviewed infrastructure plan, confirm SNS subscriptions, and install the exported agent configurations on the intended VMs. Verify the existing proxy log source and IAM propagation.
6. Confirm fresh metrics with the exact dimensions, then enable guest alarms. Test a controlled error and recovery in an authorized test environment.
7. Enable synthetics only after checking runtime availability, public endpoint readiness, and recurring charges.

The external Desktop JSON is left as you last edited it. New flags are documented in `project-config.example.json`; no paid feature was silently enabled there.

## Validation

From repository root:

```sh
terraform -chdir=infrastructure/terraform init -backend=false \
  -test-directory=modules/aws/monitoring/tests
terraform -chdir=infrastructure/terraform validate
terraform -chdir=infrastructure/terraform test \
  -test-directory=modules/aws/monitoring/tests
node --test infrastructure/terraform/modules/aws/monitoring/canary/health.test.js
```

Terraform tests mock AWS/archive providers and do not create cloud resources. They cover defaults, master disable, no AWS VMs, full guest metrics, log disablement, recipient deduplication, invalid settings and synthetic enablement. Node tests cover the response validator using simulated HTTPS responses.

Passing these tests establishes local configuration and behavior checks, not live IAM propagation, runtime execution, email confirmation, agent installation, or successful notification delivery. A cloud plan/apply and live smoke test remain deployment work.

## Cost and scope

Logs, custom metrics, alarms, dashboards, SNS usage and canaries can be charged beyond account allowances. A five-minute canary runs 8,640 times in a 30-day month, with supporting Lambda/S3/log/metric usage. Guest metrics create separate series per VM; use current regional pricing.

This completes the AWS monitoring module. GCP monitoring, independent $50/$100 budget notifications, automated agent installation and automated Traefik deployment changes remain separate tasks rather than being hidden inside this module.

References: [AWS provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs), [canary resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/synthetics_canary), [runtime support](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Synthetics_Library_nodejs_puppeteer.html), [agent configuration](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html), [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/).
