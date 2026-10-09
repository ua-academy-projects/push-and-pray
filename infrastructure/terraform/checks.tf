# Cross-references between parts of the configuration that no single cloud
# module sees whole. A precondition fails the plan before anything is built;
# a validation inside modules/shared/selection would run once per cloud and
# report the same mistake three times.

locals {
  server_count = length([
    for node in values(local.nodes) : node
    if node.role == "k3s_server"
  ])

  # Network ranges of every cloud that hosts a node, plus the tailnet. Each
  # bastion routes all of them, so no two may overlap.
  routed_ranges = merge(
    {
      for cloud in local.active_clouds :
      cloud => local.raw_config.clouds[cloud].network_cidr
      if can(local.raw_config.clouds[cloud].network_cidr)
    },
    { tailnet = local.raw_config.tailscale.address_range },
  )

  # Two ranges overlap exactly when one contains the other's first address.
  # Terraform has no cidrcontains, but masking an address with a range's
  # prefix length and comparing it to the range's own first address is the
  # same test.
  range_names = keys(local.routed_ranges)

  range_pairs = [
    for pair in setproduct(range(length(local.range_names)), range(length(local.range_names))) : {
      a = local.range_names[pair[0]]
      b = local.range_names[pair[1]]
    }
    if pair[0] < pair[1]
  ]

  overlapping_ranges = [
    for pair in local.range_pairs :
    "${pair.a} (${local.routed_ranges[pair.a]}) and ${pair.b} (${local.routed_ranges[pair.b]})"
    if(
      cidrhost("${cidrhost(local.routed_ranges[pair.b], 0)}/${split("/", local.routed_ranges[pair.a])[1]}", 0) == cidrhost(local.routed_ranges[pair.a], 0)
      || cidrhost("${cidrhost(local.routed_ranges[pair.a], 0)}/${split("/", local.routed_ranges[pair.b])[1]}", 0) == cidrhost(local.routed_ranges[pair.b], 0)
    )
  ]
}

resource "terraform_data" "config_checks" {
  lifecycle {
    precondition {
      condition     = can(local.raw_config.clouds[local.raw_config.default_cloud])
      error_message = "default_cloud is ${local.raw_config.default_cloud}, which clouds declares no profile for."
    }

    precondition {
      condition     = contains([1, 3], local.server_count)
      error_message = "The cluster needs one or three k3s_server nodes for an etcd quorum; the configuration has ${local.server_count}."
    }

    precondition {
      condition     = length(local.overlapping_ranges) == 0
      error_message = "Routed ranges overlap, so a bastion could not tell where to send a packet: ${join("; ", local.overlapping_ranges)}."
    }
  }
}
