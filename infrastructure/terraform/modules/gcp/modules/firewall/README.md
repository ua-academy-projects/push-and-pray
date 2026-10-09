# GCP firewall module

Says who may talk to whom inside one GCP deployment. Every rule is an ingress
rule matched by network tag; the [network module](../network/README.md) knows
nothing about ports.

## Scopes

| Scope | Network tag | Carried by |
| --- | --- | --- |
| `bastion` | `<prefix>-bastion` | The bastion, the cloud's Tailscale subnet router |
| `k3s_server` | `<prefix>-k3s-server` | Nodes with that role |
| `k3s_agent` | `<prefix>-k3s-agent` | Nodes with that role |
| `ingress` | `<prefix>-ingress` | Nodes with `assign_public_ip`, which answer for the application |

A network tag takes no underscore, so the role is rewritten for the tag and
kept as is for the key.

## Rules

| Rule | From | To | Allows |
| --- | --- | --- | --- |
| `allow-bastion-ssh` | `bastion.allowed_cidrs` | bastion | `bastion.ssh_port`/tcp |
| `allow-bastion-ssh-bootstrap` | `bastion.allowed_cidrs` | bastion | 22/tcp, only while `enable_bastion_ssh_bootstrap` |
| `allow-bastion-tailscale` | anywhere | bastion | `tailscale.port`/udp - direct WireGuard instead of DERP relays |
| `allow-bastion-forwarding` | this cloud's `network_cidr` | bastion | everything the bastion forwards to the other clouds and the tailnet |
| `allow-node-ssh` | bastion, `tailscale.address_range` | nodes | 22/tcp |
| `allow-<name>` | `cluster_cidrs` | the roles the entry names | one rule per `cluster.ports` entry |
| `allow-cluster-icmp` | `cluster_cidrs` | nodes, bastion | ICMP - path MTU discovery through the tunnel, and ping |
| `allow-ingress-web` | anywhere | ingress | `cluster.ingress.public_ports`/tcp |

`cluster_cidrs` is every cloud that hosts a node plus the tailnet. The subnet
routers never translate addresses, so traffic from another cloud or from a
laptop on the tailnet keeps its own source and is matched by range.

Nothing opens an application port such as PostgreSQL: inside the cluster,
traffic between pods on different nodes travels inside Flannel's VXLAN, which
the firewall sees only as `flannel-vxlan` between nodes. Separating services
from each other is a NetworkPolicy's job.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for rule and tag names |
| `network_id` | The VPC |
| `cluster` | `cluster.ports` and `cluster.ingress.public_ports` from the configuration |
| `tailscale` | `tailscale.port` and `tailscale.address_range` |
| `network_cidr` | This cloud's range |
| `cluster_cidrs` | From `modules/shared/selection` |
| `bastion` | `allowed_cidrs` and `ssh_port` |
| `enable_bastion_ssh_bootstrap` | Opens 22 on the bastion while Ansible moves SSH |

## Outputs

| Name | Description |
| --- | --- |
| `network_tags` | Tag by scope |
| `firewall_rule_names` | Rule name by purpose; cluster rules as `cluster/<name>` |
| `scopes` | The four scopes |

## License

GPL-2.0-or-later
