# Ansible Collection - oilscope.platform

Documentation for the collection.

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
