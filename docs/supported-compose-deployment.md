# Supported Docker Compose deployment

The supported cloud deployment uses the `oilscope.platform` Ansible collection.
Terraform creates the VMs, networking, workload identities, and secret
containers. Terraform cloud-init configures only the bastion's SSH service;
Ansible configures and deploys the workload VMs.

`database.mode` in `project-config.json` selects the architecture:

```json
"database": {
  "mode": "self_managed",
  "version": "18",
  "size": "micro",
  "storage_gb": 20
}
```

`self_managed` runs PostgreSQL and its extensions on the infrastructure VM.
`managed` creates private Cloud SQL or RDS PostgreSQL according to
`default_cloud`, and runs RabbitMQ and Redis on the infrastructure VM. Both
providers use the configured 20 GB development storage allocation.

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

Application images use the OCI tag from `registry.image_tag`. A personal,
mutable tag such as `andrii-miroshnyk` is suitable for an isolated development
environment; use an immutable version tag for shared or release deployments.
The database image is required in both database modes because it also provides
the migration command.

```json
"registry": {
  "repository": "ghcr.io/example-org/example-project",
  "username": "example-operator",
  "image_tag": "example-operator"
}
```

## Secrets

Terraform creates no secret values. Before deployment, export values in the
controller environment:

```sh
export DB_PASSWORD="$(openssl rand -hex 32)"
export RABBITMQ_PASSWORD="$(openssl rand -hex 32)"
export REDIS_PASSWORD="$(openssl rand -hex 32)"
export GHCR_TOKEN="..."
export EXTERNAL_API_KEY="..."
export TF_VAR_database_password="${DB_PASSWORD}"
```

The general deployment synchronizes changed or missing versions before any VM
configuration. During workload deployment, each VM retrieves only its configured
secrets through its attached AWS or GCP identity. Ansible passes values to
Compose in the command environment and does not create a persistent deployment
environment file.

Reuse the same values on later deployments. Generating new values changes the
desired state and intentionally creates new secret versions.

See [secrets.md](secrets.md) for provider requirements and rotation guidance.

## Deploy

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

The cloud deployment uses Docker's default JSON log files. The observability
playbooks configure the appropriate cloud agent to collect those workload logs.
