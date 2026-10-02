locals {
  enabled     = var.config.default_cloud == "aws"
  rds_enabled = local.enabled && var.config.managed_database
}
