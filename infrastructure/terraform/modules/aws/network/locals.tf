locals {
    resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
    az = var.config.regions[var.config.region]["aws"].zone
    ui_public_ports_str = [for port in var.config.network.ui_public_ports : tostring(port)]
    managed_db_enabled = var.has_selected_vms && try(var.config.managed_db.enabled, false)
}
