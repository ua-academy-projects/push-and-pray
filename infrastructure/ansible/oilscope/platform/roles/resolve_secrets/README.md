# Resolve secrets role

Resolves only the `secrets_by_role` mapping assigned to the current VM role.
The neutral inventory variables `oilscope_cloud` and `oilscope_vm_key` select
the provider and exact VM; its role selects the secret mapping.

GCP reads Secret Manager with the attached service account and metadata token.
AWS reads SSM SecureString parameters with the attached EC2 IAM role. Secret
values remain in no_log in-memory facts and are not written to disk.

Required variable:

- resolve_secrets_config_path: the same project configuration JSON Terraform
  reads.

Optional GCP overrides remain in defaults/main.yml. The result is
resolve_secrets_result, keyed by the application environment-variable names.
