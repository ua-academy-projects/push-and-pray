# VM deployment operations

Ansible installs one Compose project per workload. Application VMs use
`/opt/oilscope/app/compose.yaml`; the `infra` VM uses separate RabbitMQ and Redis
projects.

| Workload | Project directory | Project name |
| --- | --- | --- |
| History, Fetcher, UI | `/opt/oilscope/app` | `oilscope` |
| RabbitMQ | `/opt/oilscope/rabbitmq` | `oilscope-rabbitmq` |
| Redis | `/opt/oilscope/redis` | `oilscope-redis` |
| Edge proxy | `/opt/oilscope/proxy` | `oilscope-proxy` |

Inspect a project with:

```bash
cd /opt/oilscope/app
sudo docker compose --project-name oilscope --file compose.yaml ps
sudo docker compose --project-name oilscope --file compose.yaml logs --follow
```

For an infrastructure service, replace the directory and project name with the values
from the table. Runtime secrets are injected by Ansible when it starts or recreates a
container, so an interactive `docker compose up` requires the same environment values.

Use the Ansible playbooks for deployment and configuration changes:

```bash
ansible-playbook -i inventory/oilscope.aws.yml playbooks/deploy_workloads.yml
```

Use `inventory/oilscope.gcp.yml` for GCP. The managed PostgreSQL instance is operated
through RDS or Cloud SQL and does not have a Compose project on a VM.
