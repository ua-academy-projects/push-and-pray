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

  ingress_ports = {
    for item in flatten([
      for location, vms in local.vms_by_location : [
        for role in distinct([for vm in values(vms) : vm.role if vm.role != "bastion" && try(vm.assign_public_ip, false)]) : [
          for port in(try(var.config.cloudflare.enabled, false) ? [80, 443] : var.config.network.ingress_public_ports) : {
            key      = "${location}/${role}/${port}"
            location = location
            role     = role
            port     = port
          }
        ]
      ]
    ]) : item.key => item
  }

  k3s_nodes = {
    for key, instance in local.role_instances : key => instance
    if contains(["k3s_server", "k3s_agent"], instance.role) && contains(
      keys(local.role_instances),
      instance.location == var.config.default_location ? "k3s_server" : "${instance.location}/k3s_server"
    )
  }

  k3s_node_pairs = merge({}, [
    for target_key, target in local.role_instances : {
      for source_key, source in local.role_instances : "${target_key}:${source_key}" => {
        target_key = target_key
        source_key = source_key
        location   = target.location
      }
      if source.location == target.location && contains(["k3s_server", "k3s_agent"], source.role)
    } if contains(["k3s_server", "k3s_agent"], target.role)
  ]...)
}
