module "gcp_network" {
  source = "./modules/gcp/network"

  config           = local.config
  project_services = module.gcp_project.services
}

module "gcp_vm" {
  source = "./modules/gcp/vm"

  config               = local.config
  project_services     = module.gcp_project.services
  management_subnet_id = module.gcp_network.management_subnet_id
  workload_subnet_id   = module.gcp_network.workload_subnet_id
  network_tags_by_role = module.gcp_network.network_tags
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

  config                     = local.config
  key_name                   = module.aws_key_pair.key_name
  management_subnet_id       = module.aws_network.management_subnet_id
  workload_subnet_id         = module.aws_network.workload_subnet_id
  security_group_ids_by_role = module.aws_network.security_group_ids
}
