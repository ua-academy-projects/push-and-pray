# Azure configuration

Azure is selected through the existing `project-config.json`, using
`default_cloud: "azure"` or a VM's `cloud: "azure"`. Copy the Azure entries for
locations, instance types, disks, images, and database sizes from
`project-config.example.json` into your shared config. Existing AWS/GCP configs
do not need Azure mapping entries. Retain the existing AWS/GCP configuration
fields: the root still configures those providers and uses its GCS backend.

For a complete single-location Azure topology, replace the corresponding fields
in the shared example with this fragment (retain its other fields):

```json
{
  "default_cloud": "azure",
  "default_location": "europe",
  "database_mode": "postgres_extensions",
  "cloudflare": { "enabled": false },
  "vms": {
    "bastion": { "allowed_cidrs": ["192.0.2.10/32"] },
    "infra": { "role": "database", "size": "micro", "location": "europe", "internal_ip": "10.0.1.4" },
    "history": { "role": "history", "size": "small", "location": "europe", "internal_ip": "10.0.1.5" },
    "fetcher": { "role": "fetcher", "size": "micro", "location": "europe", "internal_ip": "10.0.1.6" },
    "ui": { "role": "ui", "cloud": "azure", "size": "micro", "location": "europe", "internal_ip": "10.0.0.5", "assign_public_ip": true }
  }
}
```

Replace the example SSH source CIDR with your own public address. The automatic
Linux bastion uses the management subnet's fourth address and the configured
`ssh_users` username/key. Extra bastions use the existing VM model with
`role: "bastion"`. For each Azure location with workloads, configure a matching
bastion. The bootstrap toggle and `OILSCOPE_BASTION_CONNECT_PORT=22` work as
before when Ansible first changes a bastion's SSH port.

## Resources and connectivity

Each selected logical location gets a Resource Group, VNet, management and
workload subnets using the shared CIDRs, and an explicit NAT gateway for outbound
traffic. As with AWS, bastions and public UI VMs use the management subnet;
other VMs use the workload subnet. Set static IPs within the corresponding
subnet, excluding Azure's first four and last reserved addresses.

NIC NSGs allow only the configured bastion SSH sources, bastion-to-workload SSH,
UI-to-history HTTP (8001), application-to-self-managed PostgreSQL (5432),
fetcher-to-history RabbitMQ (5672) in managed mode, and the existing public UI
ports. They override Azure's default unrestricted VNet ingress. Public IPs are
limited to bastion/UI roles. There is no new cross-cloud or cross-location
peering; private services and clients need a reachable common network just as
with the existing provider modules.

Azure VM sizes, Ubuntu marketplace images, and disk SKUs resolve inside the VM
module. OS disks are at least the mapped image's `min_disk_size_gb` (30 GiB for
the example Ubuntu images), since Azure cannot shrink an image to the common
10 GiB default. Additional disks use `disks` and are attached without formatting
or mounting, like the existing modules. Bootstrap commands run on first boot.
Azure monitoring and logging are provisioned as described below.

## Monitoring and logging

The root `azure_monitoring` module consumes shared config and only the VMs
returned by `azure_vm`. All created Azure Linux VMs receive monitoring: bastion,
database/infra, history, fetcher, and UI, as selected. An empty Azure VM map
creates no monitoring resources or data lookups and requires no Azure location
mappings. Existing provider authentication requirements remain unchanged.

Each logical location containing Azure VMs gets an Azure Monitor Workspace
(`-amw`) for OpenTelemetry metrics and a Log Analytics Workspace (`-law`,
PerGB2018, 30-day retention) for logs. Names use
`<name_prefix>-<environment>-<purpose>`, with the existing location suffix
convention, and resources receive common labels plus environment tags.

The supported `Microsoft.Azure.Monitor/AzureMonitorLinuxAgent` extension uses
a system-assigned identity enabled on each VM. Minor-version and automatic
upgrades are enabled; the minimum extension version is 1.38, which introduced
Linux OpenTelemetry support. The existing VM UUID output remains unchanged;
the added `resource_id` supplies the ARM ID needed for extensions and associations.
VM ingestion requires no additional role assignments. Metrics and Syslog use
separate Linux DCRs, with one association of each kind on every Azure VM:

