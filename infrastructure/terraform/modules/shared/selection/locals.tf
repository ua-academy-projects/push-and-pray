locals {
  profile = try(var.config.clouds[var.cloud], null)

  # The root module has already merged node_defaults into every node and
  # resolved its cloud, so a node's cloud is always set here.
  nodes = {
    for name, node in var.config.nodes : name => node
    if node.cloud == var.cloud
  }

  is_active = length(local.nodes) > 0

  hosts_server = anytrue([for node in values(local.nodes) : node.role == "k3s_server"])

  active_clouds = sort(distinct([for node in values(var.config.nodes) : node.cloud]))

  # Ranges this cloud reaches through its own bastion: every other cloud that
  # hosts a node, and the tailnet.
  # distinct, so that two clouds mistakenly given the same range reach the
  # root module's overlap check instead of failing earlier on a duplicate key.
  remote_cidrs = distinct(concat(
    [
      for cloud in local.active_clouds : var.config.clouds[cloud].network_cidr
      if cloud != var.cloud
    ],
    [var.config.tailscale.address_range],
  ))

  # Where cluster traffic may come from: this cloud, the others, the tailnet.
  # The subnet routers never translate addresses, so a packet keeps the source
  # it started with.
  cluster_cidrs = distinct(concat(
    [for cloud in local.active_clouds : var.config.clouds[cloud].network_cidr],
    [var.config.tailscale.address_range],
  ))

  # Only k3s_server nodes read secrets, so a cloud without one holds none.
  secret_ids = local.hosts_server ? sort(distinct(values(var.config.secrets))) : []

  common_labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
    {
      cloud = var.cloud
    },
  )
}
