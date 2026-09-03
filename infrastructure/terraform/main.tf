module "gcp" {
  source = "./modules/gcp"

  config                       = local.config
  cloud_key                    = "gcp"
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  secret_version_managers      = var.secret_version_managers
}

module "aws" {
  source = "./modules/aws"

  config                       = local.config
  cloud_key                    = "aws"
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}
