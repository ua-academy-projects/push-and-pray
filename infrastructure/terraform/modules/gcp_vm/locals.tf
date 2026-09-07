locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == "gcp"
  }

  labels = {
    for name, vm in local.vms : name => merge(
      var.config.common_labels,
      try(vm.labels, {}),
      {
        application = var.config.name_prefix
        environment = var.config.environment
        managed_by  = "terraform"
        role        = vm.role
      },
    )
  }
}
