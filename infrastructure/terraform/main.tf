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

module "gcp_database" {
  source = "./modules/gcp/database"

  config                     = local.config
  network_id                 = module.gcp_network.default_network_id
  private_service_connection = module.gcp_network.database_private_service_connection
}

module "gcp_monitoring" {
  source = "./modules/gcp/monitoring"

  config = local.config
  vms    = module.gcp_vm.vms
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

module "aws_database" {
  source = "./modules/aws/database"

  config                    = local.config
  vpc_id                    = module.aws_network.default_vpc_id
  subnet_ids                = module.aws_network.database_subnet_ids
  client_security_group_ids = module.aws_network.managed_database_client_security_group_ids
}

module "aws_monitoring" {
  source = "./modules/aws/monitoring"

  config = local.config
  vms    = module.aws_vm.vms
}

moved {
  from = module.aws_key_pair.aws_key_pair.bootstrap
  to   = module.aws_vm.aws_key_pair.bootstrap
}

module "azure_network" {
  source = "./modules/azure/network"

  config = local.config
}

module "azure_vm" {
  source = "./modules/azure/vm"

  config                     = local.config
  resource_group_names       = module.azure_network.resource_group_names
  management_subnet_ids      = module.azure_network.management_subnet_ids
  workload_subnet_ids        = module.azure_network.workload_subnet_ids
  network_security_group_ids = module.azure_network.network_security_group_ids
}

module "azure_database" {
  source = "./modules/azure/database"

  config                         = local.config
  resource_group_name            = module.azure_network.default_resource_group_name
  delegated_subnet_id            = module.azure_network.database_subnet_id
  private_dns_zone_id            = module.azure_network.database_private_dns_zone_id
  administrator_password         = var.azure_database_admin_password
  administrator_password_version = var.azure_database_admin_password_version
}

module "azure_monitoring" {
  source = "./modules/azure/monitoring"

  config               = local.config
  vms                  = module.azure_vm.vms
  resource_group_names = module.azure_network.resource_group_names
}
