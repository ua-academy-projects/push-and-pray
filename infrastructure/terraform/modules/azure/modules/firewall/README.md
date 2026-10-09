# Azure firewall module

Says who may talk to whom inside one Azure deployment. A scope is an
application security group a network interface joins; every rule lives in one
network security group attached to every subnet. The
[network module](../network/README.md) knows nothing about ports.

## Scopes

| Scope | Application security group | Joined by |
| --- | --- | --- |
| `bastion` | `<prefix>-bastion` | The bastion, the cloud's Tailscale subnet router |
| `k3s_server` | `<prefix>-k3s-server` | Nodes with that role |
| `k3s_agent` | `<prefix>-k3s-agent` | Nodes with that role |
| `ingress` | `<prefix>-ingress` | Nodes with `assign_public_ip`, which answer for the application |

Azure allows everything inside a virtual network by default; `deny-vnet-inbound`
at priority 4000 closes it, so the rules below are the whole contract.

## Rules

| Rule | From | To | Allows |
| --- | --- | --- | --- |
| `allow-bastion-ssh` | `bastion.allowed_cidrs` | bastion | `bastion.ssh_port`/tcp |
| `allow-bastion-ssh-bootstrap` | `bastion.allowed_cidrs` | bastion | 22/tcp, only while `enable_bastion_ssh_bootstrap` |
| `allow-bastion-tailscale` | anywhere | bastion | `tailscale.port`/udp - direct WireGuard instead of DERP relays |
| `allow-bastion-forwarding` | this cloud's `network_cidr` | `remote_cidrs` | everything the bastion forwards - matched by destination range, because a forwarded packet is not addressed to the bastion's own interface |
| `allow-node-ssh-bastion`, `allow-node-ssh-tailnet` | bastion group, `tailscale.address_range` | nodes | 22/tcp - a rule takes groups or prefixes as its source, never both |
| `allow-<name>` | `cluster_cidrs` | the roles the entry names | one rule per `cluster.ports` entry, priority 200 onwards, ten apart |
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
| `resource_prefix` | Prefix for group names |
| `resource_group_name`, `location` | Where the groups live |
| `subnet_ids` | Subnets the security group is attached to |
| `cluster` | `cluster.ports` and `cluster.ingress.public_ports` from the configuration |
| `tailscale` | `tailscale.port` and `tailscale.address_range` |
| `network_cidr` | This cloud's range |
| `cluster_cidrs`, `remote_cidrs` | From `modules/shared/selection` |
| `bastion` | `allowed_cidrs` and `ssh_port` |
| `enable_bastion_ssh_bootstrap` | Opens 22 on the bastion while Ansible moves SSH |
| `tags` | Tags for every group |

## Outputs

| Name | Description |
| --- | --- |
| `application_security_group_ids` | By scope |
| `network_security_group_id`, `network_security_group_name` | The one security group |
| `scopes` | The four scopes |

## License

GPL-2.0-or-later
