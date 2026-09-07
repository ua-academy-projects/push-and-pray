locals {
  workload_locations = toset([
    for vm in values(var.config.vms) : vm.location
    if try(vm.cloud, var.config.default_cloud) == "aws" && vm.role != "bastion"
  ])

  vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "aws" && contains(local.workload_locations, vm.location)
  }

  vms_by_location = {
    for location in distinct([for vm in values(local.vms) : vm.location]) : location => {
      for name, vm in local.vms : name => vm if vm.location == location
    }
  }

  locations = {
    for location in keys(local.vms_by_location) : location => var.config.locations[location].aws
  }

  bastion_vms_by_location = {
    for location, vms in local.vms_by_location :
    location => try(one([for vm in values(vms) : vm if vm.role == "bastion"]), null)
  }

  role_instances = merge({}, [
    for location, vms in local.vms_by_location : {
      for name, vm in vms :
      location == var.config.default_location ? vm.role : "${location}/${vm.role}" => {
        location = location
        role     = vm.role
      }
    }
  ]...)

  workload_role_instances = {
    for key, instance in local.role_instances : key => instance
    if instance.role != "bastion" && local.bastion_vms_by_location[instance.location] != null
  }
}
