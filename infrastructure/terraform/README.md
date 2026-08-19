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

All non-secret, environment-specific configuration is supplied through a
single external JSON file — not through `terraform.tfvars`. The file is
**never committed to this repository**; keep it in a separate,
access-controlled location (e.g. a private configs directory, a secrets
manager, or a CI-provided temp file).

The full contract — every field, its type, and its allowed values — is
documented in
[`project-config.schema.json`](./project-config.schema.json).
It covers: project ID, environment, region/zone, naming and labels, network
and subnet CIDRs, bastion settings, and the full list of workload VM
definitions (machine type, image, disk, internal IP, public-IP policy,
network tags, automation role, application image tag, and Secret Manager
secret IDs — never secret values).

Two Terraform inputs remain outside the JSON contract:

| Input | Purpose |
| --- | --- |
| `project_config_path` | Absolute path to the environment-specific JSON configuration file |
| `ssh_users` | Public SSH keys keyed by Linux username — not environment-specific, supplied separately |
| `secret_version_managers` | IAM principals allowed to store new secret values. Identities only; never values |

Before the first plan, prepare a JSON file for your environment (e.g.
`dev.json`) following the schema, and confirm:

- `project_id`, `region` and a `zone` in that region;
- management and workload subnet CIDRs that do not overlap existing VPC, VPN,
  peering or on-premises routes;
- `bastion.bastion_allowed_cidrs`, preferably the operator's current public
  `/32` or a controlled VPN/office egress range. `0.0.0.0/0` is allowed for
  temporary testing, but is not recommended for a permanent deployment;
- each VM's `internal_ip`, which must remain inside the workload subnet and
  must not already be allocated.

Terraform validates the loaded configuration — required fields, supported
`config_version`, region/zone consistency, CIDR validity, unique internal
IPs, supported VM and automation roles, valid disk sizes/machine types, and
network tags — before any resource is created.

No domain, application credential, database password, external message
broker credential, Redis credential or container image input is required by
the current root.

## Secret Manager

The root creates one Secret Manager container per distinct entry in the
`secret_ids` field of the VM definitions, and grants each VM's service account
`roles/secretmanager.secretAccessor` on exactly the secrets it lists — per
secret, never at project scope. `secretmanager.googleapis.com` is enabled by
Terraform itself in `apis.tf`, with `disable_on_destroy = false` so a destroy
cannot break other workloads in the project.

Secret *values* are not managed here: there is no
`google_secret_manager_secret_version` resource and no input that accepts a
credential, so no payload reaches Terraform state. Values are added out of band
and consumed at service start.

See [`docs/secrets.md`](../../docs/secrets.md) for the access map, how to grant
and revoke, how to store a value, and the rotation procedure.

## First plan

Run from this directory, passing the absolute path to your environment's
JSON configuration file and your SSH users:

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan \
  -var="project_config_path=/absolute/path/to/dev.json" \
  -var='ssh_users={ alice = "ssh-ed25519 AAAA... alice@laptop" }' \
  -out=tfplan
terraform show tfplan
terraform apply tfplan
```

Switching environments means pointing at a different JSON file — no `.tf`
file is ever edited or generated. Review the complete saved plan before
applying it. The apply creates only the Terraform-managed infrastructure
described below; it does not run Docker, Compose or application deployment.
For CI or isolated syntax checking, use `terraform init -backend=false`.

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