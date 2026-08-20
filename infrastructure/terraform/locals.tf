locals {
  config = jsondecode(file(var.project_config_path))

  resource_prefix = "${local.config.name_prefix}-${local.config.environment}"

  common_labels = {
    application = local.config.name_prefix
    environment = local.config.environment
    managed_by  = "terraform"
  }
}