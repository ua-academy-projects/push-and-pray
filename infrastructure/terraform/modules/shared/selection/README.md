# Selection module

Answers the questions every cloud module asks of the cluster configuration, so
that every provider gets the same answer from the same code. It creates no
resources.

Given the whole configuration and the name of the asking cloud, it decides
which nodes that cloud hosts, whether it should build anything at all, which
ranges its bastion routes, which secrets it holds and what labels go on
everything.

The root module has already merged `node_defaults` into every node and resolved
each node's `cloud` against `default_cloud`, so this module reads `node.cloud`
directly and never falls back on its own.

## The active check

`nodes` holds cluster nodes only - the bastion each cloud needs is derived by
[modules/shared/bastion](../bastion/README.md) from the project-wide `bastion`
block. A cloud that hosts no node has nothing to run and nothing to reach, so
`is_active` is false and `nodes` comes back empty; the caller then builds
nothing at all on it, its bastion included. Moving the last node off a cloud
therefore tears that cloud down on the next apply.

## Routing

| Output | Holds | Used for |
| --- | --- | --- |
| `remote_cidrs` | `network_cidr` of every *other* cloud that hosts a node, and `tailscale.address_range` | routes pointing at this cloud's bastion; what the bastion forwards |
| `cluster_cidrs` | `network_cidr` of *every* cloud that hosts a node, and `tailscale.address_range` | sources the cluster ports admit |

The subnet routers run without SNAT, so a packet keeps its original source
across clouds and from the tailnet; that is why the tailnet range appears in
both.

## Validation

Cross-references live here because JSON Schema cannot express them: a label is
only valid against a sibling map in the same document.

| Check | Message names |
| --- | --- |
| the cloud declares a profile | `clouds.<cloud>` |
| the profile carries what the provider needs | `required_profile_fields` |
| every `size`, `image` and `boot_disk.type` label exists | the missing label |
| every value in every lookup map is one the provider accepts | each offending entry |
| every subnet lies inside `network_cidr` | - |

All of them are skipped when the cloud is inactive: nothing is built, so
nothing has to hold. Checks across clouds - the number of servers, overlapping
ranges, `default_cloud` - run once in the root module's `checks.tf`.

## Inputs

| Name | Description |
| --- | --- |
| `config` | The whole decoded configuration, nodes normalised by the root module |
| `cloud` | Which cloud is asking - the caller's own name for itself |
| `required_profile_fields` | Profile fields this provider cannot work without, e.g. `["project_id"]` |
| `profile_value_patterns` | Per lookup map, a regex every value must match on this provider |

## Outputs

| Name | Description |
| --- | --- |
| `profile` | This cloud's profile, or `null` when it declares none |
| `is_active` | Whether this cloud hosts any node |
| `nodes` | Nodes this cloud hosts; empty unless active |
| `hosts_server` | Whether a `k3s_server` node runs here |
| `remote_cidrs`, `cluster_cidrs` | See [Routing](#routing) |
| `secret_ids` | Secret containers this cloud holds - all of them when it hosts a server, none otherwise |
| `resource_prefix` | Prefix shared by every resource name |
| `common_labels` | Labels applied to every resource, including the `cloud` key |
| `cloud` | The cloud this instance answered for |

## License

GPL-2.0-or-later
