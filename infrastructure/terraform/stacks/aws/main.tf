locals {
  config = jsondecode(file(var.project_config_path))
}

provider "aws" {
  region = local.config.clouds.aws.locations[local.config.defaults.location_profile].region
}

module "aws" {
  source = "../../modules/aws"

  project_config_path          = var.project_config_path
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  database_password            = var.database_password
}

module "deployment_contract" {
  source = "../../modules/deployment-contract"

  project_config_path    = var.project_config_path
  provider_name          = "aws"
  nodes                  = module.aws.vms
  managed_database       = module.aws.managed_database
  managed_service_images = module.aws.managed_service_images
  monitoring             = module.aws.monitoring
}
