locals {
  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if coalesce(try(vm.cloud, null), var.config.cloud) == "aws"
  }

  has_selected_vms = length(local.selected_vms) > 0
}
