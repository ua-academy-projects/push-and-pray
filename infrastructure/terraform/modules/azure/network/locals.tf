locals {
  resource_prefix    = "${var.config.name_prefix}-${var.config.environment}"
  managed_db_enabled = var.has_selected_vms && try(var.config.managed_db.enabled, false)
}
