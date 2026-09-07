locals {
  enabled = anytrue([
    for vm in values(var.config.vms) : try(vm.cloud, var.config.default_cloud) == "aws"
  ])

  resource_prefix   = "${var.config.name_prefix}-${var.config.environment}"
  availability_zone = var.config.region_map[var.config.region]["aws"].availability_zone

  ui_public_ports = [
    for port in var.config.network.ui_public_ports : tostring(port)
  ]
}
