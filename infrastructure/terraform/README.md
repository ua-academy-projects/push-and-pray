# Terraform Infrastructure

Terraform configuration for the Google Cloud foundation and network used by
OilScope. This root currently creates network resources only; application
compute and deployment resources are intentionally deferred.

## Prerequisites

- Terraform 1.15.x.
- Google Cloud CLI (`gcloud`).
- A GCP project with billing enabled.
- Permission to enable APIs and manage VPC networks, subnetworks, routers,
  NAT gateways, addresses, firewall rules, service accounts, Secret Manager
  secrets, and secret-level IAM policies.
- The Compute Engine, IAM, and Secret Manager APIs enabled in the target
  project.

Enable the required API:

```bash
gcloud services enable \
  compute.googleapis.com \
  iam.googleapis.com \
  secretmanager.googleapis.com \
  --project PROJECT_ID
```

## Authentication

The Google provider uses Application Default Credentials. Authenticate and set
the quota project before running Terraform:

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project PROJECT_ID
```

CI or other non-interactive environments should use workload identity or a
similarly short-lived credential mechanism rather than a versioned service
account key.

## State strategy

Shared environments use a GCS backend. The state bucket is a one-time
prerequisite and is deliberately not created by this Terraform root; otherwise
the root would need its own state before it could create its backend.

Choose a globally unique bucket name and bootstrap it once:

```bash
export TF_STATE_BUCKET="PROJECT_ID-oilscope-tfstate"

gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
  --project PROJECT_ID \
  --location us-east1 \
  --uniform-bucket-level-access

gcloud storage buckets update "gs://${TF_STATE_BUCKET}" \
  --versioning \
  --public-access-prevention
```

Copy the versioned backend example, replace `PROJECT_ID` in the local copy, and
keep that generated `backend.tf` uncommitted. It is ignored by Git so CI can
continue to initialize and validate the root without a real backend bucket:

```bash
cp backend.tf.example backend.tf
```

The resulting local `backend.tf` contains:

```hcl
terraform {
  backend "gcs" {
    bucket = "PROJECT_ID-oilscope-tfstate"
    prefix = "oilscope/dev/network"
  }
}
```

Initialize the root with the backend configuration:

```bash
terraform init
```

Object versioning provides recovery from accidental state overwrites. Access
to the bucket must be restricted to the people and automation that administer
this environment. CI validation uses `terraform init -backend=false`, so it
does not require access to the state bucket.

For isolated local validation only, initialize without a backend:

```bash
terraform init -backend=false
```

Do not apply shared infrastructure with local state.

## Configuration

Copy the example variable file and set the target project ID:

```bash
cp terraform.tfvars.example terraform.tfvars
```