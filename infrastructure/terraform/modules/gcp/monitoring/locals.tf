locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if coalesce(try(vm.cloud, null), var.config.cloud) == "gcp"
  }

  cpu_threshold_ratio = try(var.config.monitoring.cpu_threshold_percent, 80) / 100
}