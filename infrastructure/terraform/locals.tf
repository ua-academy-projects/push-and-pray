locals {
  raw_config = jsondecode(file(var.project_config_path))

  nodes = {
    for name, node in local.raw_config.nodes : name => merge(
      local.raw_config.node_defaults,
      node,
      { cloud = try(node.cloud, local.raw_config.default_cloud) },
    )
  }

  config = merge(local.raw_config, { nodes = local.nodes })

  active_clouds = sort(distinct([for node in values(local.nodes) : node.cloud]))
}
