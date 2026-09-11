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

  selected_vms = var.selected_vms

  public_vms = { for name, vm in local.selected_vms : name => vm if vm.assign_public_ip }
}
