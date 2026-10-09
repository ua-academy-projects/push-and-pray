locals {
  resource_prefix = "${var.config.name_prefix}-${var.config.environment}"
  placement       = var.config.locations[var.config.default_location].gcp
  cluster         = var.config.kubernetes.managed
  worker_zones    = slice(sort(data.google_compute_zones.available.names), 0, 2)
  labels = merge(
    {
      application = var.config.name_prefix
      environment = var.config.environment
      managed_by  = "terraform"
    },
    var.config.common_labels,
  )
}
