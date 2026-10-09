# Azure routing module

Sends traffic for the other clouds and for the tailnet to this cloud's
bastion, the Tailscale subnet router. The bastion carries it through its
tunnel; on the far side the other cloud's bastion hands it on.

It sits apart from the [network module](../network/README.md) because a route
needs the bastion as its next hop, and the bastion needs the network first.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-via-bastion` | Route table with one route per destination, next hop `VirtualAppliance` at the bastion's address |
| `azurerm_subnet_route_table_association` | Attaches it to every subnet - workload and management |

The routers never translate source addresses, so a reply to the tailnet has to
find its way back by route as well - which is why the tailnet range is among
the destinations even with a single cloud.

The table is attached to the bastion's own subnet too. That was settled by
testing, not by documentation: with the workload subnet alone, a node in
Azure reached the other clouds, but connections opened from another cloud or
the tailnet stopped at the bastion. Neither Tailscale's nor Microsoft's
documentation says why; the likely reason - unconfirmed - is that the
`VirtualNetwork` service tag a subnet's security rules use includes the
prefixes of the route table attached to that subnet, so without it the
bastion's default outbound rules do not cover the ranges it forwards.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix`, `resource_group_name`, `location` | Where the table lives and how it is named |
| `destinations` | Remote ranges: other clouds that host a node, and the tailnet |
| `bastion_internal_ip` | Next hop; the bastion's interface must have IP forwarding on |
| `subnet_ids` | The subnets the table is attached to, by purpose |
| `tags` | Tags for the table |

## Outputs

| Name | Description |
| --- | --- |
| `route_table_id` | The route table |

## License

GPL-2.0-or-later
