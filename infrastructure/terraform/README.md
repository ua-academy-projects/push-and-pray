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

`terraform.tfvars` is ignored by Git. The deployment defaults are:

| Setting | Default |
|---|---|
| Region | `us-east1` |
| Zone | `us-east1-b` |
| VPC | `oilscope-vpc` |
| Subnet | `oilscope-subnet` |
| Subnet CIDR | `10.10.0.0/24` |
| Cloud Router | `oilscope-router` |
| Cloud NAT | `oilscope-nat` |

Reserved internal addresses:

| Future VM role | Address |
|---|---|
| Fetcher | `10.10.0.10` |
| History | `10.10.0.11` |
| Infra | `10.10.0.12` |
| UI | `10.10.0.14` |

## VM identities and secret access

Terraform creates a separate service account for each future VM. This keeps a
compromised service from reading credentials belonging only to another role.
No Editor, Owner, or project-wide Secret Manager role is granted.

Secret access is granted with `roles/secretmanager.secretAccessor` on each
individual secret:

| Secret | Infra | History | Fetcher | UI |
|---|:---:|:---:|:---:|:---:|
| PostgreSQL password | Yes | Yes | Yes | Yes |
| RabbitMQ username | Yes | Yes | No | No |
| RabbitMQ password | Yes | Yes | No | No |
| OilPriceAPI key | No | No | Yes | No |
| GHCR username | No | Yes | Yes | Yes |
| GHCR read token | No | Yes | Yes | Yes |

The PostgreSQL username and database name are fixed application configuration,
so only the password is stored as a secret. Redis is not used by the current
application code and no Redis secret is created.

Terraform creates secret containers and IAM bindings only. It deliberately
does not create secret versions or accept secret values as variables, keeping
real credentials out of configuration, plans, and Terraform state.

After `terraform apply`, add each value separately. For example, read a value
without echoing it and send it directly to `gcloud`:

```bash
read -r -s SECRET_VALUE
printf '%s' "${SECRET_VALUE}" | gcloud secrets versions add \
  oilscope-dev-db-password \
  --data-file=- \
  --project PROJECT_ID
unset SECRET_VALUE
```

Repeat this operation for the secret IDs returned by `terraform output
secret_ids`. Do not place the values in `terraform.tfvars`, `backend.tf`, shell
scripts, cloud-init, or instance metadata.

The History, Fetcher, and UI VMs will pull private application images from
GHCR. The stored GHCR token must have `read:packages` and access to the private
packages, and the stored username must identify the GitHub account that owns
or can use that token. The Infra VM pulls only public PostgreSQL and RabbitMQ
images and is intentionally denied GHCR credentials.

## UI external address

Terraform reserves one Premium-tier regional external IPv4 address in
`us-east1`. The later compute layer will attach it to the UI VM. DNS will point
to the `ui_external_ipv4_address` output, and Traefik on that VM will serve
ports `80` and `443`, manage Let's Encrypt certificates, and proxy internally
to UI port `8080`. Port `8080` is not exposed by the GCP firewall.

## Compute layout

Terraform creates four Ubuntu 24.04 LTS Compute Engine instances in
`us-east1-b`:

| VM role | Default machine type | Internal IP | External IP |
|---|---|---|---|
| Fetcher | `e2-micro` | `10.10.0.10` | None |
| History | `e2-micro` | `10.10.0.11` | None |
| Infra | `e2-small` | `10.10.0.12` | None |
| UI | `e2-micro` | `10.10.0.14` | Reserved static address |

Machine types are configurable through `machine_types`. Every VM uses its
reserved internal address, matching service account, and firewall network tag.
Only UI receives an `access_config`; the other VMs reach package repositories,
GHCR, and Google APIs through Cloud NAT.

The default boot image is the `ubuntu-2404-lts-amd64` family from
`ubuntu-os-cloud`. Boot images, disk sizes, and disk types are configurable.
Boot disks default to 20 GiB balanced persistent disks and are deleted with
their VM.

All instances enable Shielded VM Secure Boot, vTPM, and integrity monitoring.
No SSH key, password, startup script, or cloud-init content is stored in
instance metadata at this stage.

The subsequent cloud-init provisioning must create and enable a 1 GiB swap
file on every VM. Swap is intentionally deferred to cloud-init and does not
change the configurable machine-type defaults.

## Cloud-init provisioning

Each instance receives a role-specific rendering of the shared cloud-init
template as `user-data`. The rendered metadata contains Compose configuration,
secret resource names, image tags, and other non-sensitive deployment values;
it never contains a secret value.

On first boot, cloud-init:

1. Creates and persists a 1 GiB `/swapfile` if it is not already present.
2. Installs Docker Engine, Buildx, and the Docker Compose plugin from Docker's
   Ubuntu repository, then enables Docker.
3. Creates `/opt/oilscope/deployment`, `/opt/oilscope/runtime`, and the
   role-specific data directories.
