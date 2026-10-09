# Ansible Collection - oilscope.platform

Documentation for the collection.

The dynamic inventory reads the same JSON as Terraform and discovers selected
GCP, AWS and Azure VMs. Each cloud gets its own `cloud_<name>` group, while one
global bastion remains the SSH jump host. Azure authentication uses the active
`az login` session.

Install the controller dependencies before deployment:

```bash
python3 -m venv ~/.venvs/oilscope-ansible
source ~/.venvs/oilscope-ansible/bin/activate
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
pip install -r ~/.ansible/collections/ansible_collections/azure/azcollection/requirements.txt
```

## Validate configuration

Before deploying, validate your project configuration file against the schema:

​```bash
uvx check-jsonschema \
  --schemafile infrastructure/terraform/project-config.schema.json \
  /absolute/path/project-config.json
​```

## Deploy all workloads

Deploy the application workloads in dependency order:

1. Verify Terraform-bootstrapped Tailscale and enforce one K3s subnet router per cloud
2. Direct tailnet and routed cross-cloud connectivity checks
3. Cloud monitoring agents
4. K3s servers and agents when K3s groups are present
5. Private Headlamp, Technitium DNS and Homepage cluster dashboards
6. CloudNativePG in Kubernetes database mode, Kubernetes Secrets, the
   cert-manager Helm chart, Let's Encrypt, RabbitMQ and database migrations
7. History, Fetcher, UI and the NGINX HTTPS proxy
8. Legacy role-based Compose workloads when their inventory groups are present

Run from the repository root:

```bash
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

The deployment stops if a workload fails, preventing dependent workloads from being deployed.

To configure only the monitoring agents, run:

```bash
ansible-playbook oilscope.platform.monitoring_agents \
  -i infrastructure/ansible/inventory/oilscope.yml
```

To install or update only Technitium and its Homepage widget, run:

```bash
ansible-playbook oilscope.platform.technitium \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

The Azure play installs the Azure Monitor Agent extension. Terraform creates
and associates the Azure Data Collection Rules. When K3s groups are present,
the same deployment playbook builds the cluster and deploys OilScope; see the
[K3s guide](../../../../docs/k3s.md). Cross-cloud routing is described in the
[Tailscale guide](../../../../docs/tailscale.md).
