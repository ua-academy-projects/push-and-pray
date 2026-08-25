# Terraform remote state operations

The application Terraform root stores state in a versioned Google Cloud
Storage bucket. State can contain sensitive infrastructure data, so access is
limited to the deployment identity and explicitly approved administrators.

## One-time state bucket creation

1. Create a dedicated deployment service account. Do not reuse a workload VM
   runtime identity.
2. Keep the application GCS backend block disabled for the first run, then use
   the application root's `buckets.tf` and `bucket-iam.tf` in a targeted plan
   and apply. The operator needs temporary project-level permission to create
   the bucket and set its IAM policy, and must be included in the authoritative
   bucket policy before apply.
3. Confirm the bucket has object versioning, uniform bucket-level access and
   public access prevention enabled.
4. Audit inherited project, folder and organization IAM. Bucket IAM cannot
   revoke an inherited Storage role.
5. Record only the bucket name and environment-specific prefix in the external
   project JSON. Do not create a `backend.hcl`, `.tfvars` or credentials file.
6. Remove temporary project-wide Storage Admin access after state migration.

The initial targeted operation is the only supported use of `-target` in this
workflow. It prevents application infrastructure from being created before the
shared backend exists:

```bash
terraform -chdir=infrastructure/terraform init
terraform -chdir=infrastructure/terraform plan \
  -target=google_storage_bucket.bucket_oil_state \
  -target=google_storage_bucket_iam_policy.bucket_oil_state \
  -out=state-bucket.tfplan
terraform -chdir=infrastructure/terraform apply state-bucket.tfplan
```

The default project configuration path is the ignored local file
`infrastructure/terraform/config/dev.json`. Override `project_config_path` when
the file is stored elsewhere. Public SSH keys are read from
`bastion.ssh_users` in that JSON. Never place a private key there.

Because the application root also manages the bucket resource and its
authoritative IAM policy, the deployment identity and approved recovery
administrators need `roles/storage.admin` on this bucket. The deployment
identity needs that role at project level only for the initial bucket creation;
remove that project-level grant after migration. Operators also need permission
to impersonate the deployment identity instead of downloading a long-lived
service-account key.

An organization IAM auditor must separately review inherited bindings. That
operator needs `resourcemanager.organizations.getIamPolicy` on the parent
organization (normally through an organization-level viewer or security audit
role). A bucket policy cannot inspect or revoke access inherited from a folder
or organization, so a successful bucket IAM apply is not evidence that no
inherited Storage access exists.

## Initial state migration

Before migration, stop all Terraform operations and save the current local
state somewhere encrypted and access-controlled:

```bash
terraform -chdir=infrastructure/terraform state pull > pre-gcs-migration.tfstate
```

Then initialize the backend with the bucket and prefix taken from the validated
external JSON:

```bash
uv run python scripts/terraform_init.py \
  --config infrastructure/terraform/config/dev.json \
  -migrate-state
```

The preflight validates the full JSON Schema and passes only the validated
bucket and prefix to Terraform. Review and accept Terraform's migration prompt.
Confirm `terraform state pull` works from a second authorized checkout before
removing the encrypted local backup. Never commit that backup.

## Confirm state locking

Use two authorized terminals against the same bucket and prefix:

1. In terminal A, start `terraform apply -refresh-only` and leave the operation
   at its approval prompt while it owns the lock.
2. In terminal B, run `terraform plan -lock-timeout=5s`.
3. Terminal B must fail with an error acquiring the state lock and identify the
   current lock holder.
4. Cancel terminal A cleanly, then repeat terminal B. It must acquire the lock
   and complete.

Routine automation should set a bounded `-lock-timeout`; it must never use
`-lock=false`. Use `terraform force-unlock LOCK_ID` only after confirming the
owning process no longer exists and recording the incident.

## Recovery and version restoration

First capture the currently readable state and stop concurrent operations:

```bash
terraform -chdir=infrastructure/terraform state pull > before-recovery.tfstate
gcloud storage ls --all-versions gs://STATE_BUCKET/STATE_PREFIX/default.tfstate
gcloud storage cp \
  'gs://STATE_BUCKET/STATE_PREFIX/default.tfstate#GENERATION' \
  recovered.tfstate
```

An approved administrator must compare the recovered state's `lineage`,
`serial` and resources with the current state before restoring it. Restore only
during a maintenance window, with no active lock, and keep the pre-recovery
copy until a fresh `terraform plan` has been reviewed. `terraform state push`
is a last-resort recovery action because it can overwrite newer state.

If Terraform writes `errored.tfstate` after a failed remote-state write, do not
rerun apply blindly. Preserve the file, stop other operators, inspect the
remote generation and follow Terraform's state-push guidance for that exact
failure.

## Concurrent operations

One bucket prefix represents one state and therefore one write stream. Use a
different prefix per environment, allow the GCS backend lock to serialize plan
and apply operations, and cancel superseded automation jobs. A lock error is a safety
signal, not a reason to disable locking.
