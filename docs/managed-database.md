# Managed PostgreSQL and RabbitMQ

OilScope supports one deployment switch:

```hcl
database_mode = "self_hosted" # default
```

`self_hosted` preserves the existing PostgreSQL 18 and PGMQ deployment on the
database VM. `managed` creates private PostgreSQL in the cloud selected by the
VM whose role is `database`:

- Amazon RDS when that VM selects AWS;
- Cloud SQL when that VM selects GCP.

In managed mode the former database VM is retained. Ansible stops its
PostgreSQL container without deleting `postgres_data`, starts durable RabbitMQ,
and runs SQL migrations against the managed endpoint. Fetcher and History use
RabbitMQ; the UI and History continue to use the same PostgreSQL environment
variables as before.

## Safety and networking

- RDS is private, encrypted, Single-AZ, and placed in a DB subnet group that
  spans two AZs. TCP 5432 is accepted only from the application and migration
  runner security groups.
- Cloud SQL has no public IPv4 address and uses Private Services Access.
- RabbitMQ TCP 5672 is accepted only from Fetcher and History. Its management
  port 15672 is bound to loopback on the VM.
- AWS creates one NAT Gateway by default so private workload VMs can download
  packages and pull application images without public IPs. This resource has an hourly and traffic
  charge. Set `aws_enable_nat_gateway = false` only when another image
  delivery/egress path already exists.
- Managed migration runs skip only `004_create_pgmq_queue.sql`; all relational
  migrations remain common.
- Switching to managed mode never removes the old PostgreSQL Docker volume.

## Required secret values

Terraform generates the managed database password and RabbitMQ password. The
external OilPriceAPI value and, when required by a private registry, GHCR token
still come from the operator. Secret payloads must not be placed in tfvars,
project JSON, inventory, or Git.

The existing secret-version workflow can populate GCP application secrets. AWS
application secret containers use names such as:

```text
oilscope/dev/external-api-key
oilscope/dev/db-password
```

Managed RDS does not use `db-password`; it uses the RDS-managed Secrets Manager
secret. `db-password` remains required only for `self_hosted`.

## Offline validation

```bash
terraform -chdir=infrastructure/terraform fmt -check -recursive
terraform -chdir=infrastructure/terraform init -backend=false -input=false
terraform -chdir=infrastructure/terraform validate
terraform -chdir=infrastructure/terraform test

uv run ruff check .
uv run pytest
(cd services/fetcher && go test ./...)
```

## Reviewed plans

Run both plans against the real backend and credentials. Do not apply either
plan until replacements and deletions have been reviewed.

```bash
terraform -chdir=infrastructure/terraform plan \
  -var='database_mode=self_hosted' \
  -out=self-hosted.tfplan

terraform -chdir=infrastructure/terraform plan \
  -var='database_mode=managed' \
  -out=managed.tfplan
```

After applying the reviewed managed plan, rebuild and publish the changed
Fetcher and History images, update `registry.image_sha`, then deploy:

```bash
ansible-playbook oilscope.platform.deploy_workloads \
  -i infrastructure/ansible/inventory/oilscope.yml \
  -e project_config_path="$PWD/infrastructure/terraform/config/dev.json"
```

Verify from the former database VM:

```bash
nc -vz "$DATABASE_HOST" 5432
docker compose --project-name petroscope \
  --file /opt/oilscope/app/compose.yaml ps
```

Expected managed services are `rabbitmq` and the one-shot `migrate` container;
the local `postgres` container must be stopped. A second Terraform plan should
show no unexpected changes.
