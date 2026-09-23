locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  location        = var.config.regions[var.config.region]["azure"].region
}