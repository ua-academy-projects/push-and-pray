locals {
  cloud_name      = "azure"
  resource_prefix = join("-", compact(["${var.config.name_prefix}-${var.config.environment}", var.name_suffix]))
  enabled         = length(var.vms) > 0
  location        = var.location
  network         = var.network
  vnet_cidr       = try(local.network.vnet_cidr, local.network.vpc_cidr)
  common_tags = merge(var.config.common_labels, {
    application       = var.config.name_prefix
    environment       = var.config.environment
    managed_by        = "terraform"
    cloud             = local.cloud_name
    deployment_region = var.region_key
  })
}
