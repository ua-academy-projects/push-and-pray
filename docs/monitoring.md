# Cloud monitoring

For Compose deployments, Terraform creates the monitoring definitions that
belong to the active cloud. Ansible installs the guest agents and configures
workload log collection and Traefik access logging. Budgets remain manual.

Host monitoring covers the bastion and every workload VM. Docker and
application log collection remains limited to workload VMs, and the external
HTTPS check targets only the public UI.

K3s mode deliberately does not instantiate the VM-focused observability modules,
so Kubernetes nodes do not receive the Compose VM alert policies or guest-agent
IAM grants. Managed GKE instead uses the metrics exported by GKE's managed
monitoring integration. Managed EKS installs the Amazon CloudWatch Observability
add-on and uses Container Insights. Managed AKS enables Azure Monitor Container
Insights. All three platforms receive native cloud
dashboards, alerts, and a public HTTPS availability check without installing
Prometheus or Grafana.

## Manual notification destinations

Notification handling differs by provider:

- For managed EKS, set `monitoring.aws.notification_email` to let Terraform
  create SNS topics and email subscriptions. Confirm the AWS email request for
  both the workload region and `us-east-1`; Route 53 health-check metrics and
  their alarm live in `us-east-1`. Alternatively, provide existing regional
  topic ARNs in `notification_topic_arns`. An existing ARN takes precedence
  over the email setting for that region.
- For AWS Compose, create a standard SNS topic in each alarm region, subscribe
  the operator email, and provide the topic ARNs in
  `notification_topic_arns`.
- In GCP, create one email notification channel in the monitored project and
  copy its full resource name, such as
  `projects/example-project/notificationChannels/1234567890`.

Azure differs from AWS and GCP: Terraform creates its Action Group and email
receiver from the non-secret address in project configuration. Azure can also
create alerts without notification actions when that address is null.

For managed EKS, the automatic email configuration looks like this:

