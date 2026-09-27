# Ansible Collection - oilscope.platform

Documentation for the collection.

The dynamic inventory reads the same JSON as Terraform and discovers selected
GCP, AWS and Azure VMs. Each cloud gets its own `cloud_<name>` group and its own
bastion path. Azure authentication uses the active `az login` session.

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

1. Cloud monitoring agents
2. Database
3. History
4. Fetcher
5. UI

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

The Azure play installs the Azure Monitor Agent extension. Guest data starts
flowing only after an Azure Data Collection Rule is created and associated with
the VM.
