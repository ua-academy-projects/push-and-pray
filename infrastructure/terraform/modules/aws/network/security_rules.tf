locals {
  bastion_cidrs = merge({}, [
    for location, vm in local.bastion_vms_by_location : vm == null ? {} : {
      for cidr in vm.allowed_cidrs :
      location == var.config.default_location ? cidr : "${location}/${cidr}" => {
        location = location
        cidr     = cidr
        ssh_port = vm.ssh_port
      }
    }
  ]...)

  bootstrap_bastion_cidrs = var.config.network.enable_bastion_ssh_bootstrap ? {
    for key, value in local.bastion_cidrs : key => value if value.ssh_port != 22
  } : {}

  ui_ports = merge({}, [
    for location, vms in local.vms_by_location :
    contains([for vm in values(vms) : vm.role], "ui") ? {
      for port in(try(var.config.cloudflare.enabled, false) ? [80, 443] : var.config.network.ui_public_ports) :
      location == var.config.default_location ? tostring(port) : "${location}/${port}" => {
        location = location
        port     = port
      }
    } : {}
  ]...)

  k3s_agents = {
    for key, instance in local.role_instances : key => instance
    if contains(["history", "fetcher", "ui"], instance.role) && contains(
      keys(local.role_instances),
      instance.location == var.config.default_location ? "database" : "${instance.location}/database"
    )
  }

  k3s_node_pairs = merge({}, [
    for target_key, target in local.role_instances : {
      for source_key, source in local.role_instances : "${target_key}:${source_key}" => {
        target_key = target_key
        source_key = source_key
        location   = target.location
      }
      if source_key != target_key && source.location == target.location && contains(["database", "history", "fetcher", "ui"], source.role)
    } if contains(["database", "history", "fetcher", "ui"], target.role)
  ]...)
}
