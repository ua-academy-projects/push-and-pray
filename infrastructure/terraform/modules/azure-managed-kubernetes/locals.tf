locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  cluster         = var.config.kubernetes.managed
  node_zones      = try(local.cluster.azure_zones, ["1", "2", "3"])
  ingress_zones   = ["1", "2", "3"]
  sku_tier        = try(local.cluster.azure_sku_tier, "Standard")
  tags = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )
}
