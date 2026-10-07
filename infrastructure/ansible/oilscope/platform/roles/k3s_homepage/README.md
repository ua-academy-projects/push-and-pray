# K3s Homepage role

Runs on the local Ansible controller and deploys a pinned Homepage container in
its own namespace. An Ansible-managed ConfigMap defines the dashboard settings,
widgets, and service cards for OilScope, Headlamp, and Technitium.
OilScope, Headlamp, and Technitium use server-side health checks and the `dot`
status style. The Technitium check uses the internal proxy Service; Terraform
allows K3s nodes to reach only its private administration port on the bastion.

The full-width boxed header shows aggregate cluster CPU and memory first,
followed by the configured K3s servers and then the configured agents.
Homepage's native Kubernetes information widget supplies the metrics; a small
custom script groups its node cards using the VM role tags because Homepage has
no node-order setting. A
full-width DuckDuckGo search field follows the metrics. The standard search
provider icon and manual revalidation control remain available. Kubernetes
service discovery is disabled.

Homepage has a `ClusterIP` Service and a separately managed Traefik Ingress at
`k3s.private_services.homepage.hostname`. The same private access pattern as
Headlamp applies: Technitium split DNS resolves the name to both K3s agents,
cert-manager obtains a trusted certificate through DNS-01, and the Traefik IP
allow-list accepts only the Tailscale subnet router's private address.

The Pod receives a projected Kubernetes API token tied to a dedicated Service
Account. Its ClusterRole permits only `get` and `list` for core Nodes and
`metrics.k8s.io` Nodes. It cannot read Pods, Secrets, workloads, or ingress
resources.

Deploy it through the controller-side add-on playbook:

```bash
ansible-playbook oilscope.platform.deploy_k3s_addons \
  -i localhost, \
  -e k3s_addons_config_file="$PWD/project-config.json"
```
