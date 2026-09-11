locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  selected_vms = var.selected_vms

  merged_common_tags = merge(
    {
      Application = var.config.name_prefix
      Environment = var.config.environment
      ManagedBy = "terraform"
    },
    var.config.common_labels
  )
}
