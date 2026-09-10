# Supported Docker Compose deployment

The supported cloud deployment uses the `oilscope.platform` Ansible collection.
Terraform creates the VMs, networking, workload identities, and secret
containers. Terraform cloud-init configures only the bastion's SSH service;
Ansible configures and deploys the workload VMs.

Each workload VM receives one role-specific Compose definition:

| Inventory group | Compose services | Installed file |
| --- | --- | --- |
| `database` | PostgreSQL and the migration job | `/opt/oilscope/app/compose.yaml` |
| `history` | History | `/opt/oilscope/app/compose.yaml` |
| `fetcher` | Fetcher | `/opt/oilscope/app/compose.yaml` |
| `ui` | UI | `/opt/oilscope/app/compose.yaml` |
| `ui` | Traefik proxy | `/opt/oilscope/proxy/compose.yaml` |

The application images use the immutable Git commit tag from
`registry.image_tag` in `project-config.json`. The database image is the
project's `database` image with the same tag.

## Secrets

Terraform creates no secret values. Before deployment, upload values from the
controller environment:

```sh
export DB_PASSWORD="$(openssl rand -hex 32)"
export GHCR_TOKEN="..."
export EXTERNAL_API_KEY="..."

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json" \
  --check

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json"
```

During workload deployment, each VM retrieves only its configured secrets
through its attached AWS or GCP identity. Ansible passes values to Compose in
the command environment and does not create a persistent deployment environment
file.

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

Deploy all workloads in dependency order:

```sh
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The orchestrator deploys Database, History, Fetcher, and UI in that order. The
UI play also starts Traefik, which terminates HTTPS and redirects HTTP traffic
from port 80 to port 443.

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

## Historical deployment files

`infrastructure/terraform/cloud-init/` and
`compose.deployment.yaml.j2` preserve the earlier workload cloud-init exercise.
They are not referenced by the current Terraform or Ansible deployment path.
