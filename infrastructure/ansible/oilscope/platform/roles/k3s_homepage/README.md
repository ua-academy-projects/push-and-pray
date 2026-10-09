# K3s Homepage role

Runs on the local Ansible controller and deploys a pinned Homepage container in
its own namespace. An Ansible-managed ConfigMap defines the dashboard settings,
widgets, and service cards for OilScope, Headlamp, and Technitium.
OilScope, Headlamp, and Technitium use server-side health checks and the `dot`
status style. The Technitium check uses the internal proxy Service; Terraform
allows K3s nodes to reach only its private administration port on the bastion.

The full-width boxed header shows aggregate cluster CPU and memory first. For a
self-managed cluster, it then shows the configured K3s servers followed by the
configured agents. For managed Kubernetes, it shows the provider-managed worker
nodes; managed control-plane machines are not Kubernetes Node objects and are
therefore not available to the widget. Homepage's native Kubernetes information
widget supplies the metrics, while shared responsive styling keeps the cards in
one equal-width row when space permits. A small custom script groups
self-managed node cards using the VM role tags because Homepage has no
node-order setting.

A full-width DuckDuckGo search field follows the metrics. The three application
cards share one row on desktop and collapse to one column on narrow screens.
The footer retains the manual revalidation control but hides the interactive
palette, theme selector, and version so the controller-managed appearance stays
consistent across self-managed and managed clusters. Kubernetes service
discovery is disabled.

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