```json
"monitoring": {
  "aws": {
    "log_retention_days": 30,
    "notification_email": "operator@example.com",
    "notification_topic_arns": {}
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

For managed EKS, an empty AWS map together with a null AWS email creates alerts
without notification actions. For AWS Compose, an empty map does so regardless
of the email field. A null GCP channel or null Azure email likewise creates its
provider's monitoring resources without notification actions.

Terraform builds the AWS fleet alarms from the IDs of the currently managed
instances, so terminated instances are not retained in their metric queries.

## Managed resources

For each active AWS region, Terraform creates the `/oilscope/system` and
`/oilscope/docker` log groups, request and HTTP 5xx metric filters, and
fleet-wide CPU, memory, root-disk, status-check, and HTTP 5xx alarms. It also
creates a Route 53 HTTPS check for `/health`, its alarm in `us-east-1`, and the
`Oilscope` dashboard.

For a GCP Compose deployment, Terraform creates request and HTTP 5xx logs-based
metrics, fleet-wide CPU, memory, root-disk, VM metric-absence, and HTTP 5xx
policies. It also creates an HTTPS uptime check for `/health`, an availability
policy, and the `Oilscope` dashboard.

For a managed GKE deployment, Terraform creates the `OilScope GKE` native Cloud
Monitoring dashboard, five GKE metric alert policies, a public HTTPS uptime
check, and its availability policy. Every Kubernetes query is scoped to the
Terraform-managed cluster name and region; workload restart and PVC alerts are
additionally scoped to the application namespace. Alerts notify the existing
GCP channel configured in `monitoring.gcp.notification_channel_id`. The
dashboard and alert lifecycle follows the GKE deployment, while the underlying
metrics continue to be collected by GKE's managed monitoring integration.
Missing node, pod, and container time series are treated as recovered because
GKE routinely replaces those resources; this prevents incidents from remaining
open for deleted resources. Container restarts are summed by namespace and
stable container name rather than ephemeral pod name. The restart policy uses
PromQL `increase` over a ten-minute window so a restart burst resolves when it
leaves that window, and it has a 30-minute no-data auto-close fallback.

For a managed EKS deployment, Terraform installs the Amazon CloudWatch
Observability add-on using EKS Pod Identity and creates the `OilScope-EKS`
CloudWatch dashboard. It shows node CPU, memory, and filesystem utilization;
pod count by namespace; OilScope pod CPU, memory, restarts, and network traffic;
HTTPS availability; and current alarm state. Alerts cover failed nodes,
sustained node CPU and memory pressure, sustained OilScope pod CPU and memory
pressure, and public HTTPS availability. The regional alarms notify the SNS
topic in the EKS region, while the Route 53 alarm notifies the topic in
`us-east-1`. Terraform pre-creates the Container Insights log groups with the
configured retention period. Container Insights, CloudWatch Logs, Route 53
health checks, and SNS may incur AWS charges.

For a managed AKS deployment, Terraform enables the Azure Monitor Container
Insights agent, creates and associates its Container Insights data collection
rule, and creates the `OilScope AKS` workbook. The data collection rule sends
the full Container Insights stream group to Log Analytics every minute. The
workbook shows per-node CPU, memory, and root-filesystem utilization; pod count
and state; OilScope container CPU, memory, and restarts; warning events; and
public HTTPS availability. Alerts cover per-node CPU, memory, and root-disk
pressure; nodes that are not ready; unhealthy OilScope pods; container restart
bursts; and public HTTPS availability. Root-disk monitoring is restricted to
`/dev/root`, preventing small system partitions from distorting its chart or
alert. The alerts use the shared Azure Action Group configured by
`monitoring.azure.notification_email` and automatically resolve when their
conditions clear. Log Analytics ingestion, Application Insights availability
tests, and Azure Monitor alerts may incur Azure charges.

For an Azure Compose deployment, Terraform creates a capped Log Analytics
workspace, an Application Insights component, a Linux data collection rule and
its VM associations, an optional email Action Group, CPU, memory, root-disk,
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

For Compose deployments:

1. Apply Terraform to create the infrastructure, monitoring definitions, and
   optional Cloudflare DNS record.
2. Run `oilscope.platform.deploy`. The general Ansible playbook prepares the
   hosts, installs the applicable provider guest agent or VM extension, and
   deploys the application workloads.

Agent-backed alarms can initially show no data. The HTTPS alarm can initially
open while DNS, Traefik, and the application are not ready; it closes after the
endpoint becomes healthy.

For managed Kubernetes deployments, apply Terraform first. GKE begins exporting
the required metrics through its managed integration. EKS then starts the
CloudWatch agent and Fluent Bit pods in the `amazon-cloudwatch` namespace; allow
several minutes after the add-on becomes ready for Container Insights series to
populate the dashboard. AKS starts its Container Insights agent after the
Terraform update; allow approximately ten minutes for its Log Analytics series
to populate the workbook. Confirm all pending SNS email subscriptions before
expecting AWS alarm or recovery messages. Azure Action Group email receivers do
not require the SNS confirmation workflow. The workload deployment remains the
same Ansible workflow and no separate monitoring playbook is required.

## Cloudflare DNS

Add the non-secret Cloudflare Zone ID to `project-config.json` to manage the
public application record with Terraform:

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
mode. Compose deployments point it to the active cloud's UI public IP; a GCP
K3s deployment points it to the reserved external ingress load-balancer IP and
uses `k3s.application.hostname` as the record name.

The first apply requires an existing record to be imported or deleted. Import
uses the identifier `<zone_id>/<dns_record_id>` at the address
`module.cloudflare_dns[0].cloudflare_dns_record.ui`.

## Existing manual resources

Before the first monitoring-enabled apply, delete or import manually created
alarms and metric filters that use the same names. Existing AWS log groups must
also be deleted or imported because Terraform now owns them. Delete or import
existing dashboards named `Oilscope`, `OilScope-EKS`, or `OilScope AKS`. Keep
manually created budgets and GCP notification channels. Existing SNS topics
referenced through `notification_topic_arns` remain external; SNS topics
created from `notification_email` are Terraform-managed. Terraform also
manages the Azure Action Group.

Terraform destroys its monitoring resources together with the application.
Manual budgets, external SNS topics, and GCP notification channels remain.
