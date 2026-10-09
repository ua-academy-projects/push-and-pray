locals {
  cloud_network              = merge(var.config.network, try(var.config.network.cloud_cidrs.gcp, {}))
  managed_database_enabled   = var.config.database_mode == "managed" && var.config.default_cloud == "gcp"
  managed_kubernetes_enabled = try(var.config.kubernetes.mode, "self_managed") == "managed" && var.config.default_cloud == "gcp"

  workload_locations = setunion(toset([
    for vm in values(var.config.vms) : vm.location
    if try(vm.cloud, var.config.default_cloud) == "gcp" && vm.role != "bastion"
  ]), local.managed_database_enabled || local.managed_kubernetes_enabled ? toset([var.config.default_location]) : toset([]))

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
}
