# Resolve secrets role

Reads the current host's configured secrets from AWS Secrets Manager or Google
Secret Manager by using the VM's attached cloud identity. It runs on the
workload VM during deployment and returns an in-memory dictionary for the
application roles.

The dynamic inventory supplies `oilscope_vm_name` and `oilscope_cloud`. The role
uses those values to select the exact `vms` entry and its `secret_mappings`; it
does not infer authorization from Ansible groups or tags.

## Provider behavior

- AWS uses the instance profile and the standard boto3 credential chain. The
  role installs Ubuntu's `python3-boto3` package and requests each secret from
  the VM's effective region.
- GCP obtains an access token for the attached service account from the metadata
  server and requests each secret's `latest` version from the configured
  project.

Terraform grants each VM identity access only to the containers listed for that
VM. No operator credential is copied to a workload host.

## Variables

- `resolve_secrets_config_path`: project configuration path, defaulting to the
  inventory-provided `project_config_path`.
- `resolve_secrets_gcp_project_id`: optional GCP project override.
- `resolve_secrets_gcp_metadata_url`: GCP metadata token endpoint.
- `resolve_secrets_gcp_secretmanager_url`: GCP Secret Manager API base URL.
- `resolve_secrets_aws_python`: system Python used on AWS, default
  `/usr/bin/python3`.
- `resolve_secrets_aws_boto3_package`: Ubuntu package providing boto3, default
  `python3-boto3`.

## Output

`resolve_secrets_result` maps the application variable name—the key in
`secret_mappings`—to the retrieved value. A host without mappings receives an
empty dictionary. Tasks carrying tokens or values use `no_log`, and the role
does not intentionally persist values to disk.

See [docs/secrets.md](../../../../../../docs/secrets.md) for the complete model.

## License

GPL-2.0-or-later
