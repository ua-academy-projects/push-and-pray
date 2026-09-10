locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"

  enabled = var.has_selected_vms && try(var.config.managed_db.enabled, false)

  db_name = try(var.config.managed_db.db_name, "oil_tracker")
  db_user = try(var.config.managed_db.db_user, "oil_tracker")
}