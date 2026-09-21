module "gcp_database" {
  source = "./modules/gcp/database"

  config  = local.config
  network = module.gcp_network
}

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

module "aws_database" {
  source = "./modules/aws/database"

  config  = local.config
  network = module.aws_network
}

module "aws_budget" {
  source = "./modules/aws/budget"

  name     = "${local.config.name_prefix}-${local.config.environment}-account-monthly"
  settings = try(local.raw_config.budgets.aws, {})
}

module "gcp_budget" {
  source     = "./modules/gcp/budget"
  name       = "${local.config.name_prefix}-${local.config.environment}-project-monthly"
  settings   = try(local.raw_config.budgets.gcp, {})
  project_id = try(local.config.clouds.gcp.project_id, null)
  depends_on = [module.gcp_monitoring]
}

module "aws_monitoring" {
  source = "./modules/aws/monitoring"

  config   = local.config
  vms      = module.aws_vm.vms
  database = module.aws_database.monitoring
}

module "gcp_monitoring" {
  source = "./modules/gcp/monitoring"

  config   = local.config
  vms      = module.gcp_vm.vms
  database = module.gcp_database.monitoring
}

module "cloudflare_dns" {
  source = "./modules/cloudflare/dns"

  config  = local.config
  aws_vms = module.aws_vm.vms
  gcp_vms = module.gcp_vm.vms
}

