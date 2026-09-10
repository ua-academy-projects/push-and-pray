# Native multi-cloud monitoring

OilScope uses the native monitoring and logging services in each provider.
Terraform owns the alerting, notification, dashboard, budget, log-group, and
agent-permission resources; the `oilscope.platform.host_baseline` Ansible role
installs and configures the agent inside each VM.

## Configuration

`project-config.json` requires a small shared monitoring section:

```json
"monitoring": {
  "alert_email": "operator@example.com",
  "monthly_budget": {
    "amount": 25,
    "currency": "USD",
    "gcp_billing_account_id": "000000-000000-000000"
  }
}
```

`monthly_budget` is optional. When present, AWS creates an account-level monthly
cost budget. GCP creates a project-filtered monthly budget only when
`gcp_billing_account_id` is also present; omitting that provider-specific value
keeps GCP budget creation disabled without affecting VM monitoring.

CPU alerts use an 80 percent threshold. Filesystem alerts use 85 percent. These
initial thresholds intentionally live in provider module logic rather than
expanding deployment configuration with tuning fields.

## AWS

Each AWS VM has alarms for EC2 status-check failure or missing health data,
CPU utilization, and the CloudWatch Agent's root-filesystem utilization metric.
One SNS topic and email subscription is created in every AWS region containing
OilScope VMs. A compact CloudWatch dashboard charts those three categories.

AWS sends a confirmation message for each regional SNS email subscription.
The recipient must confirm every subscription before VM alarm notifications can
be delivered. AWS Budgets can also send a verification request for its direct
email subscriber; complete it if requested by AWS.

Terraform creates `/<name_prefix>-<environment>-<vm>/system` log groups. The
agent sends `/var/log/syslog` to an `{instance_id}/system` stream and
`/var/log/auth.log` to an `{instance_id}/authentication` stream. The VM role
retains `cloudwatch:PutMetricData` in the `CWAgent` namespace and receives only
`logs:CreateLogStream`, `logs:DescribeLogStreams`, and `logs:PutLogEvents` for
the project VM log groups. Terraform creates the groups, so the agent does not
receive `logs:CreateLogGroup`.

## GCP

Each GCP VM has alert policies for missing instance uptime, CPU utilization,
and maximum used-filesystem percentage. The policies notify a Cloud Monitoring
email channel, and a compact Cloud Monitoring dashboard charts the same three
categories.

The existing per-VM service account receives `roles/monitoring.metricWriter`
and `roles/logging.logWriter`. The Ansible baseline installs the Google Cloud
Ops Agent and keeps its host-metrics pipeline enabled. Its logging pipeline
collects the standard `/var/log/messages` or `/var/log/syslog` system log and
the `/var/log/auth.log` or `/var/log/secure` authentication log. Agent self-log
file collection remains disabled.

GCP budget creation requires the Billing Budgets API, a billing account ID, and
Terraform credentials allowed to manage budgets on that billing account. User
Application Default Credentials also need `serviceusage.services.use` on the
configured GCP project, which Terraform uses as the quota/billing project.

## Deferred scope

Application logs, HTTP 500 log-based alerts, and synthetic availability tests
remain intentionally deferred.
