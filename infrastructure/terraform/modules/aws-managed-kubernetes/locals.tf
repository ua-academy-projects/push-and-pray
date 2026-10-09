locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  placement       = var.config.locations[var.config.default_location].aws
  cluster         = var.config.kubernetes.managed
  tags = merge(
    {
      Application = var.config.name_prefix
      Environment = var.config.environment
      ManagedBy   = "terraform"
    },
    { for key, value in var.config.common_labels : title(key) => value },
  )
}
