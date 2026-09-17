locals {
  config = jsondecode(file(var.project_config_path))
}

provider "google" {
  project = local.config.clouds.gcp.project_id
  region  = local.config.clouds.gcp.locations[local.config.defaults.location_profile].region
  zone    = local.config.clouds.gcp.locations[local.config.defaults.location_profile].zone
}

module "gcp" {
  source = "../../modules/gcp"

  project_config_path          = var.project_config_path
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  secret_version_managers      = var.secret_version_managers
  database_password            = var.database_password
}

module "deployment_contract" {
  source = "../../modules/deployment-contract"

  project_config_path    = var.project_config_path
  provider_name          = "gcp"
  nodes                  = module.gcp.vms
  managed_database       = module.gcp.managed_database
  managed_service_images = module.gcp.managed_service_images
  monitoring             = module.gcp.monitoring
}
