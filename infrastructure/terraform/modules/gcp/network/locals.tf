locals {
  vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "gcp"
  }

  vms_by_location = {
    for location in distinct([for vm in values(local.vms) : vm.location]) : location => {
      for name, vm in local.vms : name => vm if vm.location == location
    }
  }

  locations = {
    for location in keys(local.vms_by_location) : location => var.config.locations[location].gcp
  }

  primary_location = var.config.vms.bastion.location
  location_suffixes = {
    for location in keys(local.locations) :
    location => location == local.primary_location ? "" : "-${location}"
  }
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  roles_by_location = {
    for location, vms in local.vms_by_location :
    location => toset([for vm in values(vms) : vm.role])
  }
  workload_roles_by_location = {
    for location, roles in local.roles_by_location :
    location => toset([for role in roles : role if role != "bastion"])
  }
  bastion_vms_by_location = {
    for location, vms in local.vms_by_location :
    location => try(one([for vm in values(vms) : vm if vm.role == "bastion"]), null)
  }
  network_tags = {
    for location, vms in local.vms_by_location : location => {
      for name, vm in vms : vm.role => "${local.resource_prefix}-${name}"
    }
  }
}
