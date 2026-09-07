module "gcp_network" {
  source = "./modules/gcp/network"

  config = local.config
}

module "gcp_vm" {
  source = "./modules/gcp/vm"

  config                   = local.config
  management_subnet_ids    = module.gcp_network.management_subnet_ids
  workload_subnet_ids      = module.gcp_network.workload_subnet_ids
  network_tags_by_location = module.gcp_network.network_tags
}

module "aws_network" {
  source = "./modules/aws/network"

  config = local.config
}

module "aws_vm" {
  source = "./modules/aws/vm"

  config                         = local.config
  management_subnet_ids          = module.aws_network.management_subnet_ids
  workload_subnet_ids            = module.aws_network.workload_subnet_ids
  security_group_ids_by_location = module.aws_network.security_group_ids
}

moved {
  from = module.aws_key_pair.aws_key_pair.bootstrap
  to   = module.aws_vm.aws_key_pair.bootstrap
}
