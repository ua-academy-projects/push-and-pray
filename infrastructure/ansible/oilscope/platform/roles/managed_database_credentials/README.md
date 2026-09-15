# Managed database credentials role

Runs on the operator's machine, after `terraform apply` and before the
workloads are deployed, when `database.mode` is `managed`. It makes the
application role on the managed instance and the project's `POSTGRES_PASSWORD`
secret container agree on one password - without that password ever passing
through Terraform, where it would land in the plan and the state.

The two clouds offer different things, so the role does different things:

- **GCP.** Cloud SQL creates no application role by itself. The role takes the
  password from the environment variable `upload_secret_versions` reads for the
  container (for example `DB_PASSWORD` for `oilscope-dev-db-password`), or,
  when that is unset, from the container's latest version in Secret Manager,
  and creates or updates the role through the Cloud SQL Admin API with the
  password in the request body. The operator needs `roles/cloudsql.admin`.
- **AWS.** RDS generated the master password itself and keeps it in a secret of
  its own (`manage_master_user_password`). The role reads that secret and puts
  the value into the project's container, the one `resolve_secrets` and the
  Compose environment already read. The operator needs
  `rds:DescribeDBInstances` and `secretsmanager:GetSecretValue` on the
  RDS-managed secret, plus the `PutSecretValue` right every version manager
  already has.

The role does nothing in self-hosted mode. It is not idempotent in the strict
sense - a run always sets the password again - but setting an unchanged
password has no effect on anything.

## Required variables

- `managed_database_credentials_config_path`: path to the project
  configuration JSON.

## Optional variables

- `managed_database_credentials_project_id`: GCP project; falls back to
  `$GOOGLE_PROJECT`, then to `clouds.gcp.project_id`.
- `managed_database_credentials_region`: AWS region; falls back to
  `clouds.aws.region`.
- `managed_database_credentials_gcloud`, `managed_database_credentials_aws_cli`:
  the CLIs to call.

## Example

```bash
DB_PASSWORD='...' ansible-playbook oilscope.platform.managed_database_credentials \
  -e project_config_path=/absolute/path/project-config.json
```

## License

GPL-2.0-or-later
