# Terraform Infrastructure

Terraform configuration for the active OilScope Google Cloud foundation. The
current root module creates the network, a bastion VM and four workload VMs.
Application deployment remains intentionally deferred.

## Active scope

The root module composes three local modules:

- `modules/network`: custom-mode VPC, management and workload subnets, firewall
  rules, an optional explicit default route, Cloud Router and Cloud NAT;
- `modules/bastion`: bastion VM, static external address, dedicated service
  account, optional logging roles and hardened SSH configuration.
- `modules/vm`: generic workload compute with static addressing and boot disks,
  network tags, a service-account attachment and a Shielded VM baseline.

The root creates `infra`, `history`, `fetcher` and `ui` from one workload map.
It does not install Docker or start application services. The previous
application-aware compute and cloud-init implementation remains preserved
under `legacy/workload` and must not be applied independently.

## Prerequisites

- Terraform 1.15.1;
- Google Cloud CLI (`gcloud`);
- a GCP project with billing enabled;
- permission to manage Compute Engine networking, instances, service accounts
  and the bastion logging IAM grants;
- Compute Engine, IAM, Cloud Logging and Cloud Monitoring APIs enabled.

Enable the required APIs:

```bash
gcloud services enable \
  compute.googleapis.com \
  iam.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  --project PROJECT_ID
```

## Authentication

The Google provider uses Application Default Credentials:

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project PROJECT_ID
```

Prefer workload identity or another short-lived credential mechanism in CI
instead of a versioned service-account key.

## State strategy

This learning project uses Terraform's standard local backend. No backend
configuration file, GCS bucket, or `backend.hcl` is required. Terraform stores
state in `terraform.tfstate` in this directory and may create
`terraform.tfstate.backup` alongside it. Both are ignored by Git and must not
be committed or shared. Avoid running concurrent Terraform operations against
the same deployment.

## Configuration

Copy the example and replace its placeholder values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Active root inputs are:

| Input | Purpose |
| --- | --- |
| `project_id` | Target GCP project |
| `region`, `zone` | Resource location |
| `name_prefix`, `environment` | Resource names and labels |
| `common_labels` | Additional GCP labels |
| `management_subnet_cidr` | Bastion subnet; default `10.10.0.0/24` |
| `workload_subnet_cidr` | Application VM subnet; default `10.10.1.0/24` |
| `ssh_port` | Non-default bastion SSH port |
| `bastion_allowed_cidrs` | Approved office or VPN source ranges |
| `ssh_users` | Public SSH keys keyed by Linux username |
| `machine_types` | Workload VM sizes keyed by role |
| `internal_addresses` | Static workload IPs keyed by role |
| `boot_image_*`, `boot_disk_*` | Workload boot disk settings |

Before the first plan, manually set or confirm:

- `project_id`, `region` and a `zone` in that region;
- management and workload subnet CIDRs that do not overlap existing VPC, VPN,
  peering or on-premises routes;
- `bastion_allowed_cidrs`, preferably the operator's current public `/32` or a
  controlled VPN/office egress range. `0.0.0.0/0` is allowed for temporary
  testing, but is not recommended for a permanent deployment;
- `ssh_users`, containing Linux usernames and public OpenSSH keys only;
- workload internal addresses, which must remain inside the workload subnet and
  must not already be allocated.

No domain, application credential, database password, external message broker credential,
Redis credential or container image input is required by the current root.

## First plan

Run from this directory after preparing the ignored `terraform.tfvars` file:

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan -var-file=terraform.tfvars -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Review the complete saved plan before applying it. The apply creates only the
Terraform-managed infrastructure described below; it does not run Docker,
Compose or application deployment. For CI or isolated syntax checking, use
`terraform init -backend=false`.

## Outputs

The root exports network and subnet details, firewall and NAT information,
bastion access details, workload names and addresses, and workload service
accounts.

## Deferred application deployment

The workload VMs boot the selected Ubuntu image with no application cloud-init
metadata. Terraform does not install Docker, pull images, retrieve application
secrets, initialize PostgreSQL, start
external message broker or Redis, configure Traefik, run Compose, or apply database migrations.
Those actions require a separate reviewed integration stage.
