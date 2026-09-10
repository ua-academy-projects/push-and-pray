module "gcp_network" {
  source = "./modules/gcp/network"

  config = local.config
}

module "gcp_vm" {
  source = "./modules/gcp/vm"

  config  = local.config
  network = module.gcp_network
}

module "aws_network" {
  source = "./modules/aws/network"

  config = local.config
}

module "aws_vm" {
  source = "./modules/aws/vm"

  config  = local.config
  network = module.aws_network
}

module "gcp_secrets" {
  source = "./modules/gcp/secrets"

  config                  = local.config
  vms                     = module.gcp_vm.vms
  secret_version_managers = var.secret_version_managers
}

module "aws_secrets" {
  source = "./modules/aws/secrets"

  config = local.config
  vms    = module.aws_vm.vms
}

module "aws_monitoring" {
  source = "./modules/aws/monitoring"

  config = local.config
  vms    = module.aws_vm.vms
}

module "gcp_monitoring" {
  source = "./modules/gcp/monitoring"

  config = local.config
  vms    = module.gcp_vm.vms
}
