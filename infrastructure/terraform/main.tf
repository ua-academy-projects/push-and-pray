module "gcp_vm" {
  source = "./modules/gcp"

  config                       = local.config
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

module "aws_vm" {
  source = "./modules/aws"

  config                       = local.config
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}
