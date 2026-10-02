locals {
  enabled = var.config.default_cloud == "aws"

  common_labels = {
    application = var.config.name_prefix
    environment = var.config.environment
    managed_by  = "terraform"
  }
}
