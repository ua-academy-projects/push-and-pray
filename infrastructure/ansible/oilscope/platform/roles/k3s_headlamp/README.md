# K3s Headlamp role

Runs on the local Ansible controller and reconciles a pinned Headlamp Helm
release in its own `headlamp` namespace. The release uses the official chart
and image, with the image pinned by immutable multi-architecture digest.

Headlamp is deliberately private. Its chart-managed Service remains
`ClusterIP`, and the chart does not create an Ingress or Gateway API route.
Ansible creates a separate Traefik Ingress for the hostname configured at
`k3s.private_services.headlamp.hostname`. Technitium resolves that exact name to
the two K3s agents only for tailnet clients. A Traefik IP allow-list also accepts
only traffic forwarded by the Tailscale subnet router, so private DNS is not the
only access control. cert-manager obtains the certificate with the production
DNS-01 issuer; the private endpoint therefore has a publicly trusted
certificate without being published in public DNS.

The chart's automatic `cluster-admin` binding is disabled, as are Helm
operations and the unsafe mode that authenticates every visitor as the
Headlamp Pod's service account.

The role creates a separate `headlamp-admin` ServiceAccount and explicitly
binds it to Kubernetes's built-in `cluster-admin` ClusterRole. This is suitable
for this private cluster, but its token grants unrestricted control of the
entire cluster. Generate a short-lived bearer token only when access is needed;
the token is not stored in Git, Google Secret Manager, Helm values, or a
persistent Kubernetes Secret.

Run the role as part of the controller-side add-on playbook from the repository
root. The local kubeconfig reaches the private K3s API through the Tailscale
subnet route, so no SSH tunnel or Headlamp port-forward is needed:

```bash
ansible-playbook oilscope.platform.deploy_k3s_addons \
  -i localhost, \
  -e k3s_addons_config_file="$PWD/project-config.json"
```

Open the configured HTTPS hostname from a tailnet client, then generate and
paste a temporary login token:

```bash
KUBECONFIG="$HOME/.kube/oilscope-dev.yaml" \
kubectl -n headlamp create token headlamp-admin --duration=8h
```

Treat the generated token like a root credential and use a short token
duration. The Headlamp Pod's own ServiceAccount remains unprivileged; admin
access is granted only after logging in with the temporary token.

The administrator ServiceAccount and ClusterRoleBinding are managed by Ansible,
not by the Helm release. If Headlamp is removed permanently, remove both RBAC
resources as well:

```bash
KUBECONFIG="$HOME/.kube/oilscope-dev.yaml" \
kubectl delete clusterrolebinding headlamp-admin

KUBECONFIG="$HOME/.kube/oilscope-dev.yaml" \
kubectl -n headlamp delete serviceaccount headlamp-admin
```
