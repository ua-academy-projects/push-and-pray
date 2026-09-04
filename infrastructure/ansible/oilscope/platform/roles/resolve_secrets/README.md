# Resolve secrets role

Resolves only the secret_mappings assigned to the current VM. The neutral
inventory variables oilscope_cloud and oilscope_vm_key select the provider and
the exact vms entry; role names and string parsing are not used as identity.

GCP reads Secret Manager with the attached service account and metadata token.
AWS reads SSM SecureString parameters with the attached EC2 IAM role. Secret
values remain in no_log in-memory facts and are not written to disk.

Required variable:

- resolve_secrets_config_path: the same project configuration JSON Terraform
  reads.

Optional GCP overrides remain in defaults/main.yml. The result is
resolve_secrets_result, keyed by the application environment-variable names.
