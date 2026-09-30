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

The aggregate playbook prepares the managed database when selected, bootstraps the K3s server quorum, joins agents, and deploys the Kubernetes workloads. In `postgres_extensions`, workload preparation installs CNPG, waits for two PostgreSQL instances, and applies the existing migrations before applications. Publish the application and CNPG images and set `OILSCOPE_IMAGE_TAG` before running it. The control host needs `kubectl`, Helm, the `kubernetes.core` collection, and the Python dependencies in `infrastructure/ansible/requirements.txt`.

Both database modes install private Headlamp. See [CNPG and Headlamp](../../../../docs/k3s-platform.md) for registry/image preparation, existing-data limitations, private UI access, and verification commands. To update an existing K3s cluster's workloads, use `oilscope.platform.deploy_k3s_workloads` instead of the aggregate playbook.

Run from the repository root:

```bash
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The dynamic inventory publishes the resolved project configuration path to the
playbooks. Set `OILSCOPE_PROJECT_CONFIG` only when the file is not the
repository-root `project-config.json`.

The first server is selected by `k3s.bootstrap_server` (or the first sorted server key). All K3s nodes must share reachable private networking. The example uses three servers; add `k3s_agent` entries when separate worker capacity is useful.
Set `k3s.version` to a pinned K3s release when changing versions. The role
compares it with `k3s --version` on each node and reruns the installer only for
a missing or different version. Server upgrades run one node at a time before
agents. Changing only the K3s config restarts an existing service through its
handler.

## Cloudflare HTTPS

When the external project configuration sets `cloudflare.enabled` to `true`,
the K3s workload playbook installs cert-manager through Helm and requests a
Let's Encrypt certificate through Cloudflare DNS-01. Export
`CLOUDFLARE_API_TOKEN` in the controller shell before running the K3s workload
or full workload playbook. The standalone Compose `ui.yml` playbook still uses
Nginx and Certbot, but is not part of the aggregate path. The token needs scoped DNS Edit and Zone Read permissions
for the configured zone.

See [Cloudflare DNS and UI HTTPS](../../../../docs/cloudflare-https.md) for the
project configuration, Terraform workflow, certificate renewal behavior, and
the one-time nameserver delegation step.
