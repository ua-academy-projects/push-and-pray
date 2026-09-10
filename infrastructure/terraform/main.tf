module "gcp" {
  source = "./modules/gcp"

  config                            = local.config
  enable_bastion_ssh_bootstrap      = var.enable_bastion_ssh_bootstrap
  secret_version_managers           = var.secret_version_managers
  managed_database_password         = var.managed_database_password
  managed_database_password_version = var.managed_database_password_version
}

module "aws" {
  source = "./modules/aws"

  config                       = local.config
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}
