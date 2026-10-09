# AWS firewall module

Says who may talk to whom inside one AWS deployment. A scope is a security
group an instance joins; the [network module](../network/README.md) knows
nothing about ports. Every group allows all egress.

## Scopes

| Scope | Security group | Joined by |
| --- | --- | --- |
| `bastion` | `<prefix>-bastion` | The bastion, the cloud's Tailscale subnet router |
| `k3s_server` | `<prefix>-k3s-server` | Nodes with that role |
| `k3s_agent` | `<prefix>-k3s-agent` | Nodes with that role |
| `ingress` | `<prefix>-ingress` | Nodes with `assign_public_ip`, which answer for the application |

A security group rule names one port and one source, so a `cluster.ports`
entry becomes one rule per role, port and source range.

## Rules

| Rule | From | To | Allows |
| --- | --- | --- | --- |
| `bastion_ssh` | `bastion.allowed_cidrs` | bastion | `bastion.ssh_port`/tcp |
| `bastion_ssh_bootstrap` | `bastion.allowed_cidrs` | bastion | 22/tcp, only while `enable_bastion_ssh_bootstrap` |
| `bastion_tailscale` | anywhere | bastion | `tailscale.port`/udp - direct WireGuard instead of DERP relays |
| `bastion_forwarding` | this cloud's `network_cidr` | bastion | everything the bastion forwards to the other clouds and the tailnet |
| `node_ssh_bastion`, `node_ssh_tailnet` | bastion group, `tailscale.address_range` | nodes | 22/tcp |
| `cluster` | `cluster_cidrs` | the roles the entry names | one rule per role, port and source range |
| `cluster_icmp` | `cluster_cidrs` | nodes, bastion | ICMP - path MTU discovery through the tunnel, and ping |
| `ingress_web` | anywhere | ingress | `cluster.ingress.public_ports`/tcp |

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
| `vpc_id` | The VPC |
| `cluster` | `cluster.ports` and `cluster.ingress.public_ports` from the configuration |
| `tailscale` | `tailscale.port` and `tailscale.address_range` |
| `network_cidr` | This cloud's range |
| `cluster_cidrs` | From `modules/shared/selection` |
| `bastion` | `allowed_cidrs` and `ssh_port` |
| `enable_bastion_ssh_bootstrap` | Opens 22 on the bastion while Ansible moves SSH |
| `tags` | Tags for every group and rule |

## Outputs

| Name | Description |
| --- | --- |
| `security_group_ids`, `security_group_names`, `security_group_arns` | By scope |
| `scopes` | The four scopes |

## License

GPL-2.0-or-later
