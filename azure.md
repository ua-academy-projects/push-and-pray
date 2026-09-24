# Task: add Azure as a third cloud

Created: 2026-09-21. Status: not started.

## Goal

The application currently deploys to AWS and GCP from one JSON project
configuration. Add Microsoft Azure as a third, equally supported cloud, so that
a configuration selecting Azure provisions and deploys the same architecture —
bastion, fetcher, history + RabbitMQ, UI + Redis + reverse proxy, and a
PostgreSQL store in either `application` or `cloud` database mode — with no
change to application code.

"Supported" means feature parity with what AWS and GCP already have in this
repository: network, VMs, secrets, managed database, monitoring, and budget,
plus the Ansible deployment path that drives them.

## Mandatory ordering

**Phase 1 (Terraform) must be complete and reviewed before Phase 2 (Ansible)
starts.** Ansible consumes Terraform outputs (`terraform_outputs_path`), so the
output contract has to exist and be stable first. Do not interleave the phases.
Within Phase 1, land the configuration schema before the modules that read it.

## Background: how multicloud works here today

Read these before writing anything:

- [infrastructure/terraform/locals.tf](infrastructure/terraform/locals.tf) — the
  whole configuration is `jsondecode(file(var.project_config_path))`, with
  monitoring defaults merged in once.
- [infrastructure/terraform/main.tf](infrastructure/terraform/main.tf) — every
  module for every cloud is instantiated unconditionally and passed
  `local.config`. Modules gate themselves internally (`count`, a `local.enabled`
  flag, `try(..., null)`), so an unused cloud plans to zero resources rather
  than being excluded from the graph.
- [infrastructure/terraform/outputs.tf](infrastructure/terraform/outputs.tf) —
  per-cloud outputs (`aws_database_connection`, `gcp_monitoring`, …) plus merged
  cross-cloud maps (`vm_names`, `vm_internal_ips`, `vm_public_ips`,
  `secret_ids`).
- [project-config.cloud-example.json](project-config.cloud-example.json) — the
  cloud-neutral vocabulary. `size_map`, `region_map`, `disk_type_map`,
  `image_map`, `database_profile_map` and `clouds` are each keyed by cloud, and
  the VM definitions in `vms` are written once in neutral terms.
- [infrastructure/terraform/project-config.schema.json](infrastructure/terraform/project-config.schema.json)
  — the schema those files are validated against.

The design rule to preserve: **`vms`, `network`, `rabbitmq`, `redis`,
`registry`, `service_ports` and `ssh_users` stay cloud-neutral.** Everything
Azure-specific belongs in the per-cloud branches of the maps and under
`clouds.azure`. Adding Azure must not require editing a single VM definition.

## Phase 1 — Terraform

### 1.1 Configuration

Add an `azure` branch everywhere a cloud branch already exists:

| Location | Add |
|---|---|
| `size_map.<size>` | `azure`: VM size, e.g. `Standard_B1s`, `Standard_B1ms`, `Standard_B2s` |
| `region_map.<region>` | `azure`: `{ "location": "germanywestcentral", "availability_zone": "1" }` |
| `disk_type_map.<type>` | `azure`: `Standard_LRS` / `StandardSSD_LRS` / `Premium_LRS` |
| `image_map.<image>` | `azure`: publisher/offer/sku/version for the Ubuntu image |
| `database_profile_map.<profile>` | `azure`: `sku_name`, `postgres_version`, `storage_mb`, `storage_tier`, `backup_retention_days`, `high_availability`, `zone` |
| `clouds.azure` | `subscription_id`, `resource_group_name` (or a create/reuse flag), `vnet_cidr`, and a `postgres_network` block for the delegated subnet CIDR |
| `budgets.azure` | same shape as `budgets.aws`: `enabled`, `monthly_amount`, `currency`, `actual_thresholds`, `email_recipients` |
| `default_cloud` | accept `"azure"` |

Then:

1. Extend `project-config.schema.json` with the same structures and the same
   strictness as the AWS/GCP branches — required keys, enums, no permissive
   additions.
