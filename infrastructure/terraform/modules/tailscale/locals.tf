locals {
  tailscale_enabled       = try(var.config.tailscale.enabled, false)
  tailscale_manage_policy = try(var.config.tailscale.manage_policy, true)
  tailscale_tag           = try(var.config.tailscale.tag, "tag:oilscope")
  tailscale_key_expiry    = try(var.config.tailscale.auth_key_expiry_seconds, 3600)

  tailscale_vms = {
    for name, vm in var.config.vms : name => merge(vm, {
      cloud = lookup(vm, "cloud", var.config.default_cloud)
    })
  }

  tailscale_active_clouds = toset([
    for vm in values(local.tailscale_vms) : vm.cloud
    if vm.role != "bastion"
  ])

  tailscale_k3s_servers_by_cloud = {
    for cloud in local.tailscale_active_clouds : cloud => sort([
      for name, vm in local.tailscale_vms : name
      if vm.cloud == cloud && vm.role == "k3s" && vm.k3s_role == "server"
    ])
  }

  tailscale_router_by_cloud = {
    for cloud, servers in local.tailscale_k3s_servers_by_cloud :
    cloud => try(servers[0], null)
  }

  tailscale_routes_by_cloud = {
    aws = [try(
      var.config.clouds.aws.network.vpc_cidr,
      var.config.network.vpc_cidr,
    )]
    gcp = [try(
      var.config.clouds.gcp.network.vpc_cidr,
      var.config.network.vpc_cidr,
    )]
    azure = var.azure_trusted_vnet_cidrs
  }

  tailscale_advertised_routes = sort(distinct(flatten([
    for cloud in local.tailscale_active_clouds :
    lookup(local.tailscale_routes_by_cloud, cloud, [])
  ])))

  tailscale_hostnames = {
    for name, vm in local.tailscale_vms : name => (
      vm.cloud == "azure" ? join("-", compact([
        "${var.config.name_prefix}-${var.config.environment}",
        lookup(vm, "azure_region", var.config.location.region) == var.config.location.region ? "" : lookup(vm, "azure_region", var.config.location.region),
        name,
      ])) : "${var.config.name_prefix}-${var.config.environment}-${name}"
    )
  }

  tailscale_vm_advertised_routes = {
    for name, vm in local.tailscale_vms : name => (
      try(local.tailscale_router_by_cloud[vm.cloud], null) == name ?
      local.tailscale_routes_by_cloud[vm.cloud] : []
    )
  }

}
