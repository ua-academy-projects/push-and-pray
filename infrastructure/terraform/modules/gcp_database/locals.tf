locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  settings        = var.config.services.database.gcp
}