2. Update both [project-config.example.json](project-config.example.json) and
   [project-config.cloud-example.json](project-config.cloud-example.json) with
   realistic Azure values.
3. **No fallback values.** Consistent with the existing decision that all
   selected infrastructure settings come explicitly from JSON: a missing Azure
   key must fail the plan, not silently default. The only exception is the
   `monitoring` block, which already has documented defaults in `locals.tf`.

### 1.2 Modules to create

Create `infrastructure/terraform/modules/azure/<name>/` mirroring the AWS and
GCP layouts, including the file split (`main.tf`, `variables.tf`, `outputs.tf`,
`locals.tf`, and topic files where they help).

| Module | Mirrors | Must provide |
|---|---|---|
| `azure/network` | `aws/network`, `gcp/network` | VNet, management + workload subnets, NSGs per role (bastion, history, fetcher, ui, database), public IPs, egress for private subnets, and a delegated subnet + private DNS zone for PostgreSQL |
| `azure/vm` | `aws/vm`, `gcp/vm` | Linux VMs per `vms` entry, static private IPs from `internal_ip`, public IP only when `assign_public_ip`, SSH keys from `ssh_users`, a user-assigned managed identity per VM, and monitoring wiring |
| `azure/secrets` | `aws/secrets`, `gcp/secrets` | Key Vault plus one secret container per distinct ID in `secret_mappings`, with read access granted only to the managed identity of the VMs that map it |
| `azure/database` | `aws/database`, `gcp/database` | PostgreSQL Flexible Server, private VNet integration, TLS, admin credential handling, active only in `cloud` database mode |
| `azure/monitoring` | `aws/monitoring`, `gcp/monitoring` | Log Analytics workspace, agent configuration emitted for Ansible, metric alerts, action group, dashboard, log collection, availability check |
| `azure/budget` | `aws/budget`, `gcp/budget` | Subscription or resource-group budget with the configured thresholds and recipients |

### 1.3 Azure service mapping

Verify every resource name and argument against current provider documentation
before use — do not rely on memory for API details.

| Concept | AWS | GCP | Azure |
|---|---|---|---|
| Network | VPC + subnets | VPC + subnetworks | `azurerm_virtual_network` + `azurerm_subnet` |
| Firewall | Security groups | Firewall rules + tags | `azurerm_network_security_group` + `azurerm_subnet_network_security_group_association` |
| VM | `aws_instance` | `google_compute_instance` | `azurerm_linux_virtual_machine` + `azurerm_network_interface` |
| VM identity | IAM role + instance profile | Service account | `azurerm_user_assigned_identity` + role assignments |
| Public address | `aws_eip` | `google_compute_address` | `azurerm_public_ip` |
| Managed PostgreSQL | RDS | Cloud SQL | `azurerm_postgresql_flexible_server` |
| Private DB access | Private subnets + SG | Private services access | Delegated subnet (`Microsoft.DBforPostgreSQL/flexibleServers`) + `azurerm_private_dns_zone` + `azurerm_private_dns_zone_virtual_network_link` |
| Secrets | Secrets Manager | Secret Manager | `azurerm_key_vault` + `azurerm_key_vault_secret` |
| Metrics/logs | CloudWatch | Cloud Monitoring / Ops Agent | Azure Monitor: Log Analytics + Azure Monitor Agent + data collection rules |
| Alerts | CloudWatch alarms + SNS | Alert policies + notification channels | `azurerm_monitor_metric_alert` + `azurerm_monitor_action_group` |
| Synthetic check | Synthetics canary | Uptime check | Application Insights availability test |
| Budget | `aws_budgets_budget` | Billing budget | `azurerm_consumption_budget_subscription` |

The PostgreSQL Flexible Server private pattern is: subnet with a
`Microsoft.DBforPostgreSQL/flexibleServers` delegation, a private DNS zone named
`<something>.postgres.database.azure.com` linked to the VNet, and the server
created with `delegated_subnet_id`, `private_dns_zone_id` and
`public_network_access_enabled = false`, depending on the zone link.

### 1.4 Root wiring

