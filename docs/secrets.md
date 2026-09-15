# Secrets

Operator-provided secret values never enter project configuration. Terraform-generated
managed PostgreSQL, RabbitMQ, and Redis passwords are sensitive state values and are never
exposed through outputs. The
provider-neutral `application.secret_mappings` values are logical container IDs,
grouped by application role rather than VM key. Terraform
creates a container in the same cloud as each consuming workload and grants
that VM's runtime identity least-privilege read access.

- GCP uses Secret Manager and a dedicated VM service account.
- AWS uses Secrets Manager and a dedicated EC2 instance profile.

If the same operator-provided logical secret is consumed in both clouds, Terraform creates
one container in each provider. Generated Redis credentials receive the same Terraform-managed
value in every provider where the database or UI role consumes them.
`terraform output secret_resource_names` reports provider-specific resource
identifiers; it never reports values.

## Uploading values

In managed mode, Terraform creates the PostgreSQL, RabbitMQ, and Redis password versions
and the managed database-host version. Do not overwrite them with the operator uploader.
The GCP uploader automatically omits configured `POSTGRES_PASSWORD` and `REDIS_PASSWORD`
mappings in managed mode; it continues to upload operator-owned values such as
`GHCR_TOKEN` and `OILPRICEAPI_KEY`. In self-hosted mode those configured password mappings
remain operator-owned and are uploaded normally.

The existing `oilscope.platform.upload_secret_versions` play remains the safe
bulk uploader for GCP. It reads values from the operator environment, passes
them to `gcloud` on stdin, disables stdin newline insertion, and marks payload
tasks `no_log`.

For AWS, upload out of band with the normal AWS credential chain. Keep the
payload on stdin rather than in the command line:

```sh
printf '%s' "$SECRET_VALUE" | aws secretsmanager put-secret-value \
  --region eu-central-1 \
  --secret-id example-ghcr-token \
  --secret-string file:///dev/stdin
```

The AWS operator needs `secretsmanager:PutSecretValue` on the target
containers. Terraform intentionally does not manage this operator permission,
because account identity administration is outside the project and no AWS
credentials belong in project config.

The GCP uploader's `secret_version_managers` Terraform variable likewise
accepts IAM members allowed to add versions without reading them. This input
is required: persist the deployment's members in an ignored `*.auto.tfvars`
file so later plans retain the grants. Use an explicit empty list only when
the deployment should have no uploader grants. Omitting this input fails
instead of silently planning to revoke existing access.

## Runtime resolution

`oilscope.platform.resolve_secrets` runs on each workload and selects behavior
from inventory's `oilscope_cloud`:

- GCP obtains a metadata-server token and calls Secret Manager's REST API.
- AWS uses boto3's instance-profile credential chain. `host_baseline` installs
  `python3-boto3` before resolution.

Managed Fetcher resolves only RabbitMQ and application credentials, not PostgreSQL.
Managed UI resolves only Redis and registry credentials. History resolves RabbitMQ and
the managed PostgreSQL endpoint/password; the infra host resolves those plus Redis.

Returned values exist only as `no_log` Ansible facts for the deployment play.
They are not written to a project config or Terraform state.

## Rotation and recovery

Add a new version, restart consumers so they resolve `latest`, then destroy the
old version only after verification. If a value leaks, rotate it first; deleting
a commit or log does not make the exposed credential safe again.

Destroying infrastructure removes secret containers and their versions. Keep
an independent recovery copy before destroying an environment.
