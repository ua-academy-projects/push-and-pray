locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  selected_vms = var.selected_vms

  cpu_threshold_ratio = try(var.config.monitoring.cpu_threshold_percent, 80) / 100
}