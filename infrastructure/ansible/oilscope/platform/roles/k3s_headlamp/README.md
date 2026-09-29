# K3s Headlamp role

Runs on the local Ansible controller and reconciles a pinned Headlamp Helm
release in its own `headlamp` namespace. The release uses the official chart
and image, with the image pinned by immutable multi-architecture digest.

Headlamp is deliberately private. Its Service is `ClusterIP`, and both Ingress
and Gateway API HTTPRoute creation are disabled. The chart's automatic
`cluster-admin` binding is disabled, as are Helm operations and the unsafe mode
that authenticates every visitor as the Headlamp Pod's service account.

The role creates a separate `headlamp-admin` ServiceAccount and explicitly
binds it to Kubernetes's built-in `cluster-admin` ClusterRole. This is suitable
for this private cluster, but its token grants unrestricted control of the
entire cluster. Generate a short-lived bearer token only when access is needed;
the token is not stored in Git, Google Secret Manager, Helm values, or a
persistent Kubernetes Secret.

Run the role as part of the controller-side add-on playbook from the repository
root while the SSH tunnel to the private K3s API is active:

```bash
ansible-playbook oilscope.platform.deploy_k3s_addons \
  -i localhost, \
  -e k3s_addons_config_file="$PWD/project-config.json"
```

Forward the internal Service to the controller's loopback address:

```bash
KUBECONFIG="$HOME/.kube/oilscope-dev.yaml" \
kubectl -n headlamp port-forward \
  service/headlamp 8088:80 \
  --address=127.0.0.1
```

Open `http://127.0.0.1:8088`, then generate and paste a temporary login token:

```bash
KUBECONFIG="$HOME/.kube/oilscope-dev.yaml" \
kubectl -n headlamp create token headlamp-admin --duration=8h
```

Treat the generated token like a root credential. Keep Headlamp bound only to
`127.0.0.1`, close the port-forward when finished, and use a short token
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
