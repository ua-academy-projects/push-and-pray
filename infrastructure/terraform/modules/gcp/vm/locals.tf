locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  # GCP label keys must be lowercase and start with a lowercase letter.
  merged_common_labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )

  selected_vms = var.selected_vms

}
