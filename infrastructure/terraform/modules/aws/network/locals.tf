locals {
  vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "aws"
  }

  vms_by_location = {
    for location in distinct([for vm in values(local.vms) : vm.location]) : location => {
      for name, vm in local.vms : name => vm if vm.location == location
    }
  }
  locations = {
    for location in keys(local.vms_by_location) : location => var.config.locations[location].aws
  }

  primary_location = var.config.vms.bastion.location
  location_suffixes = {
    for location in keys(local.locations) :
    location => location == local.primary_location ? "" : "-${location}"
  }
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  bastion_vms_by_location = {
    for location, vms in local.vms_by_location :
    location => try(one([for vm in values(vms) : vm if vm.role == "bastion"]), null)
  }

  role_instances = merge({}, [
    for location, vms in local.vms_by_location : {
      for name, vm in vms :
      location == local.primary_location ? vm.role : "${location}/${vm.role}" => {
        location = location
        role     = vm.role
        vm_name  = name
      }
    }
  ]...)

  workload_role_instances = {
    for key, instance in local.role_instances : key => instance
    if instance.role != "bastion" && local.bastion_vms_by_location[instance.location] != null
  }

  bastion_cidrs = merge({}, [
    for location, vm in local.bastion_vms_by_location : vm == null ? {} : {
      for cidr in vm.allowed_cidrs :
      location == local.primary_location ? cidr : "${location}/${cidr}" => {
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
      location == local.primary_location ? tostring(port) : "${location}/${port}" => {
        location = location
        port     = port
      }
    } : {}
  ]...)
}
