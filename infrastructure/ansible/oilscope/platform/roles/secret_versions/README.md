# Secret versions role

Uploads operator-provided values to every provider that has a VM referencing
the secret. GCP uses Secret Manager versions; AWS uses SSM Parameter Store
Standard SecureString. A shared secret used in both clouds becomes two
provider-specific upload targets.

Values are read from controller environment variables derived from secret IDs:
uppercase with non-alphanumeric characters converted to underscores. Payloads
are sent on stdin and upload tasks use no_log.

Required variable:

- secret_versions_config_file: the same project configuration JSON Terraform
  reads.

Optional variables:

- secret_versions_only: secret IDs or derived variable names to upload.
- secret_versions_gcloud: gcloud executable, default gcloud.
- secret_versions_aws: AWS CLI executable, default aws.

Run the oilscope.platform.upload_secret_versions playbook with --check first,
then without --check after reviewing the provider-specific target list.
