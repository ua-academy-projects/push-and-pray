# VM deployment operations

The current cloud deployment is managed by the `oilscope.platform` Ansible
collection. Workload VMs do not run an `oilscope-deploy.service`; Terraform
uses cloud-init only to configure the bastion's SSH port during its first boot.

For the complete deployment sequence, see
[the supported Compose deployment guide](supported-compose-deployment.md).

## Check application containers

Connect to the required workload VM through the bastion and inspect its Compose
project:

```sh
sudo docker compose \
  --project-name petroscope \
  --file /opt/oilscope/app/compose.yaml \
  ps
```

The infrastructure VM contains `postgres` and the one-shot `migrate` service
in self-managed mode. In managed mode it contains RabbitMQ, Redis, the
migration job, and the GCP Cloud SQL Auth Proxy when applicable. Other workload
VMs contain their corresponding `history`, `fetcher`, or `ui` service.

On the UI VM, Traefik runs as a separate Compose project:

```sh
sudo docker compose \
  --project-name oilscope-proxy \
  --file /opt/oilscope/proxy/compose.yaml \
  ps
```

## Read logs

Application containers use Docker's default JSON logging. Read a workload's
local logs with:

```sh
sudo docker compose \
  --project-name petroscope \
  --file /opt/oilscope/app/compose.yaml \
  logs --follow
```

For Traefik logs on the UI VM:

```sh
sudo docker compose \
  --project-name oilscope-proxy \
  --file /opt/oilscope/proxy/compose.yaml \
  logs --follow traefik
```

The GCP Ops Agent and AWS CloudWatch Agent roles collect workload Docker log
files into the selected cloud's logging service.

## Redeploy

Rerun the complete deployment when shared dependencies or several services have
changed:

```sh
ansible-playbook oilscope.platform.deploy \
  -i infrastructure/ansible/inventory/oilscope.yml
```

For an isolated service change, rerun its playbook after confirming its
dependencies are healthy:

```sh
ansible-playbook oilscope.platform.fetcher \
  -i infrastructure/ansible/inventory/oilscope.yml
```

The Ansible roles pull the configured immutable image, reconcile the service,
and wait for its health check. No persistent secret environment file is stored
on the VM.

## Stop services

To stop the application service on a workload VM without deleting its data:

```sh
sudo docker compose \
  --project-name petroscope \
  --file /opt/oilscope/app/compose.yaml \
  stop
```

The infrastructure services' named volumes remain present. Rerunning the corresponding
Ansible playbook starts the service again.
