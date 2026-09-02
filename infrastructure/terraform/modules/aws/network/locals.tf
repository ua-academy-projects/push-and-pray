locals {
  vms = {
    for name, vm in var.config.vms : name => vm
    if try(vm.cloud, var.config.default_cloud) == "aws"
  }

  instances         = length(local.vms) > 0 ? { this = true } : {}
  roles             = toset([for vm in values(local.vms) : vm.role])
  bastion_vm        = try(one([for vm in values(local.vms) : vm if vm.role == "bastion"]), null)
  location          = try(var.config.locations[one(distinct([for vm in values(local.vms) : vm.location]))].aws, null)
  resource_prefix   = "${var.config.name_prefix}-${var.config.environment}"
  vm_names_by_role  = { for name, vm in local.vms : vm.role => name }
  workload_vm_roles = { for role, name in local.vm_names_by_role : role => name if role != "bastion" }
}
