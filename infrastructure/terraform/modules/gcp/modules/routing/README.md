# GCP routing module

Sends traffic for the other clouds and for the tailnet to this cloud's
bastion, the Tailscale subnet router. The bastion carries it through its
tunnel; on the far side the other cloud's bastion hands it on.

It sits apart from the [network module](../network/README.md) because a route
needs the bastion as its next hop, and the bastion needs the network first.

## Resources

| Resource | Purpose |
| --- | --- |
| `<prefix>-via-bastion-<range>` | One route per destination, next hop the bastion, applied only to the node tags |

The routers never translate source addresses, so a reply to the tailnet has to
find its way back by route as well - which is why the tailnet range is among
the destinations even with a single cloud.

## Inputs

| Name | Description |
| --- | --- |
| `resource_prefix` | Prefix for the route names |
| `network_id` | The VPC |
| `destinations` | Remote ranges: other clouds that host a node, and the tailnet |
| `bastion_self_link` | Next hop; the instance must have `can_ip_forward` |
| `node_tags` | Instances the routes apply to |

## Outputs

| Name | Description |
| --- | --- |
| `route_names` | Route name by destination |

## License

GPL-2.0-or-later
