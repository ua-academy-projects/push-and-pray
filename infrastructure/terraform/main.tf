module "gcp_network" {
  source = "./modules/gcp/network"

  config           = local.config
  project_services = module.gcp_project.services
}

module "gcp_vm" {
  source = "./modules/gcp/vm"

  config                   = local.config
  project_services         = module.gcp_project.services
  management_subnet_ids    = module.gcp_network.management_subnet_ids
  workload_subnet_ids      = module.gcp_network.workload_subnet_ids
  network_tags_by_location = module.gcp_network.network_tags
}

module "aws_network" {
  source = "./modules/aws/network"

  config = local.config
}

module "aws_key_pair" {
  source = "./modules/aws/key-pair"

  config = local.config
}

module "aws_vm" {
  source = "./modules/aws/vm"

  config                         = local.config
  key_names_by_location          = module.aws_key_pair.key_names_by_location
  management_subnet_ids          = module.aws_network.management_subnet_ids
  workload_subnet_ids            = module.aws_network.workload_subnet_ids
  security_group_ids_by_location = module.aws_network.security_group_ids
}
