# Multi-cloud dynamic inventory

`oilscope.yml` uses the `oilscope.platform.oilscope_gcp` wrapper. The plugin
keeps its historical name for compatibility, but now discovers both GCP
Compute Engine and AWS EC2 instances.

The wrapper reads the same external project JSON as Terraform. It applies
`default_cloud` and each VM's optional `cloud` override, resolves the selected
region or zone from the cloud dictionaries, and runs only the live inventory
plugins needed by that configuration.

Terraform attaches these tags or labels to every VM:

- `application`;
- `environment`;
- `role`;
- `cloud` (`gcp` or `aws`).

Terraform also attaches non-secret database and queue connection metadata as
EC2 tags or Compute Engine metadata. The inventory exposes those values as
`database_*` and `queue_*` host variables. Passwords are never attached to a VM
tag or metadata value; `resolve_secrets` reads them from the selected cloud's
secret manager during deployment.

The inventory filters by `application`, `environment`, and `cloud`, creates
role groups such as `bastion`, `database`, and `history`, and also creates
`cloud_gcp`, `cloud_aws`, and `workloads` groups.

## Controller setup

```sh
pip install -r infrastructure/ansible/requirements.txt
ansible-galaxy collection install -r infrastructure/ansible/requirements.yml
```

Use Application Default Credentials for GCP. AWS uses the normal AWS SDK
credential chain; set `AWS_PROFILE` if a named CLI profile is required.

```sh
export OILSCOPE_PROJECT_CONFIG=/absolute/path/to/dev.json
export OILSCOPE_SSH_KEY=/absolute/path/to/private-key
export AWS_PROFILE=oil-user
ansible-inventory -i infrastructure/ansible/inventory/oilscope.yml --graph
```

Deployment playbooks also consume the file directly, so pass the same path as
an extra variable:

```sh
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path=/absolute/path/to/dev.json
```

No account ID or credentials are stored in the project JSON. The inventory
contains no cross-cloud routing: a topology split between providers must not
assume that private addresses are reachable across clouds.
