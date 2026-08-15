locals {
  name_prefix = var.name_prefix

  common_labels = merge(
    {
      application = "oil-price-tracker"
      environment = var.environment
      managed_by  = "terraform"
    },
    var.common_labels
  )
}
