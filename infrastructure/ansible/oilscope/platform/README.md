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
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json
```

The deployment stops if a workload fails, preventing dependent workloads from being deployed.

The inventory discovers both GCP and AWS according to `default_cloud` and
per-VM `cloud` overrides. Private addresses are only routable inside their own
cloud network. A cross-cloud VPN or overlay is required before a bastion or
application in one cloud can reach a private workload in the other.
