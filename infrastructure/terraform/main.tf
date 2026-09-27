module "gcp_apis" {
  source                  = "./modules/gcp/gcp-apis"
  config                  = local.config
  enable_managed_database = local.gcp_managed_database
}

module "iam" {
  source = "./modules/iam"
  config = local.config

  aws_secret_arns = concat(
    values(module.aws_secrets.secret_arns),
    compact([module.aws_rds.master_user_secret_arn]),
  )
  enable_aws_secret_access = local.aws_managed_database

  depends_on = [module.gcp_apis]
}

module "aws_network" {
  source                  = "./modules/aws/aws-network"
  config                  = local.config
  create_database_subnets = local.aws_managed_database
  database_subnet_cidrs   = var.aws_database_subnet_cidrs
  create_workload_nat_gateway = var.aws_enable_nat_gateway && length([
    for vm in values(local.config.vms) : vm
    if lookup(vm, "cloud", local.config.default_cloud) == "aws" &&
    vm.role != "bastion" &&
    vm.role != "ui" &&
    !vm.assign_public_ip
  ]) > 0
}

module "aws_security" {
  source        = "./modules/aws/aws-security"
  config        = local.config
  vpc_id        = module.aws_network.vpc_id
  database_mode = var.database_mode

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

module "aws_rds" {
  source = "./modules/aws/aws-rds"

  enabled             = local.aws_managed_database
  clients_share_cloud = length(local.database_client_clouds) == 1
  name_prefix         = "${local.config.name_prefix}-${local.config.environment}"
  vpc_id              = module.aws_network.vpc_id
  subnet_ids          = module.aws_network.database_subnet_ids
  allowed_security_group_ids = {
    for name, vm in local.config.vms : name => module.aws_security.security_group_ids[name]
    if lookup(vm, "cloud", local.config.default_cloud) == "aws" &&
    contains(["database", "history", "fetcher", "ui"], vm.role)
  }
  database_name             = var.database_name
  username                  = var.database_username
  port                      = local.config.service_ports.postgresql
  engine_version            = var.aws_rds_engine_version
  parameter_group_family    = var.aws_rds_parameter_group_family
  instance_class            = var.aws_rds_instance_class
  allocated_storage         = var.aws_rds_allocated_storage
  skip_final_snapshot       = var.aws_rds_skip_final_snapshot
  final_snapshot_identifier = var.aws_rds_final_snapshot_identifier
  deletion_protection       = var.aws_rds_deletion_protection
  tags                      = local.config.common_labels
}

module "aws_secrets" {
  source               = "./modules/aws/aws-secrets"
  config               = local.config
  generated_secret_ids = local.aws_managed_database ? [local.rabbitmq_secret_reference] : []
}

module "aws_vm" {
  source                = "./modules/aws/aws-vm"
  config                = local.config
  subnet_ids            = module.aws_network.subnet_ids
  security_group_ids    = module.aws_security.security_group_ids
  instance_profile_name = module.iam.aws_instance_profile_name
  database_runtime      = local.database_runtime
}

module "gcp_network" {
  source = "./modules/gcp/gcp-network"
  config = local.config

  depends_on = [module.gcp_apis]
}

module "gcp_security" {
  source        = "./modules/gcp/gcp-security"
  config        = local.config
  network_id    = module.gcp_network.network_id
  database_mode = var.database_mode

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

module "gcp_cloud_sql" {
  source = "./modules/gcp/gcp-cloud-sql"

  enabled             = local.gcp_managed_database
  clients_share_cloud = length(local.database_client_clouds) == 1
  project_id          = try(local.config.clouds.gcp.project_id, null)
  region              = try(local.config.clouds.gcp.regions[local.config.location.region], null)
  name_prefix         = "${local.config.name_prefix}-${local.config.environment}"
  network_id          = module.gcp_network.network_id
  database_version    = var.gcp_cloud_sql_database_version
  tier                = var.gcp_cloud_sql_tier
  disk_size           = var.gcp_cloud_sql_disk_size
  database_name       = var.database_name
  username            = var.database_username
  deletion_protection = var.gcp_cloud_sql_deletion_protection
  secret_accessor_members = {
    for name, email in module.iam.gcp_service_account_emails : name => "serviceAccount:${email}"
  }
  labels = local.config.common_labels

  depends_on = [module.gcp_apis]
}

module "gcp_vm" {
  source                 = "./modules/gcp/gcp-vm"
  config                 = local.config
  subnet_ids             = module.gcp_network.subnet_ids
  service_account_emails = module.iam.gcp_service_account_emails
  database_runtime       = local.database_runtime
}

module "gcp_secrets" {
  source                  = "./modules/gcp/gcp-secrets"
  config                  = local.config
  service_account_emails  = module.iam.gcp_service_account_emails
  secret_version_managers = var.secret_version_managers
  generated_secret_ids    = local.gcp_managed_database ? [local.rabbitmq_secret_reference] : []

