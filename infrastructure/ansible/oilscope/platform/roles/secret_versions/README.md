# Secret versions role

Synchronizes secret values in AWS Secrets Manager, Azure Key Vault, and Google
Secret Manager targets referenced by `secret_mappings` in the project
configuration. The role runs on `localhost`; Terraform creates the backing
secret service and access policies, while this role creates versions containing
the values. By default, it reads the latest enabled value and adds a version
only when the desired value differs.

The target catalog is derived from every VM and, in K3s mode, from the
cluster-level `k3s.secret_mappings` object:

- AWS secrets are scoped by the VM's effective region.
- Azure secrets are scoped by the deployment's Key Vault.
- GCP secrets are scoped by the configured project.
- Repeated references to the same container in the same scope are uploaded once.
- K3s application secrets are scoped to the GCP project and are marked as read
  by the application namespace rather than granting every node direct access.

Values come only from the controller process environment. A source variable is
the upper-case secret ID with non-alphanumeric characters replaced by
underscores: `db-password` becomes `DB_PASSWORD`. The role prints this mapping,
but never prints a value.

## Requirements

- The backing secret-manager resources and access policies must already exist
  after `terraform apply`.
- AWS targets require `boto3` in Ansible's controller Python and credentials
  with `secretsmanager:DescribeSecret`, `secretsmanager:GetSecretValue`, and
  `secretsmanager:PutSecretValue`.
- Azure targets require an authenticated Azure CLI session and the Key Vault
  Secrets Officer role assigned by Terraform. The secret object is created with
  its first value because Key Vault has no empty secret container.
- GCP targets require an authenticated `gcloud` and permission to describe the
  secret, list and access versions, and add versions.

Standard provider authentication applies. For example, select an AWS profile
with `AWS_PROFILE`, run `az login`, and authenticate `gcloud` before running the
playbook.

## Variables

- `secret_versions_config_file`: project configuration path. It defaults to the
  inventory-provided `project_config_path`.
- `secret_versions_gcp_project_id`: optional GCP project override.
- `secret_versions_azure_key_vault_name`: optional Azure Key Vault name
  override. By default, the role derives Terraform's deterministic name.
- `secret_versions_only`: optional list of secret IDs or derived environment
  variable names. Entries that match no configured secret select no targets.
- `secret_versions_force_upload`: add a new version even when the current value
  matches. It defaults to `false`; `upload_secret_versions` sets it to `true`.
- `secret_versions_gcloud`: `gcloud` executable, default `gcloud`.
- `secret_versions_az`: Azure CLI executable, default `az`.
- `secret_versions_azure_key_vault_api_version`: Azure Key Vault data-plane API
  version, default `7.4`.
- `secret_versions_python`: controller Python used for AWS, default
  `ansible_playbook_python`.

## Usage

This example deliberately rotates only the external API key:

```bash
export EXTERNAL_API_KEY="..."

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json" \
  -e '{"secret_versions_only": ["external-api-key"]}' \
  --check

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json" \
  -e '{"secret_versions_only": ["external-api-key"]}'
```

The explicit upload playbook forces a new version and is intended for deliberate
rotation. Check mode validates the source values, target containers, and read
access without adding versions. Payloads pass on stdin with no trailing newline,
and comparisons and other secret-bearing tasks use `no_log`. All targets are
validated before uploading; an external API failure during the upload phase can
still leave a partial rotation and should be retried after the cause is fixed.
Database password rotation requires changing PostgreSQL and its secret value as
one coordinated operation; uploading a new `DB_PASSWORD` version alone is not
sufficient.

In K3s mode, uploading a new version does not change an existing Kubernetes
Secret automatically. Rerun `oilscope.platform.synchronize_k3s_secrets` and
restart the affected workloads as part of the rotation procedure.

To rotate only one container:

```bash
ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json" \
  -e '{"secret_versions_only": ["db-password"]}'
```

See [docs/secrets.md](../../../../../../docs/secrets.md) for the complete model.

## License

GPL-2.0-or-later
