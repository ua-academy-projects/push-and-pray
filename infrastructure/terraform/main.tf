module "gcp_apis" {
  source                  = "./modules/gcp-apis"
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
  source                  = "./modules/aws-network"
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
  source        = "./modules/aws-security"
  config        = local.config
  vpc_id        = module.aws_network.vpc_id
  database_mode = var.database_mode

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

module "aws_rds" {
  source = "./modules/aws-rds"

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
  source               = "./modules/aws-secrets"
  config               = local.config
  generated_secret_ids = local.aws_managed_database ? [local.rabbitmq_secret_reference] : []
}

module "aws_vm" {
  source                = "./modules/aws-vm"
  config                = local.config
  subnet_ids            = module.aws_network.subnet_ids
  security_group_ids    = module.aws_security.security_group_ids
  instance_profile_name = module.iam.aws_instance_profile_name
  database_runtime      = local.database_runtime
}

module "gcp_network" {
  source = "./modules/gcp-network"
  config = local.config

  depends_on = [module.gcp_apis]
}

module "gcp_security" {
  source        = "./modules/gcp-security"
  config        = local.config
  network_id    = module.gcp_network.network_id
  database_mode = var.database_mode

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
}

module "gcp_cloud_sql" {
  source = "./modules/gcp-cloud-sql"

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
  source                 = "./modules/gcp-vm"
  config                 = local.config
  subnet_ids             = module.gcp_network.subnet_ids
  service_account_emails = module.iam.gcp_service_account_emails
  database_runtime       = local.database_runtime
}

module "gcp_secrets" {
  source                  = "./modules/gcp-secrets"
  config                  = local.config
  service_account_emails  = module.iam.gcp_service_account_emails
  secret_version_managers = var.secret_version_managers
  generated_secret_ids    = local.gcp_managed_database ? [local.rabbitmq_secret_reference] : []

  depends_on = [module.gcp_apis]
}

module "aws-monitoring" {
  source             = "./modules/aws-monitoring"
  instances          = module.aws_vm.vms
  name_prefix        = "${local.config.name_prefix}-${local.config.environment}"
  notification_email = var.alert_email
}

module "gcp-monitoring" {
  source = "./modules/gcp-monitoring"

  instance_keys = toset([
    for name, vm in local.config.vms : name
    if lookup(vm, "cloud", local.config.default_cloud) == "gcp"
  ])
  instances          = module.gcp_vm.vms
  name_prefix        = "${local.config.name_prefix}-${local.config.environment}"
  notification_email = var.alert_email

  depends_on = [module.gcp_apis]
}
