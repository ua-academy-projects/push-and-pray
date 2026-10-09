# AWS routing module

Sends traffic for the other clouds and for the tailnet to this cloud's
bastion, the Tailscale subnet router. The bastion carries it through its
tunnel; on the far side the other cloud's bastion hands it on.

It sits apart from the [network module](../network/README.md) because a route
needs the bastion as its next hop, and the bastion needs the network first.

## Resources

| Resource | Purpose |
| --- | --- |
| `aws_route.via_bastion` | One route per route table and destination, next hop the bastion's primary network interface |

Both route tables get the routes: a node with a public address sits in the
public subnet, the rest in the private one. The routers never translate source
addresses, so a reply to the tailnet has to find its way back by route as well
- which is why the tailnet range is among the destinations even with a single
cloud.

## Inputs

| Name | Description |
| --- | --- |
| `route_table_ids` | Route tables by purpose |
| `destinations` | Remote ranges: other clouds that host a node, and the tailnet |
| `bastion_network_interface_id` | Next hop; the instance must run with `source_dest_check` off |

## Outputs

| Name | Description |
| --- | --- |
| `route_ids` | Route ID by `<route table>/<destination>` |

## License

GPL-2.0-or-later
