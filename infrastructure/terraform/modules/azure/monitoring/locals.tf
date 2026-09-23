locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  selected_vms    = var.selected_vms
}