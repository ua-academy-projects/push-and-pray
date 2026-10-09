locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  workload_vms = {
    for name, vm in var.selected_vms : name => vm
    if length(try(vm.secret_mappings, {})) > 0
  }
}