4. Installs the matching deployment Compose file and shared provisioning
   scripts.
5. Enables and starts `oilscope-deployment.service`.

The systemd service waits for `network-online.target` and Docker, refreshes
`/opt/oilscope/runtime/.env` from Secret Manager with mode `0600`, logs in to
private GHCR where required, pulls images, and starts Compose with:

```text
docker compose up --detach --no-build --remove-orphans
```

The deployment unit uses bounded restart attempts so a registry or API outage
does not create an unlimited restart loop. Secrets are refreshed whenever the
unit starts or is reloaded. GHCR credentials are written only to a temporary
Docker configuration under `/run` and removed after the pull completes.

### Initial secret prerequisite

All required Secret Manager containers must have an enabled `latest` version
before the deployment service can start. On a brand-new project, first apply
the secret containers, service accounts, and secret-level IAM bindings; add
the secret versions out of band; then create the VMs with the full plan. If a
VM starts before versions are populated, add them and restart the VM or run:

```bash
sudo systemctl restart oilscope-deployment.service
```

### Infra persistent disk

Infra receives a separate 30 GiB balanced persistent disk. It is managed as an
independent Terraform resource and attached separately, so instance replacement
detaches and reattaches the disk instead of deleting it with the VM. A complete
`terraform destroy` still destroys the Terraform-managed disk.

The disk is initially blank. Cloud-init will later format it when necessary,
mount it, and create the PostgreSQL and RabbitMQ data directories. Terraform
does not write application data or run migrations.

Cloud-init locates the disk by its stable Compute Engine device name. It runs
`mkfs.ext4` only when `blkid` reports no existing filesystem, records the
filesystem UUID in `/etc/fstab`, and mounts it at `/opt/oilscope/data`. VM
recreation therefore reuses the existing filesystem and data.

## Domain and ACME configuration

Set these required, non-sensitive values in the ignored `terraform.tfvars`:

```hcl
app_domain = "oilscope.example.com"
acme_email = "admin@example.com"
```

Terraform does not manage DNS. After apply, obtain the UI address:

```bash
terraform output -raw ui_external_ipv4_address
```

Create an external DNS `A` record for `app_domain` pointing to that address.
Cloud-init puts `app_domain` and `acme_email` into the UI runtime environment
so Traefik can request the Let's Encrypt certificate.

## Provisioning operations and troubleshooting

Useful checks on a VM are:

```bash
cloud-init status --long
sudo systemctl status oilscope-deployment.service
sudo journalctl -u oilscope-deployment.service
sudo journalctl -u cloud-init -u cloud-final
sudo docker compose \
  --env-file /opt/oilscope/runtime/.env \
  --file /opt/oilscope/deployment/compose.ROLE.yaml \
  ps
```

Replace `ROLE` with `infra`, `history`, `fetcher`, or `ui`. To refresh secrets
and redeploy the pinned images without rebuilding:

```bash
sudo systemctl restart oilscope-deployment.service
```

The current repository does not provide a deployment migration artifact or a
cloud-supported migration command. Cloud-init does not invent one. Database
migrations remain a deployment prerequisite and must be applied through an
explicitly approved mechanism before application health is expected.

## Validate and deploy

Format and validate before planning:

```bash
terraform fmt -check -recursive
terraform init
terraform validate
```

Review and save the plan:

```bash
terraform plan -out=oilscope.tfplan
```

Apply exactly the reviewed plan:

```bash
terraform apply oilscope.tfplan
```

The plan file, local variable files, backend configuration, Terraform working
directory, and state files are ignored by Git.

## Created resources

This root creates:

- a custom-mode VPC with automatic subnet creation disabled;
- a regional `/24` subnet with Private Google Access enabled;
- a Cloud Router;
- Cloud NAT with automatically allocated external addresses, providing
  outbound Internet access to future private VMs without public IPs;
- four reserved regional internal addresses;
- four separate least-privilege VM service accounts;
- six Secret Manager secret containers with per-secret IAM access;
- one regional external IPv4 address reserved for the future UI VM;
- four Shielded Ubuntu Compute Engine instances using their reserved addresses,
  service accounts, and network tags;
- one independently managed persistent disk attached to Infra;
- narrowly scoped firewall rules for the planned service paths;
- public TCP `80` and `443` ingress targeting only the future UI VM network
  tag for Traefik.

The future compute resources must use the output network tags for these rules
to apply. Port `8080` is not opened publicly; Traefik will proxy to the UI over
the UI VM's internal Docker network.

## Intentionally out of scope

This root does not currently configure:

- a bastion or SSH ingress rule;
- real secret values or Secret Manager secret versions;
- VM disk formatting or mounts;
- database migration delivery or execution;
- a GCP load balancer;
- DNS records or TLS certificates.

Those resources belong to the subsequent compute and deployment work.
