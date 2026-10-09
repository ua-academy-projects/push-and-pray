locals {
  resource_prefix     = "${var.config.name_prefix}-${var.config.environment}"
  az                  = var.config.regions[var.config.region]["aws"].zone
  ui_public_ports_str = [for port in var.config.network.ui_public_ports : tostring(port)]
  managed_db_enabled  = var.has_selected_vms && try(var.config.managed_db.enabled, false)

  eks_unsupported_zone_ids = ["use1-az3", "usw1-az2", "cac1-az3"]

  kubernetes_secondary_az = try([
    for idx, name in data.aws_availability_zones.available.names : name
    if name != local.az && !contains(local.eks_unsupported_zone_ids, data.aws_availability_zones.available.zone_ids[idx])
  ][0], null)
}
