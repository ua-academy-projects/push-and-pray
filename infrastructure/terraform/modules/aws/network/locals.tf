locals {
  enabled     = var.config.default_cloud == "aws"
  rds_enabled = local.enabled && var.config.managed_database
  eks_enabled = local.enabled && try(var.config.managed_kubernetes, false)
  k3s_enabled = local.enabled && !try(var.config.managed_kubernetes, false)
}
