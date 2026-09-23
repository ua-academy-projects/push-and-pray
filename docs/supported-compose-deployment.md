# Supported Compose deployment

Terraform creates the network, virtual machines, a managed PostgreSQL database, and
the cloud secrets. Ansible then deploys RabbitMQ and Redis to the `infra` VM and one
application service to each workload VM.

The deployment uses these Compose templates from the `compose_project` role:

| Workload | Installed location | Runtime dependency |
| --- | --- | --- |
| RabbitMQ | `/opt/oilscope/rabbitmq/compose.yaml` | RabbitMQ password secret |
| Redis | `/opt/oilscope/redis/compose.yaml` | Redis password secret |
| History | `/opt/oilscope/app/compose.yaml` | PostgreSQL and RabbitMQ |
| Fetcher | `/opt/oilscope/app/compose.yaml` | RabbitMQ and OilPriceAPI |
| UI | `/opt/oilscope/app/compose.yaml` | Redis and History |
| Edge proxy | `/opt/oilscope/proxy/compose.yaml` | UI |

Application images are pulled from the configured GHCR repository with the immutable
commit SHA from `project-config.json`. RabbitMQ and Redis use the images configured in
`services.rabbitmq.image` and `services.redis.image`.

## Terraform-to-Ansible contract

After applying Terraform, export its non-secret service endpoints to a local file:

```bash
terraform -chdir=infrastructure/terraform \
  output -json service_endpoints \
  > .venv/oilscope-service-endpoints.json

export OILSCOPE_SERVICE_ENDPOINTS="$(realpath .venv/oilscope-service-endpoints.json)"
```

The output contains the selected cloud's PostgreSQL, RabbitMQ, and Redis host and port
data. Passwords remain in AWS Secrets Manager or Google Secret Manager and are resolved
on each VM through its runtime identity.

## Deployment order

Run database migrations against the managed database before starting History. Then run:

```bash
cd infrastructure/ansible
ansible-playbook -i inventory/oilscope.aws.yml playbooks/deploy_workloads.yml
```

Use `inventory/oilscope.gcp.yml` for GCP. The aggregate playbook deploys workloads in
this order: RabbitMQ and Redis, History, Fetcher, UI and its edge proxy.

The managed database is not a Compose workload. RabbitMQ and Redis are independent
Compose projects on the `infra` VM, so they have separate lifecycle and persistent
volumes.

## Runtime variables

The roles construct these values without writing secret values to the project JSON:

| Service | Variables |
| --- | --- |
| History | `DATABASE_URL`, `RABBITMQ_URL`, `RABBITMQ_QUEUE` |
| Fetcher | `RABBITMQ_URL`, `RABBITMQ_QUEUE`, `OILPRICEAPI_KEY` |
| UI | `REDIS_URL`, `HISTORY_SERVICE_URL` |
| RabbitMQ | `RABBITMQ_PASSWORD` |
| Redis | `REDIS_PASSWORD` |

Application containers use `restart: unless-stopped`. RabbitMQ and Redis store their
data in named Docker volumes. Cloud firewalls permit PostgreSQL only from History and
the `infra` VM, RabbitMQ only from Fetcher and History, and Redis only from UI.
