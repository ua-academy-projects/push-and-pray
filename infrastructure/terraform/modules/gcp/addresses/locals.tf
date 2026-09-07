locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  merged_common_labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )

  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if coalesce(try(vm.cloud, null), var.config.cloud) == "gcp"
  }

  public_vms = { for name, vm in local.selected_vms : name => vm if vm.assign_public_ip }
}
