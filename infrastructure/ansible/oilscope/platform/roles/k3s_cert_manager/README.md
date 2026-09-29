# K3s cert-manager role

Runs on the local Ansible controller and reconciles the pinned cert-manager
Helm release through the private K3s API. The role uses the repository-owned
`infrastructure/kubernetes/values/cert-manager.yaml` file and defaults to the
`~/.kube/oilscope-<environment>.yaml` kubeconfig produced by the K3s playbook.
After the Helm release becomes ready, the role creates a cluster-scoped
`letsencrypt-production` ACME issuer, configures HTTP-01 challenges through
Traefik, and waits for the issuer to register successfully. The application
Ingress later requests the production certificate for
`k3s.application.hostname` when the workloads are ready to receive traffic.

The controller requires Helm, the Helm Diff plugin, the `kubernetes.core`
collection, the local K3s kubeconfig, and an active SSH tunnel to the private
API server. Helm Diff provides accurate idempotency checks for the OCI chart.
Run the role through its playbook from the repository root:

```bash
ansible-playbook oilscope.platform.deploy_k3s_addons \
  -i localhost, \
  -e k3s_addons_config_file="$PWD/project-config.json"
```

Override `k3s_cert_manager_values_file` or `k3s_cert_manager_kubeconfig` when
the project files or kubeconfig are stored in non-default locations. The chart
version is intentionally pinned in the role defaults so repeated runs do not
silently install a newer cert-manager release. The ACME account email comes
from `k3s.application.acme_email` in the project configuration. The issuer does
not request a certificate by itself; the application Ingress carries the
cert-manager annotation and causes cert-manager to create and renew the
production certificate.