  depends_on = [module.gcp_apis]
}

module "azure_network" {
  source = "./modules/azure/azure-network"

  for_each = local.azure_vms_by_region

  config      = local.config
  vms         = each.value
  region_key  = each.key
  location    = local.azure_region_locations[each.key]
  name_suffix = local.azure_region_name_suffixes[each.key]
  network     = local.azure_region_networks[each.key]

  create_database_subnet = local.azure_managed_database && each.key == local.azure_primary_region_key
  database_subnet_cidr   = var.azure_database_subnet_cidr
  create_workload_nat_gateway = var.azure_enable_nat_gateway && length([
    for vm in values(each.value) : vm
    if vm.role != "bastion" && vm.role != "ui" && !vm.assign_public_ip
  ]) > 0
}

module "azure_security" {
  source = "./modules/azure/azure-security"

  for_each = local.azure_vms_by_region

  config                       = local.config
  vms                          = each.value
  region_key                   = each.key
  name_suffix                  = local.azure_region_name_suffixes[each.key]
  network                      = local.azure_region_networks[each.key]
  management_source_cidrs      = local.azure_management_source_cidrs
  trusted_vnet_cidrs           = local.azure_trusted_vnet_cidrs
  resource_group_name          = module.azure_network[each.key].resource_group_name
  location                     = module.azure_network[each.key].location
  database_mode                = var.database_mode
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

module "azure_identity" {
  source = "./modules/azure/azure-identity"

  config              = local.config
  vms                 = local.azure_vms
  resource_group_name = try(module.azure_network[local.azure_primary_region_key].resource_group_name, null)
  location            = try(module.azure_network[local.azure_primary_region_key].location, null)
  generated_secret_ids = (
    local.azure_managed_database ? [local.rabbitmq_secret_reference] : []
  )
}

module "azure_postgresql" {
  source = "./modules/azure/azure-postgresql"

  enabled             = local.azure_managed_database
  clients_share_cloud = length(local.database_client_clouds) == 1
  name_prefix         = "${local.config.name_prefix}-${local.config.environment}"
  resource_group_name = try(module.azure_network[local.azure_primary_region_key].resource_group_name, null)
  location            = try(module.azure_network[local.azure_primary_region_key].location, null)
  zone                = try(local.azure_cloud_config.zones[local.azure_primary_region_key], null)
  virtual_network_ids = {
    for region_key, regional_network in module.azure_network :
    region_key => regional_network.virtual_network_id
  }
  delegated_subnet_id    = try(module.azure_network[local.azure_primary_region_key].database_subnet_id, null)
  identity_principal_ids = module.azure_identity.principal_ids
  database_version       = var.azure_postgresql_version
  sku_name               = var.azure_postgresql_sku_name
  storage_mb             = var.azure_postgresql_storage_mb
  backup_retention_days  = var.azure_postgresql_backup_retention_days
  database_name          = var.database_name
  username               = var.database_username
  tags                   = local.config.common_labels

  depends_on = [
    azurerm_virtual_network_peering.primary_to_region,
    azurerm_virtual_network_peering.region_to_primary,
  ]
}

module "azure_vm" {
  source = "./modules/azure/azure-vm"

  for_each = local.azure_vms_by_region

  config                     = local.config
  vms                        = each.value
  region_key                 = each.key
  name_suffix                = local.azure_region_name_suffixes[each.key]
  resource_group_name        = module.azure_network[each.key].resource_group_name
  location                   = module.azure_network[each.key].location
  subnet_ids                 = module.azure_network[each.key].subnet_ids
  network_security_group_ids = module.azure_security[each.key].network_security_group_ids
  identity_ids               = module.azure_identity.identity_ids
  identity_client_ids        = module.azure_identity.client_ids
  application_key_vault_uri  = module.azure_identity.application_key_vault_uri
  database_runtime           = local.database_runtime
}

module "aws-monitoring" {
  source             = "./modules/aws/aws-monitoring"
  instances          = module.aws_vm.vms
  name_prefix        = "${local.config.name_prefix}-${local.config.environment}"
  notification_email = var.alert_email
}

module "gcp-monitoring" {
  source = "./modules/gcp/gcp-monitoring"

  instance_keys = toset([
    for name, vm in local.config.vms : name
    if lookup(vm, "cloud", local.config.default_cloud) == "gcp"
  ])
  instances          = module.gcp_vm.vms
  name_prefix        = "${local.config.name_prefix}-${local.config.environment}"
  notification_email = var.alert_email

  depends_on = [module.gcp_apis]
}
