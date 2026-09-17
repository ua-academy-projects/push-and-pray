locals {
  cloud_name      = "aws"
  cloud_config    = lookup(var.config.clouds, local.cloud_name, {})
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  vms = {
    for name, vm in var.config.vms : name => vm
    if lookup(vm, "cloud", var.config.default_cloud) == local.cloud_name
  }
  common_tags = merge(var.config.common_labels, {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
    cloud       = local.cloud_name
  })
  zone    = try(local.cloud_config.zones[var.config.location.zone], null)
  network = merge(var.config.network, lookup(local.cloud_config, "network", {}))

  database_secondary_zone = var.create_database_subnets ? "${substr(local.zone, 0, length(local.zone) - 1)}${endswith(local.zone, "a") ? "b" : "a"}" : null
  database_availability_zones = var.create_database_subnets ? [
    local.zone,
    local.database_secondary_zone,
  ] : []
  database_subnets = {
    for index, cidr in var.database_subnet_cidrs : tostring(index) => {
      cidr              = cidr
      availability_zone = local.database_availability_zones[index]
    }
    if var.create_database_subnets && index < 2
  }
}
