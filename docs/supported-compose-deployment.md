# Supported Docker Compose deployment

The supported cloud deployment uses the `oilscope.platform` Ansible collection.
Terraform creates the VMs, networking, workload identities, and secret
containers. Terraform cloud-init configures only the bastion's SSH service;
Ansible configures and deploys the workload VMs.

The complete Terraform-and-Ansible deployment supports AWS, GCP, and Azure with
either database architecture. The Azure path includes the resource group,
networking and NAT, NSGs, bastion and workload VMs, managed identities, Key
Vault secret synchronization and workload resolution, dynamic inventory,
Azure Monitor resources, the public UI address, and private Azure Database for
PostgreSQL Flexible Server when `database.mode` is `managed`.

For Azure, `locations.<name>.azure.region` uses [region names][azure-regions]
such as `swedencentral`, `eastus`, and `mexicocentral`. The `zone` field is
optional; the examples select zone `1`, which must be available to the selected
VM size in your subscription. The Azure mappings use [B-series sizes][azure-b]:
`Standard_B2ats_v2` (1 GiB), `Standard_B2als_v2` (4 GiB), and
`Standard_B2as_v2` (8 GiB),
with [Canonical Ubuntu][azure-ubuntu] 24.04/26.04 images and Standard/Premium
SSD disks. Azure Ubuntu OS disks are typically at least [30 GB][azure-disks],
so use 32 GB or more for boot disks in an Azure configuration. Confirm regional
SKU/image availability and set a budget alert before deployment; five VMs and
their network/storage resources are not covered by a [single free-VM
allowance][azure-free].
`Standard_B2ats_v2` is eligible for the Azure free-account VM allowance, subject
to the account's time and quantity limits. The $200 trial credit can be used for
other eligible charges during the trial. An Azure deployment also requires the
non-secret `cloud_settings.azure.subscription_id`; authentication remains
external to project configuration, for example through `az login`.

[azure-regions]: https://learn.microsoft.com/en-us/azure/reliability/regions-list
[azure-b]: https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/basv2-series
[azure-ubuntu]: https://ubuntu.com/azure/docs/azure-how-to/instances/find-ubuntu-images/
[azure-disks]: https://learn.microsoft.com/en-us/azure/virtual-machines/linux/expand-disks
[azure-free]: https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/create-free-services

Start from the complete example matching the selected database architecture:

- [`project-config.self-managed-db.example.json`](../project-config.self-managed-db.example.json)
- [`project-config.managed-db.example.json`](../project-config.managed-db.example.json)

`database.mode` in `project-config.json` selects the architecture:

```json
"database": {
  "mode": "self_managed"
}
```

A self-managed database (`self_managed`) runs PostgreSQL and its extensions on
the infrastructure VM. A managed database (`managed`) creates private Cloud SQL,
RDS PostgreSQL, or Azure Database for PostgreSQL Flexible Server according to
`default_cloud`, and runs RabbitMQ and Redis on the infrastructure VM. A managed
database additionally requires the PostgreSQL `version`, database `size`, and
`storage_gb` settings. Self-managed database compute is configured through the
`infrastructure` VM's `machine_type`.

```json
"database": {
  "mode": "managed",
  "version": "18",
  "size": "micro",
  "storage_gb": 20
}
```

Azure managed PostgreSQL requires at least 32 GB of storage and a dedicated
subnet in `network.managed_database.azure_delegated_subnet_cidr`. Terraform
delegates that subnet to Flexible Server, disables public database access, and
creates the private `postgres.<name>-<environment>.internal` hostname used by
Ansible. The subnet must not overlap the public, private, GCP, or AWS ranges.

An optional `data_disks` entry on the infrastructure VM only creates and
attaches the disk. The current Terraform and Ansible code does not format or
mount it, and PostgreSQL continues to use its Compose named volume on the boot
disk until disk preparation and a matching Compose mount are configured.

Development RDS instances set `backup_retention_period` to `0`, delete
automated backups, and skip a final snapshot. Stage and production retain seven
days of backups, require a final snapshot, and enable deletion protection.

Each workload VM receives one role-specific Compose definition:

| Inventory group | Compose services | Installed file |
| --- | --- | --- |
| `infrastructure` | PostgreSQL, or RabbitMQ and Redis; migration job | `/opt/oilscope/app/compose.yaml` |
| `history` | History | `/opt/oilscope/app/compose.yaml` |
| `fetcher` | Fetcher | `/opt/oilscope/app/compose.yaml` |
| `ui` | UI | `/opt/oilscope/app/compose.yaml` |
| `ui` | Traefik proxy | `/opt/oilscope/proxy/compose.yaml` |

