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
      for port in var.config.network.ui_public_ports :
      location == var.config.default_location ? tostring(port) : "${location}/${port}" => {
        location = location
        port     = port
      }
    } : {}
  ]...)
}
