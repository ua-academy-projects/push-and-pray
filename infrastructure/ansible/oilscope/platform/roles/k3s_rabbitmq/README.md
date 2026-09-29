# K3s RabbitMQ role

Runs on the local Ansible controller and reconciles a pinned, single-node
RabbitMQ Helm release in the application namespace. The CloudPirates chart uses
the repository-owned `infrastructure/kubernetes/values/rabbitmq.yaml` file and
the official RabbitMQ 4.3.6 image pinned by immutable digest.

The values file contains stable, non-secret configuration. The role overlays
the storage request from `k3s.data_services.rabbitmq.storage_gb`, the AMQP port
from `service_ports.rabbitmq`, and the `<name-prefix>-application` Secret name
from the project configuration. The chart maps the Secret's
`RABBITMQ_PASSWORD` and `RABBITMQ_ERLANG_COOKIE` keys without copying their
values into Helm release values.

RabbitMQ runs as one StatefulSet replica, uses an internal `ClusterIP` Service,
and requests a `ReadWriteOnce` volume from K3s's `local-path` storage class.
Kubernetes peer discovery is disabled because the deployment has one replica.
This is appropriate for the learning environment but is not a highly available
message broker.

Run the role as part of the controller-side add-on playbook from the repository
root while the SSH tunnel to the private K3s API is active. Helm and the Helm
Diff plugin must be installed on the controller.

```bash
ansible-playbook oilscope.platform.deploy_k3s_addons \
  -i localhost, \
  -e k3s_addons_config_file="$PWD/project-config.json"
```