- Metrics DCR: `system.cpu.time`, `system.filesystem.usage`, and `system.uptime`,
  sampled every 60 seconds through `Microsoft-OtelPerfMetrics` into the Azure
  Monitor Workspace. CPU and VM availability alerts use independent platform
  metrics; availability does not depend on AMA or an uptime-derived signal.
- Syslog DCR: facilities `auth`, `authpriv`, `cron`, `daemon`, `kern`, `syslog`,
  and `user`; severities `Warning`, `Error`, `Critical`, `Alert`, and `Emergency`.
  Messages go through `Microsoft-Syslog` into the Log Analytics `Syslog` table.
  The image must have a supported running Syslog daemon (rsyslog or syslog-ng).
  This collects system/service Syslog, not Docker stdout or application files.

All alerts use one `<name_prefix>-<environment>-alerts` Action Group, emailing
`monitoring.alert_email` with the common alert schema on firing/resolution.
Thresholds remain fixed, matching the existing provider-module configuration
pattern; no new shared config fields or environment variables are introduced.

| Alert | Signal and condition | Timing | Severity |
| --- | --- | --- | --- |
| CPU | `Percentage CPU` average > 80% per VM | 5-minute window; evaluated every minute | 2 |
| Availability | `VmAvailabilityMetric` average < 1 per VM | 5-minute window; evaluated every minute | 1 |
| Filesystem | PromQL: used bytes / total bytes > 85% for `/` | Condition holds for 5 minutes; evaluated every minute | 2 |

The filesystem rule is workspace-scoped, one per logical location, retaining
VM resource ID/device/mount/type labels so machines are evaluated independently.
It includes only root mounts of type `ext4`, `xfs`, or `btrfs`, excluding pseudo
filesystems and container/temporary mounts. A dedicated
`<name_prefix>-<environment>-id-monitoring-alerts` user-assigned identity has
only **Monitoring Reader** on these Azure Monitor Workspaces. It is attached to
the PromQL alerts, not the VMs. No subscription-wide monitoring roles are added.

Availability measures the Azure host's availability signal, not application
health. Azure can stop emitting this metric when a VM is stopped/deallocated
through the control plane; missing data is not converted to zero. This threshold
rule therefore does not replace a missing-data or application-health alert.

AzureRM remains at the existing `~> 4.62` constraint (lockfile: 4.81.0).
AzAPI `~> 2.0` is needed specifically for the metrics DCR's
`performanceCountersOTel` / `Microsoft-OtelPerfMetrics` properties
(`Microsoft.Insights/dataCollectionRules@2024-03-11`) and the filesystem alert's
`PromQLCriteria` (`Microsoft.Insights/metricAlerts@2024-03-01-preview`). Their
embedded AzAPI schema checks are disabled because older 2.x schemas omit these
properties. Azure still checks the requests during deployment. All other
resources use AzureRM. The query-based alert feature is preview; confirm its
availability in your selected regions before deploying. No dashboard, workbook,
Grafana, legacy agent, per-process metrics, or optional analytics solution is added.

The Terraform principal needs create/update/delete access to the monitoring
resources, VM identities/extensions, DCR associations, and the alert identity;
it also needs `Microsoft.ManagedIdentity/userAssignedIdentities/assign/action`
on that identity and `Microsoft.Authorization/roleAssignments/write` (and delete
for cleanup) at the workspace scopes. Contributor alone cannot create those
role assignments. An administrator can delegate the ability to assign Monitoring
Reader at the workspace scopes. Ensure `Microsoft.Insights`, `Microsoft.Monitor`,
`Microsoft.OperationalInsights`, and `Microsoft.ManagedIdentity` are registered
in the subscription. AzAPI skips automatic resource-provider registration.
It uses the same external Azure CLI or `ARM_*` authentication as AzureRM.

AMA uses the existing outbound NAT and HTTPS access to Azure Monitor and its
configuration/ingestion endpoints; no inbound ports or topology changes are
needed. No private-link monitoring endpoints are introduced.

After your manual init (which adds AzAPI to the lockfile), formatting, validation,
and plan, review Azure single/multiple-location configs and AWS/GCP-only configs.
After applying yourself, confirm AMA is healthy, both DCR associations exist on
every Azure VM, the workspace receives the three guest metrics, the filesystem
query returns a separate root series per VM, and Syslog messages arrive. Check
alert identity access, rule evaluation, and Action Group email delivery. Allow
for initial metric ingestion and role-assignment propagation. No verification
commands were run when implementing this module; refresh the graph with
`graphify update .` when you perform your checks.

