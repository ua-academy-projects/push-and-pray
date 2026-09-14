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

1. Database
2. History
3. Fetcher
4. UI

Run from the repository root:

```bash
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.gcp.yml \
  -e project_config_path=/absolute/path/project-config.json
```

The deployment stops if a workload fails, preventing dependent workloads from being deployed.

## Ship logs and metrics

Every deployment playbook installs the cloud's observability agent alongside
Docker, so a deployed host already ships its journal — container output
included — and host metrics. To roll an agent change out on its own, without
touching a container:

```bash
ansible-playbook oilscope.platform.observability \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

See `docs/observability.md` for where the logs land and how to query them.
