locals {
  vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "gcp"
  }

  instances       = length(local.vms) > 0 ? { this = true } : {}
  roles           = toset([for vm in values(local.vms) : vm.role])
  workload_roles  = toset([for vm in values(local.vms) : vm.role if vm.role != "bastion"])
  bastion_vm      = try(one([for vm in values(local.vms) : vm if vm.role == "bastion"]), null)
  location        = try(var.config.locations[one(distinct([for vm in values(local.vms) : vm.location]))].gcp, null)
  region          = try(local.location.region, null)
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  network_tags = {
    for name, vm in local.vms : vm.role => "${local.resource_prefix}-${name}"
  }
}
