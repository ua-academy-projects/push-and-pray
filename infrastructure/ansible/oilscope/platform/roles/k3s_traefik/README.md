# K3s Traefik role

Runs on the local Ansible controller and customizes the K3s-managed Traefik
chart with a `HelmChartConfig`. It schedules one anti-affined Traefik replica
on every configured `k3s-agent` and changes the Traefik Service to
`externalTrafficPolicy: Local`.

The GCP external ingress load balancer and private Technitium records both
target the agent nodes. Keeping a local Traefik endpoint on every agent lets
Kubernetes preserve the original source address. This is required for the
private Headlamp IP allow-list to distinguish traffic forwarded by the
Tailscale subnet router from traffic received through the public load balancer.

The role is the first stage of `oilscope.platform.deploy_k3s_addons` and waits
for the K3s Helm controller to finish reconciling all replicas before the other
add-ons continue.
