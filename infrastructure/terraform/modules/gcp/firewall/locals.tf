locals {
  resource_prefix     = "${var.config.name_prefix}-${var.config.environment}"
  ui_public_ports_str = [for port in var.config.network.ui_public_ports : tostring(port)]
}
