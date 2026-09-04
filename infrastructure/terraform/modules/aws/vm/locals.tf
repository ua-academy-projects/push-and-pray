locals {
  vms = {
    for name, vm in var.config.vms : name => merge({ assign_public_ip = false }, var.config.vm_defaults, vm)
    if try(vm.cloud, var.config.default_cloud) == "aws" && contains(keys(var.workload_subnet_ids), vm.location)
  }

  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  labels_by_vm = {
    for name, vm in local.vms : name => merge(
      var.config.common_labels,
      try(vm.labels, {}),
      { environment = var.config.environment, role = vm.role },
    )
  }
}
