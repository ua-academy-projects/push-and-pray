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
  -i infrastructure/ansible/inventory/oilscope.yml
```

The dynamic inventory publishes the resolved project configuration path to the
playbooks. Set `OILSCOPE_PROJECT_CONFIG` only when the file is not the
repository-root `project-config.json`.

The deployment stops if a workload fails, preventing dependent workloads from being deployed.

## Cloudflare HTTPS

When the external project configuration sets `cloudflare.enabled` to `true`,
the UI play installs Nginx and obtains a Let's Encrypt certificate with the
Cloudflare DNS plugin. Export `CLOUDFLARE_API_TOKEN` in the controller shell
before running the UI or full workload playbook. The token needs scoped DNS
Edit, Zone Settings Edit, and Zone Read permissions for the configured zone.

See [Cloudflare DNS and UI HTTPS](../../../../docs/cloudflare-https.md) for the
project configuration, Terraform workflow, certificate renewal behavior, and
the one-time nameserver delegation step.
