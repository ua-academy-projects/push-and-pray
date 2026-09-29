# K3s secrets role

Runs on the local Ansible controller, reads the configured K3s application
values from Google Secret Manager, and reconciles two Kubernetes Secrets in the
application namespace:

- `<name-prefix>-application` contains the PostgreSQL, RabbitMQ, Redis, and
  external API credentials.
- `<name-prefix>-registry` is a `kubernetes.io/dockerconfigjson` pull Secret for
  GHCR.

The role requires an authenticated `gcloud`, the `kubernetes.core` collection,
its Python dependencies, the local K3s kubeconfig, and an active SSH tunnel to
the private K3s API. Secret-bearing tasks use `no_log`, and values are held only
in Ansible memory and Kubernetes Secret objects. Secret Manager values are read
from the command's standard output; they are never written to controller files.

The playbook runs localhost modules with `ansible_playbook_python`, ensuring
that dependencies installed with `pipx runpip ansible-core` are imported from
Ansible's own isolated Python environment rather than the system interpreter.

The backing Secret Manager containers and their current versions must exist
before this role runs. Terraform creates the containers and
`oilscope.platform.upload_secret_versions` uploads the values.

Keep the bastion tunnel to the K3s API running, then invoke the role through its
playbook from the repository root:

```bash
ansible-playbook oilscope.platform.synchronize_k3s_secrets \
  -i localhost, \
  -e k3s_secrets_config_file="$PWD/project-config.json"
```

The default kubeconfig is
`~/.kube/oilscope-<environment>.yaml`. Override it with
`k3s_secrets_kubeconfig` when necessary. Updating the Secret objects does not
restart consumers; perform a controlled workload rollout after rotations.
