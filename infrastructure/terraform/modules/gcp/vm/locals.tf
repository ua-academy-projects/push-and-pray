locals {
  vms = {
    for name, vm in var.config.vms : name => merge(var.config.vm_defaults, vm)
    if try(vm.cloud, var.config.default_cloud) == "gcp"
  }

  vms_by_location = {
    for location in distinct([for vm in values(local.vms) : vm.location]) : location => {
      for name, vm in local.vms : name => vm if vm.location == location
    }
  }

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  subnet_ids_by_location = {
    for location, vms in local.vms_by_location : location => merge(
      { for vm in values(vms) : vm.role => var.workload_subnet_ids[location] },
      { bastion = var.management_subnet_ids[location] },
    )
  }
}
