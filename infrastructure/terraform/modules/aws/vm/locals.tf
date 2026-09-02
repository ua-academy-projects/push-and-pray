locals {
  vms = {
    for name, vm in var.config.vms : name => merge(var.config.vm_defaults, vm)
    if try(vm.cloud, var.config.default_cloud) == "aws"
  }

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  subnet_ids_by_role = merge(
    { for vm in values(local.vms) : vm.role => var.workload_subnet_id },
    { bastion = var.management_subnet_id },
  )
}