1. [versions.tf](infrastructure/terraform/versions.tf) — add `azurerm` (and
   `azapi` only if genuinely required) to `required_providers` with a pinned
   constraint, matching the existing style.
2. [providers.tf](infrastructure/terraform/providers.tf) — add
   `provider "azurerm" { features {} }`, reading `subscription_id` from the
   configuration the way the `google` provider does. **Credentials come from the
   environment or Azure CLI login, never from the project configuration file** —
   the same rule the Cloudflare provider comment already states.
3. Each new module needs its own `terraform { required_providers { azurerm = { source = "hashicorp/azurerm" } } }`
   block, because provider *configuration* is inherited by child modules but
   provider *source* requirements are not. See
   [modules/cloudflare/dns/versions.tf](infrastructure/terraform/modules/cloudflare/dns/versions.tf)
   for the precedent.
4. [main.tf](infrastructure/terraform/main.tf) — instantiate
   `azure_network`, `azure_vm`, `azure_secrets`, `azure_database`,
   `azure_monitoring`, `azure_budget` with the same argument style
   (`config = local.config`, `network = module.azure_network`, …).
5. [outputs.tf](infrastructure/terraform/outputs.tf) — add
   `azure_database_connection` and `azure_monitoring`, add
   `module.azure_secrets` to `secret_ids` and `secret_resource_names`, add
   `module.azure_vm.vms` to the `vm_names` / `vm_internal_ips` /
   `vm_public_ips` merges, and add `azure` to the `budgets` output.
6. [modules/cloudflare/dns/](infrastructure/terraform/modules/cloudflare/dns/)
   — it currently takes `aws_vms` and `gcp_vms`. Add `azure_vms` so the UI
   record can point at an Azure host.

### 1.5 Output contract

The Azure modules must emit the same shapes their AWS/GCP counterparts do,
because `outputs.tf` and the Ansible roles consume them positionally:

- `vm` module → `vms` keyed by VM name, each with at least `name`,
  `internal_ip`, `public_ip` (null when not assigned), plus the Azure identity
  fields that replace `role_arn` / `service_account_email`.
- `database` module → `connection` (`host`, `port`, `database`,
  `admin_username`, an admin-secret reference, `sslmode = "verify-full"`,
  `ca_bundle_url`) and `monitoring` (`id`), both `null` when disabled. **No
  password values in outputs.**
- `secrets` module → `secret_ids` and `secret_resource_names`.
- `monitoring` module → the same keys `gcp_monitoring` / `aws_monitoring`
  expose, notably `agent_configurations` and `collector_configurations` keyed by
  VM key, since the Ansible role indexes them by `oilscope_vm_key`.
- `network` module → subnet/VNet/NSG identifiers the other modules need.

### 1.6 Phase 1 acceptance

- `terraform init` and `terraform validate` succeed.
- `terraform fmt -check -recursive` is clean.
- With an Azure configuration: `terraform plan` produces a complete Azure
  plan and **zero** AWS or GCP resources.
- With the existing AWS configuration: `terraform plan` is unchanged from
  before this work — no diff introduced by the Azure addition.
- Both database modes plan correctly: `cloud` creates the Flexible Server,
  `application` creates none and forbids database-role VMs, as today.
- No secret value appears in any output.

## Phase 2 — Ansible

Start only after Phase 1 is reviewed.

The collection is `oilscope.platform` at
[infrastructure/ansible/oilscope/platform](infrastructure/ansible/oilscope/platform).
Cloud-specific behaviour is isolated behind an `oilscope_cloud` fact, which the
dynamic inventory plugin sets from the instance itself. The pattern to follow is
in [roles/resolve_secrets/tasks/main.yml](infrastructure/ansible/oilscope/platform/roles/resolve_secrets/tasks/main.yml):
a guard that fails on an unknown cloud, then `include_tasks: <cloud>.yml`.

### 2.1 Work items

