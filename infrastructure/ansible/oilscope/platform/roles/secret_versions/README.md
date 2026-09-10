# Secret versions role

Adds secret values to the AWS Secrets Manager and Google Secret Manager
containers referenced by `secret_mappings` in the project configuration. The
role runs on `localhost`; Terraform creates the containers and access policies,
while this role creates versions containing the values.

The target is derived for every VM:

- AWS secrets are scoped by the VM's effective region.
- GCP secrets are scoped by the configured project.
- Repeated references to the same container in the same scope are uploaded once.

Values come only from the controller process environment. A source variable is
the upper-case secret ID with non-alphanumeric characters replaced by
underscores: `db-password` becomes `DB_PASSWORD`. The role prints this mapping,
but never prints a value.

## Requirements

- The secret containers must already exist after `terraform apply`.
- AWS targets require `boto3` in Ansible's controller Python and credentials
  with `secretsmanager:DescribeSecret` and `secretsmanager:PutSecretValue`.
- GCP targets require an authenticated `gcloud` and permission to describe the
  secret and add versions.

Standard provider authentication applies. For example, select an AWS profile
with `AWS_PROFILE` and authenticate `gcloud` before running the playbook.

## Variables

- `secret_versions_config_file`: project configuration path. It defaults to the
  inventory-provided `project_config_path`.
- `secret_versions_gcp_project_id`: optional GCP project override.
- `secret_versions_only`: optional list of secret IDs or derived environment
  variable names. Entries that match no configured secret select no targets.
- `secret_versions_gcloud`: `gcloud` executable, default `gcloud`.
- `secret_versions_python`: controller Python used for AWS, default
  `ansible_playbook_python`.

## Usage

```bash
export DB_PASSWORD="$(openssl rand -hex 32)"
export GHCR_TOKEN="..."
export EXTERNAL_API_KEY="..."

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json" \
  --check

ansible-playbook oilscope.platform.upload_secret_versions \
  -i localhost, \
  -e secret_versions_config_file="$PWD/project-config.json"
```

Check mode validates the source values and all target containers without adding
versions. The real run passes payloads on stdin with no trailing newline, and
secret-bearing tasks use `no_log`. All targets are validated before uploading;
an external API failure during the upload phase can still leave a partial
rotation and should be retried after the cause is fixed.

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
