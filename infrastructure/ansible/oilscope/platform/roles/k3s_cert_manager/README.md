# K3s cert-manager role

Runs on the local Ansible controller and reconciles the pinned cert-manager
Helm release through the private K3s API. The role uses the repository-owned
`infrastructure/kubernetes/values/cert-manager.yaml` file and defaults to the
`~/.kube/oilscope-<environment>.yaml` kubeconfig produced by the K3s playbook.
After the Helm release becomes ready, the role creates two cluster-scoped ACME
issuers and waits for both to register successfully:

- `letsencrypt-production` uses HTTP-01 through Traefik for the public
  application hostname.
- `letsencrypt-production-dns01` uses the Cloudflare DNS API for private
  hostnames that are not published in public DNS.

The public application Ingress and private Headlamp Ingress request their
respective production certificates when those workloads are deployed.

The controller requires Helm, the Helm Diff plugin, the `kubernetes.core`
collection, the local K3s kubeconfig, and Tailscale connectivity to the private
API server. Helm Diff provides accurate idempotency checks for the OCI chart.
Before the first run, export a Cloudflare API token with `Zone:DNS:Edit` and
`Zone:Zone:Read` permissions restricted to the configured parent zone. Ansible
stores it in the cert-manager namespace; later runs can reuse the Secret
without the environment variable:

```bash
export CLOUDFLARE_API_TOKEN="$(cat)"
# Paste the token, then press Ctrl+D.

ansible-playbook oilscope.platform.deploy_k3s_addons \
  -i localhost, \
  -e k3s_addons_config_file="$PWD/project-config.json"

unset CLOUDFLARE_API_TOKEN
```

Run the same playbook normally after the Secret exists:

```bash
ansible-playbook oilscope.platform.deploy_k3s_addons \
  -i localhost, \
  -e k3s_addons_config_file="$PWD/project-config.json"
```

Override `k3s_cert_manager_values_file` or `k3s_cert_manager_kubeconfig` when
the project files or kubeconfig are stored in non-default locations. The chart
version is intentionally pinned in the role defaults so repeated runs do not
silently install a newer cert-manager release. The ACME account email comes
from `k3s.application.acme_email` in the project configuration. An issuer does
not request a certificate by itself. Each Ingress carries its issuer annotation
and causes cert-manager to create and renew its production certificate.
