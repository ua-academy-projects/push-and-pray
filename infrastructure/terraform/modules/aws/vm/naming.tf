locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  labels_by_vm = {
    for name, vm in local.vms : name => merge(
      var.config.common_labels,
      try(vm.labels, {}),
      { environment = var.config.environment, role = vm.role },
    )
  }
}