References: [VM monitoring and OTel DCR](https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vm-enable-monitoring),
[system-metric PromQL](https://learn.microsoft.com/en-us/azure/azure-monitor/metrics/prometheus-system-metrics-best-practices),
[query-based alerts and identity](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-create-query-based-metric-alerts),
and [VM availability semantics](https://learn.microsoft.com/en-us/azure/virtual-machines/monitor-vm-reference).

## Managed PostgreSQL and secrets

`database_mode: "managed"` with `default_cloud: "azure"` selects PostgreSQL
Flexible Server in `default_location`. All workload VMs must use that cloud and
location. `postgres_extensions` retains the PostgreSQL container on the database
VM. Redis and RabbitMQ stay on UI and history respectively in managed mode.

Flexible Server uses the first `network.database_subnet_cidrs` entry as its
delegated subnet and a private DNS zone linked to the VNet. Public access is
disabled. Only database/history VM addresses and PostgreSQL's own subnet can
reach port 5432. The database VM remains the migration host. Storage rounds up
to the next Azure-supported tier, with a 32 GiB minimum; the common database
size, version, username, name, and port retain their meanings. The module exports
the private FQDN through `managed_database`, which inventory already loads.

Provide `TF_VAR_azure_database_admin_password` for managed mode. It is an
ephemeral Terraform input consumed by the provider's write-only password field,
so it is not persisted in state or outputs. Supply the same value as
`DB_PASSWORD_ADMIN` to the existing Ansible secret upload workflow. On rotation,
increment `TF_VAR_azure_database_admin_password_version`, update Terraform's
password, and upload that same password before running database provisioning.

Set `clouds.azure.key_vault_name` to an existing Key Vault accessible by the
Ansible controller. The existing secret upload/resolution roles use Azure CLI
to write/read the same `<name_prefix>-<environment>-<secret_id>` names there.
The controller needs secret get/set access; no vault, secret values, or access
credentials are added to Terraform. AWS/GCP secret branches remain unchanged.

## Authentication and manual checks

Use Azure CLI login with the intended subscription, or AzureRM's normal
`ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`, `ARM_CLIENT_ID`, and `ARM_CLIENT_SECRET`
environment variables (OIDC/managed identity are also supported by AzureRM).
No account IDs or authentication values belong in the shared config.

Inventory uses `azure.azcollection.azure_rm`, scoped to the generated resource
groups, names, and tags. It creates the existing role/workloads groups, selects
the configured `ssh_users` username, and uses the same bastion ProxyCommand.
Azure's VM UUID identifies SSH known-host entries across replacements.
Install `infrastructure/ansible/requirements.yml` and the installed
`azure.azcollection/requirements.txt` Python dependencies. Azure inventory uses
CLI login or its own `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT`, `AZURE_CLIENT_ID`,
and `AZURE_SECRET` variables; it does not read Terraform's `ARM_*` variables.
The secret roles also require an authenticated Azure CLI session.

Before deploying, manually check Azure region/SKU quotas, image availability,
SSH username/key compatibility, CIDR placement, and Key Vault access. Run your
schema checks, `terraform init`, `terraform fmt`, `terraform validate`, and
`terraform plan` with the normal backend and project-config arguments. Review
both database modes and an unchanged AWS/GCP config. After applying yourself,
inspect `terraform output -json vms`, `terraform output -json managed_database`,
and `ansible-inventory -i infrastructure/ansible/inventory/oilscope.yml --graph`;
check SSH/ProxyCommand, NAT egress, DNS, TLS PostgreSQL access, and blocked public
database access. Run `graphify update .` when you refresh the project graph.

References: [AzureRM Flexible Server](https://registry.terraform.io/providers/hashicorp/azurerm/4.62.0/docs/resources/postgresql_flexible_server),
[Azure inventory](https://docs.ansible.com/projects/ansible/latest/collections/azure/azcollection/azure_rm_inventory.html),
and [Key Vault CLI](https://learn.microsoft.com/en-us/cli/azure/keyvault/secret).