Application images use the OCI tag from `registry.image_tag`. The current image
workflow publishes exact Git tags matching `v*` or `andrii-miroshnyk-*`; it does
not create a bare `andrii-miroshnyk` tag. Use an immutable release tag for shared
deployments. The database image is required with both database architectures
because it also provides the migration command.

```json
"registry": {
  "repository": "ghcr.io/example-org/example-project",
  "username": "example-operator",
  "image_tag": "v1.0.0"
}
```

## Secrets

Terraform creates no secret values. Before deployment, export values in the
controller environment:

```sh
export DB_PASSWORD="$(openssl rand -hex 32)"
export GHCR_TOKEN="..."
export EXTERNAL_API_KEY="..."

# Managed database only:
export RABBITMQ_PASSWORD="$(openssl rand -hex 32)"
export REDIS_PASSWORD="$(openssl rand -hex 32)"
export TF_VAR_database_password="${DB_PASSWORD}"
```

The VM `secret_mappings` must follow the selected database architecture. A
self-managed database deployment omits RabbitMQ and Redis mappings. A managed
database deployment maps
`RABBITMQ_PASSWORD` on Infrastructure, History, and Fetcher and maps
`REDIS_PASSWORD` on Infrastructure and UI. `TF_VAR_database_password` is also
needed only when Terraform provisions a managed database.

The general deployment synchronizes changed or missing versions before any VM
configuration. During workload deployment, each VM retrieves only its configured
secrets through its attached AWS or GCP identity. Ansible passes values to
Compose in the command environment and does not create a persistent deployment
environment file.

Reuse the same values on later deployments. Generating new values changes the
desired state and intentionally creates new secret versions.

See [secrets.md](secrets.md) for provider requirements and rotation guidance.

## Create the infrastructure

From the repository root, initialize Terraform and validate the configuration:

```sh
terraform -chdir=infrastructure/terraform init \
  -backend-config="bucket=<terraform-state-bucket>" \
  -backend-config="prefix=<terraform-state-prefix>"

terraform -chdir=infrastructure/terraform validate
```

The root module uses a GCS backend, including when the selected deployment cloud
is AWS or Azure. Supply the existing state bucket and prefix for the environment.

For a managed database, export the same database password that Ansible will
upload to the cloud secret container. A self-managed database does not require
this Terraform variable:

```sh
export DB_PASSWORD="..."
export TF_VAR_database_password="${DB_PASSWORD}"
```

Create and apply a saved plan:

```sh
terraform -chdir=infrastructure/terraform plan \
  -var='project_config_path=../../project-config.json' \
  -out=tfplan

terraform -chdir=infrastructure/terraform apply tfplan
```

For a self-managed database, omit `TF_VAR_database_password` or remove it from
the shell with `unset TF_VAR_database_password` before planning.

## Deploy the applications

After Terraform has created the infrastructure, the DNS record points to the UI
VM's current public address, and the Ansible collection has been installed,
inspect the inventory:

```sh
ansible-inventory \
  -i infrastructure/ansible/inventory/oilscope.yml \
  --graph
```

Prepare hosts, configure the selected cloud's monitoring agent, and deploy all
workloads in dependency order:

```sh
ansible-playbook oilscope.platform.deploy \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The orchestrator synchronizes secrets, prepares workload hosts, installs the
provider-specific monitoring agent, and then deploys Infrastructure, History,
Fetcher, and UI. The UI play also starts Traefik, which terminates HTTPS and
redirects HTTP traffic from port 80 to port 443.

To deploy one component, run its playbook directly, for example:

```sh
ansible-playbook oilscope.platform.history \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The required dependencies must already be healthy when deploying an individual
component.

## Operate a workload

Run these commands on the applicable VM through the bastion:

```sh
sudo docker compose \
  --project-name petroscope \
  --file /opt/oilscope/app/compose.yaml \
  ps

sudo docker compose \
  --project-name petroscope \
  --file /opt/oilscope/app/compose.yaml \
  logs --follow
```

On the UI VM, inspect Traefik separately:

```sh
sudo docker compose \
  --project-name oilscope-proxy \
  --file /opt/oilscope/proxy/compose.yaml \
  ps
```

Redeploy by rerunning the relevant Ansible playbook. This refreshes the
Compose definition, resolves the current secrets, pulls the configured image,
reconciles the container, and verifies its health.

AWS and GCP deployments use Docker's default JSON log files, which their
observability agents collect from workload hosts. Azure workload Compose
definitions instead use Docker's `syslog` logging driver to send container
output directly to the host's `local0` facility collected by the
Terraform-managed data collection rule.

## Destroy the infrastructure

After the environment is no longer needed, use the same configuration path and,
for a managed database, the same `TF_VAR_database_password` value:

```sh
terraform -chdir=infrastructure/terraform destroy \
  -var='project_config_path=../../project-config.json'
```
