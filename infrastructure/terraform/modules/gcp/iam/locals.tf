locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  selected_vms = {
    for name, vm in var.config.vms : name => vm
    if coalesce(try(vm.cloud, null), var.config.cloud) == "gcp"
  }

  merged_common_tags = merge(
    {
      Application = var.config.name_prefix
      Environment = var.config.environment
      ManagedBy = "terraform"
    },
    var.config.common_labels
  )
}
