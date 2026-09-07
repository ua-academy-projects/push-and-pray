module "aws_network" {
  source = "./modules/aws_network"

  count = contains(local.enabled_clouds, "aws") ? 1 : 0

  config = local.config
}

module "aws_basic" {
  source = "./modules/aws_basic"
  count  = contains(local.enabled_clouds, "aws") ? 1 : 0

  config = local.config
}

module "aws_vm" {
  source = "./modules/aws_vm"
  count  = contains(local.enabled_clouds, "aws") ? 1 : 0

  config                 = local.config
  network                = module.aws_network[0]
  instance_profile_names = module.aws_basic[0].instance_profile_names
}

module "gcp_basic" {
  source = "./modules/gcp_basic"
  count  = contains(local.enabled_clouds, "gcp") ? 1 : 0

  config = local.config
}

module "gcp_network" {
  source = "./modules/gcp_network"
  count  = contains(local.enabled_clouds, "gcp") ? 1 : 0

  config = local.config
}

module "gcp_vm" {
  source = "./modules/gcp_vm"
  count  = contains(local.enabled_clouds, "gcp") ? 1 : 0

  config                 = local.config
  subnets                = module.gcp_network[0]
  service_account_emails = module.gcp_basic[0].service_account_emails
}
