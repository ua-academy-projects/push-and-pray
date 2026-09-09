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

Run from the repository root, through `infrastructure/ansible/deploy.sh`
rather than `ansible-playbook` directly, using whichever inventory matches
the configuration's `default_cloud` — see
[inventory/README.md](../../inventory/README.md) for setup and the
`oilscope_cloud`/`oilscope_vm_key` contract both inventories expose:

```bash
# GCP
infrastructure/ansible/deploy.sh oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/project-config.json

# AWS
infrastructure/ansible/deploy.sh oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope-aws.yml \
  -e project_config_path=/absolute/path/project-config.json
```

`deploy.sh` takes exactly the same arguments as `ansible-playbook` - it's a
thin wrapper, not a replacement command - and refuses to report success when
the inventory/`--limit` combination given ends up matching zero hosts across
the whole run. That case can't be caught from inside the playbook itself:
`--limit` intersects with every play's own `hosts:` pattern independently
(including the preflight checks below), so a `--limit` that happens to
exclude every host in every play - `localhost` included - means nothing
inside Ansible's own execution model ever runs to catch it either. Plain
`ansible-playbook` remains fine for read-only commands
(`--syntax-check`, `--list-hosts`, `ansible-inventory --graph`, ...).

Every playbook validates `OILSCOPE_SSH_USER` against the configuration's
`ssh_users` before connecting to anything — see the SSH section of the
inventory README if that fails.

The deployment stops if a workload fails, preventing dependent workloads from being deployed.
