# OilScope cloud foundation bootstrap

`scripts/bootstrap-cloud.sh` prepares the additive resources required before an
isolated AWS or GCP Terraform stack can use remote state. It does not create
workload networks, VMs, databases, application secret containers, DNS records,
registries, or monitoring dashboards.

## Safe check

The default mode and `--check`/`--dry-run` are read-only and do not write local
generated files:

```bash
./scripts/bootstrap-cloud.sh \
  --provider aws \
  --environment dev \
  --deployment oilscope \
  --region eu-west-1 \
  --config configs/project-config.aws.json \
  --check
```

The command validates the provider, environment, deployment name, region, JSON
syntax, active identity, project/account, billing visibility, Terraform version,
state bucket, and foundation identities. A mismatch stops before mutation.

## Confirmed bootstrap

Only `--yes` enables mutations:

```bash
./scripts/bootstrap-cloud.sh \
  --provider gcp \
  --environment dev \
  --deployment oilscope \
  --region europe-west1 \
  --config configs/project-config.gcp.json \
  --yes
```

The script prints the active target before the first change. It is idempotent:
it checks buckets and identities before creation and uses additive IAM bindings.
It never disables billing, replaces a complete IAM policy, creates long-lived
access keys, or performs cleanup.

## Ownership

AWS foundation:

- encrypted, versioned, public-blocked S3 state bucket;
- native S3 state lockfile support;
- operator-assumable Terraform role;
- GitHub OIDC provider and repository-scoped CI publisher role;
- EC2-assumable runtime foundation role.

GCP foundation:

- required service APIs;
- versioned, uniform-access, public-prevented GCS state bucket;
- Terraform, CI publisher, and runtime service accounts;
- additive least-purpose project roles and bucket object access.

Workload Terraform continues to own workload resources. Runtime foundation
identities are not automatically substituted for the currently state-managed
per-VM identities; that migration requires a separately reviewed plan.

## Generated files

After a successful `--yes` run:

```text
.generated/<environment>/<provider>/<deployment>/
├── backend.hcl
├── foundation.json
├── deployment.json
└── inventory.json
```

The directory is ignored by Git. Files are created with mode `0600` and contain
identifiers only, never credentials or secret values. The script prints the
exact next commands for role activation/impersonation, `terraform init`, and
`terraform plan`. It never runs `terraform apply`.

`deployment.json` and `inventory.json` are written later by the authorised
deployment workflow after Terraform has produced the normalized deployment
output. The inventory uses only the public bastion endpoint and private workload
addresses and contains no secret values or private keys.

The isolated AWS and GCP roots declare `s3` and `gcs` backends respectively.
For local static validation initialise them without a backend:

```bash
terraform -chdir=infrastructure/terraform/stacks/aws init -backend=false
terraform -chdir=infrastructure/terraform/stacks/gcp init -backend=false
```

Do not migrate an existing local state during ordinary bootstrap. State
migration or import requires its own reviewed plan and explicit approval.

## Validation

```bash
bash -n scripts/bootstrap-cloud.sh
uv run pytest tests/test_bootstrap_cloud.py
shellcheck scripts/bootstrap-cloud.sh
```

The repository test uses mocked AWS CLI responses to prove that `--check` does
not issue known mutating calls or create generated files. `shellcheck` remains a
required CI/local dependency even if it is not installed on a particular
workstation.
