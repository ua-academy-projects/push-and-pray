# Traefik

Reconfigures the Traefik k3s installs on its own: one Traefik on every node
(`DaemonSet`), and `externalTrafficPolicy: Local` on its Service.

k3s installs Traefik from a `HelmChart` in `kube-system`; a `HelmChartConfig`
of the same name is how it accepts extra values for that chart. The helm
controller reinstalls Traefik with them, and the role waits until every node
runs a ready Traefik.

## Why

With the defaults - one Traefik pod, `externalTrafficPolicy: Cluster` - a
request reaching a node without Traefik is handed to the node that has one,
and kube-proxy replaces the client's address with the node's on the way.
Traefik then sees a node, not the client. That breaks every `ipAllowList`:
allowing the tailnet lets nobody in, allowing the cluster's ranges lets the
whole internet in, because a request to the public address arrives
translated too.

With a Traefik on every node and `Local`, each node answers what it receives
itself and the address survives. Tested on this cluster: through the tailnet
Traefik sees the laptop's tailnet address (`100.x`), from the internet the
real public address.

It also lets the UI answer on any node that is reachable, not only on the one
that happened to run Traefik.

## Reaching a node

Ports 80 and 443 are open only on nodes with a public address (the `ingress`
group). Internal names served by Traefik - Headlamp - therefore have to point
at such a node's internal address.

## License

GPL-2.0-or-later
