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

module "aws_database" {
  source = "./modules/aws_database"
  count  = contains(local.enabled_clouds, "aws") ? 1 : 0

  config              = local.config
  vpc_id              = module.aws_network[0].vpc_id
  database_subnet_ids = module.aws_network[0].database_subnet_ids
  client_security_group_ids = {
    infra   = module.aws_network[0].security_group_ids_by_role["infra"]
    history = module.aws_network[0].security_group_ids_by_role["history"]
  }
  password_secret_arn = module.aws_basic[0].secret_arns[local.config.services.database.password_secret_id]
}

module "aws_monitoring" {
  source = "./modules/aws_monitoring"
  count  = contains(local.enabled_clouds, "aws") && local.config.monitoring.enabled ? 1 : 0

  config     = local.config
  role_names = module.aws_basic[0].role_names
  vms        = module.aws_vm[0].vms
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

module "gcp_database" {
  source = "./modules/gcp_database"
  count  = contains(local.enabled_clouds, "gcp") ? 1 : 0

  config             = local.config
  network_id         = module.gcp_network[0].network_id
  password_secret_id = module.gcp_basic[0].secret_ids[local.config.services.database.password_secret_id]

  depends_on = [module.gcp_network]
}

module "gcp_monitoring" {
  source = "./modules/gcp_monitoring"
  count  = contains(local.enabled_clouds, "gcp") && local.config.monitoring.enabled ? 1 : 0

  config                 = local.config
  service_account_emails = module.gcp_basic[0].service_account_emails
  vms                    = module.gcp_vm[0].vms
}

module "azure_basic" {
  source = "./modules/azure_basic"
  count  = contains(local.enabled_clouds, "azure") ? 1 : 0

  config = local.config
}

module "azure_network" {
  source = "./modules/azure_network"
  count  = contains(local.enabled_clouds, "azure") ? 1 : 0

  config = local.config
}

module "azure_vm" {
  source = "./modules/azure_vm"
  count  = contains(local.enabled_clouds, "azure") ? 1 : 0

  config = local.config
}

module "azure_database" {
  source = "./modules/azure_database"
  count  = contains(local.enabled_clouds, "azure") ? 1 : 0

  config = local.config
}

module "azure_monitoring" {
  source = "./modules/azure_monitoring"
  count  = contains(local.enabled_clouds, "azure") && local.config.monitoring.enabled ? 1 : 0

  config = local.config
}