1. **Inventory plugin** — add
   `plugins/inventory/oilscope_azure.py` alongside `oilscope_aws.py` and
   `oilscope_gcp.py`, sharing
   [module_utils/oilscope_inventory.py](infrastructure/ansible/oilscope/platform/plugins/module_utils/oilscope_inventory.py).
   It must derive `oilscope_vm_key` and `oilscope_cloud` from the instance's own
   name or tags — not from `inventory_hostname` — so a renamed host cannot be
   pointed at the wrong VM's secrets. Add
   `inventory/oilscope-azure.yml` mirroring
   [inventory/oilscope-aws.yml](infrastructure/ansible/inventory/oilscope-aws.yml).

2. **Per-cloud task files** — add `azure.yml` next to the existing `aws.yml` and
   `gcp.yml`, and extend the dispatch and the supported-cloud guard in each
   `main.yml`, in these roles:
   - `resolve_secrets` — read secret values from Key Vault using the VM's
     managed identity.
   - `secret_versions` — upload new secret versions from the controller.
   - `monitoring_agent` — install and configure the Azure Monitor Agent and its
     data collection rule, in place of the CloudWatch Agent / Ops Agent.

3. **Other cloud-aware files** — audit and extend:
   `roles/database_migrate/tasks/read_secret.yml`,
   `roles/application_monitoring/`, and any playbook or `meta/main.yml` that
   enumerates clouds. Grep for `'gcp'` and `'aws'` to find every branch; several
   guards list the two clouds explicitly and will reject `azure` until updated.

4. **Dependencies** — add `azure.azcollection` to
   [requirements.yml](infrastructure/ansible/requirements.yml) and its Python
   dependencies to [requirements.txt](infrastructure/ansible/requirements.txt),
   pinned in the existing style. Check whether the `requires_ansible` floor in
   `meta/runtime.yml` needs to rise for that collection.

5. **Database TLS** — the `database_connection` role mounts a CA bundle. Azure
   Flexible Server uses a different root CA from RDS; the `ca_bundle_url` the
   Terraform module emits must be the correct one, and `sslmode=verify-full`
   must keep working against the server's certificate SAN.

### 2.2 Phase 2 acceptance

- `ansible-lint` and `yamllint` pass on the collection.
- The Azure inventory plugin lists every VM with correct `oilscope_vm_key`,
  `oilscope_cloud: azure`, and bastion-proxied SSH for private hosts.
- `deploy_workloads` runs end to end against Azure with no failed or
  unreachable hosts, in the existing order: local DB play skipped in cloud mode
  → managed migration from History → RabbitMQ → History → Fetcher → UI.
- AWS and GCP deployments are unaffected — re-run at least one to confirm.

## Documentation

Update, in the same voice as the existing pages:
[README.md](README.md), [docs/database-modes.md](docs/database-modes.md),
[docs/monitoring.md](docs/monitoring.md), [docs/secrets.md](docs/secrets.md),
[docs/dns.md](docs/dns.md), and
[infrastructure/ansible/inventory/README.md](infrastructure/ansible/inventory/README.md).
Each already describes AWS and GCP side by side; Azure joins them as a third
column or section rather than an appendix.

## Constraints

- Nothing in `services/`, `database/` or the Docker images changes. If Azure
  support seems to require an application change, stop and raise it.
- No credentials in the project configuration or in Terraform outputs.
- Preserve the existing decisions in
  [text-implement-configurable-database-elegant-corbato.md](text-implement-configurable-database-elegant-corbato.md):
  RabbitMQ for fetcher→history, Redis for UI sessions, `managed_database` required
  with no fallback, no automated tests added without a new request.
- Provisioning real Azure resources costs money and is **not** authorized by
  this document. Implement and validate with `plan`; a live apply needs separate
  approval.

## Decide before implementing

1. Azure subscription, tenant and target location — and whether the resource
   group is created by Terraform or referenced as existing.
2. VM sizes and PostgreSQL SKU for the `economy` profile, and whether the goal
   is the free/credit tier as it was for AWS.
3. Whether monitoring parity is required from the start or alerts and
   dashboards can land in a follow-up.
4. Whether Azure ever runs simultaneously with AWS/GCP, or only as an
   alternative — this decides whether the merged VM outputs need to stay unique
   across three clouds at once.
