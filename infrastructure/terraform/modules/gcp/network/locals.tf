locals {
  workload_locations = toset([
    for vm in values(var.config.vms) : vm.location
    if try(vm.cloud, var.config.default_cloud) == "gcp" && vm.role != "bastion"
  ])

  vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "gcp" && contains(local.workload_locations, vm.location)
  }

  vms_by_location = {
    for location in distinct([for vm in values(local.vms) : vm.location]) : location => {
      for name, vm in local.vms : name => vm if vm.location == location
    }
  }

  locations = {
    for location in keys(local.vms_by_location) : location => var.config.locations[location].gcp
  }

  location_suffixes = {
    for location in keys(local.locations) :
    location => location == var.config.default_location ? "" : "-${location}"
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
