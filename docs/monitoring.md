# Cloud monitoring

Terraform creates the monitoring definitions that belong to the active
application deployment. Ansible installs the guest agents and configures
workload log collection and Traefik access logging. Budgets remain manual.

Host monitoring covers the bastion and every workload VM. Docker and
application log collection remains limited to workload VMs, and the external
HTTPS check targets only the public UI.

## Manual notification destinations

Create and confirm the notification destination before applying Terraform:

- In AWS, create a standard SNS topic in every region that contains alarms and
  subscribe the AWS monitoring email address. VM and log alarms use the VM
  region. The Route 53 HTTPS health-check alarm uses `us-east-1`, where Route 53
  publishes its CloudWatch metrics.
- In GCP, create one email notification channel in the monitored project and
  copy its full resource name, such as
  `projects/example-project/notificationChannels/1234567890`.

Azure differs from AWS and GCP: Terraform creates its Action Group and email
receiver from the non-secret address in project configuration. Azure can also
create alerts without notification actions when that address is null.

Reference these existing destinations in `project-config.json`:

```json
"monitoring": {
  "aws": {
    "log_retention_days": 30,
    "notification_topic_arns": {
      "eu-north-1": "arn:aws:sns:eu-north-1:123456789012:oilscope-alerts",
      "us-east-1": "arn:aws:sns:us-east-1:123456789012:oilscope-availability-alerts"
    }
  },
  "gcp": {
    "notification_channel_id": "projects/example-project/notificationChannels/1234567890"
  },
  "azure": {
    "log_retention_days": 30,
    "daily_ingestion_limit_gb": 0.1,
    "notification_email": "operator@example.com"
  }
}
```

An empty AWS map, a null GCP channel, or a null Azure email creates the
monitoring resources without notification actions.

Terraform builds the AWS fleet alarms from the IDs of the currently managed
instances, so terminated instances are not retained in their metric queries.

## Managed resources

For each active AWS region, Terraform creates the `/oilscope/system` and
`/oilscope/docker` log groups, request and HTTP 5xx metric filters, and
fleet-wide CPU, memory, root-disk, status-check, and HTTP 5xx alarms. It also
creates a Route 53 HTTPS check for `/health`, its alarm in `us-east-1`, and the
`Oilscope` dashboard.

For a GCP deployment, Terraform creates request and HTTP 5xx logs-based metrics,
fleet-wide CPU, memory, root-disk, VM metric-absence, and HTTP 5xx policies. It
also creates an HTTPS uptime check for `/health`, an availability policy, and
the `Oilscope` dashboard.

For an Azure deployment, Terraform creates a capped Log Analytics workspace,
an Application Insights component, a Linux data collection rule and its VM
associations, an optional email Action Group, CPU, memory, root-disk,
availability, heartbeat, and HTTP 5xx alerts, a Standard HTTPS availability
test for `/health`, and the `OilScope` workbook. The Azure Monitor Agent sends
host performance, heartbeat, and selected system logs from every VM. On
workload VMs, Azure-only Compose logging sends container output directly to
the host's `local0` syslog facility so request and HTTP 5xx queries remain
separate from bastion logs.

The `http-requests` metrics count Traefik access records. They are intended for
an hourly `SUM` chart. They measure HTTP requests, not unique people or browser
sessions. The dedicated `/health` router disables access logging so automated
uptime probes do not inflate the request metric.

## Deployment order

1. Apply Terraform to create the infrastructure, monitoring definitions, and
   optional Cloudflare DNS record.
2. Run `oilscope.platform.deploy`. The general Ansible playbook prepares the
   hosts, installs the applicable provider guest agent or VM extension, and
   deploys the application workloads.

Agent-backed alarms can initially show no data. The HTTPS alarm can initially
open while DNS, Traefik, and the application are not ready; it closes after the
endpoint becomes healthy.

## Cloudflare DNS

Add the non-secret Cloudflare Zone ID to `project-config.json` to manage the UI
record with Terraform:

```json
"dns": {
  "cloudflare": {
    "zone_id": "0123456789abcdef0123456789abcdef"
  }
}
```

Before running Terraform, export a Cloudflare API token restricted to `DNS
Edit` on this zone as `CLOUDFLARE_API_TOKEN`. The token is not part of the
configuration or Terraform state. Terraform keeps the A record in DNS-only
mode and updates it from the active cloud's UI public IP.

The first apply requires an existing record to be imported or deleted. Import
uses the identifier `<zone_id>/<dns_record_id>` at the address
`module.cloudflare_dns[0].cloudflare_dns_record.ui`.

## Existing manual resources

Before the first monitoring-enabled apply, delete or import manually created
alarms and metric filters that use the same names. Existing AWS log groups must
also be deleted or imported because Terraform now owns them. Delete or import
an existing dashboard named `Oilscope`. Keep manually created budgets, SNS
topics, SNS subscriptions, and GCP notification channels. Terraform manages
the Azure Action Group.

Terraform destroys its monitoring resources together with the application.
The manual budgets and AWS/GCP notification destinations remain.
