module "network" {
  source = "./network"

  config = var.config
}

module "routing" {
  source = "./routing"

  config                = var.config
  vpc_id                = module.network.vpc_id
  management_subnet_id  = module.network.management_subnet_id
  workload_subnet_id    = module.network.workload_subnet_id
}

module "security_groups" {
  source = "./security_groups"

  config                       = var.config
  vpc_id                       = module.network.vpc_id
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

module "iam" {
  source = "./iam"

  config = var.config
}

module "addresses" {
  source = "./addresses"

  config = var.config
}

module "vm" {
  source = "./vm"

  config = var.config

  management_subnet_id   = module.network.management_subnet_id
  workload_subnet_id     = module.network.workload_subnet_id
  security_group_ids     = module.security_groups.security_group_ids
  instance_profile_names = module.iam.instance_profile_names
  allocation_ids          = module.addresses.allocation_ids
  public_ips              = module.addresses.public_ips
}

module "secrets" {
  source = "./secrets"

  config                      = var.config
  iam_role_names              = module.iam.iam_role_names
  aws_secret_version_managers = var.aws_secret_version_managers
}
