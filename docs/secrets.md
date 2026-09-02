# Secrets

Secret values never enter Terraform configuration, plans, or state. The
provider-neutral `secret_mappings` values are logical container IDs. Terraform
creates a container in the same cloud as each consuming workload and grants
that VM's runtime identity least-privilege read access.

- GCP uses Secret Manager and a dedicated VM service account.
- AWS uses Secrets Manager and a dedicated EC2 instance profile.

If the same logical secret is consumed in both clouds, Terraform creates one
container in each provider. Operators must upload the same value to both.
`terraform output secret_resource_names` reports provider-specific resource
identifiers; it never reports values.

## Uploading values

The existing `oilscope.platform.upload_secret_versions` play remains the safe
bulk uploader for GCP. It reads values from the operator environment, passes
them to `gcloud` on stdin, disables stdin newline insertion, and marks payload
tasks `no_log`.

For AWS, upload out of band with the normal AWS credential chain. Keep the
payload on stdin rather than in the command line:

```sh
printf '%s' "$SECRET_VALUE" | aws secretsmanager put-secret-value \
  --region eu-central-1 \
  --secret-id example-db-password \
  --secret-string file:///dev/stdin
```

The AWS operator needs `secretsmanager:PutSecretValue` on the target
containers. Terraform intentionally does not manage this operator permission,
because account identity administration is outside the project and no AWS
credentials belong in project config.

The GCP uploader's `secret_version_managers` Terraform variable likewise
accepts IAM members allowed to add versions without reading them. It defaults
to an empty list.

## Runtime resolution

`oilscope.platform.resolve_secrets` runs on each workload and selects behavior
from inventory's `oilscope_cloud`:

- GCP obtains a metadata-server token and calls Secret Manager's REST API.
- AWS uses boto3's instance-profile credential chain. `host_baseline` installs
  `python3-boto3` before resolution.

Returned values exist only as `no_log` Ansible facts for the deployment play.
They are not written to a project config or Terraform state.

## Rotation and recovery

Add a new version, restart consumers so they resolve `latest`, then destroy the
old version only after verification. If a value leaks, rotate it first; deleting
a commit or log does not make the exposed credential safe again.

Destroying infrastructure removes secret containers and their versions. Keep
an independent recovery copy before destroying an environment.
