# The GCP tree still carries the Compose-era design. Its monitoring module
# cannot build a for_each during an import, because local.enabled chains back to
# module.gcp_database.monitoring, which is unknown outside a full plan. So these
# stay commented until modules/gcp/* is converted, as with the Azure tree above.
# Uncomment together with the matching outputs in outputs.tf.
# module "gcp_database" {
#   source = "./modules/gcp/database"
#
#   config  = local.config
#   network = module.gcp_network
# }
#
# module "gcp_network" {
#   source = "./modules/gcp/network"
#
#   config = local.config
# }
#
# module "gcp_vm" {
#   source = "./modules/gcp/vm"
#
#   config  = local.config
#   network = module.gcp_network
# }

module "aws_network" {
  source = "./modules/aws/network"

  config = local.config
}

module "aws_vm" {
  source = "./modules/aws/vm"

  config  = local.config
  network = module.aws_network
}

# module "gcp_secrets" {
#   source = "./modules/gcp/secrets"
#
#   config                  = local.config
#   vms                     = module.gcp_vm.vms
#   secret_version_managers = var.secret_version_managers
# }

module "aws_secrets" {
  source = "./modules/aws/secrets"

  config = local.config
}

module "aws_registry" {
  source = "./modules/aws/registry"

  config = local.config
  vm     = module.aws_vm
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

# module "gcp_budget" {
#   source     = "./modules/gcp/budget"
#   name       = "${local.config.name_prefix}-${local.config.environment}-project-monthly"
#   settings   = try(local.raw_config.budgets.gcp, {})
#   project_id = try(local.config.clouds.gcp.project_id, null)
#   depends_on = [module.gcp_monitoring]
# }

# The Azure tree still carries the Compose-era design and reads configuration
# keys the k3s schema removed. A locals block is evaluated whichever value count
# takes, so these stay commented until modules/azure/* is converted. Uncomment
# together with the matching outputs in outputs.tf.
# module "azure_network" {
#   source = "./modules/azure/network"
#
#   config = local.config
# }
#
# module "azure_vm" {
#   source = "./modules/azure/vm"
#
#   config  = local.config
#   network = module.azure_network
# }
#
# module "azure_secrets" {
#   source = "./modules/azure/secrets"
#
#   config                  = local.config
#   network                 = module.azure_network
#   vms                     = module.azure_vm.vms
#   secret_version_managers = var.azure_secret_version_managers
# }
#
# module "azure_database" {
#   source = "./modules/azure/database"
#
#   config  = local.config
#   network = module.azure_network
#   vault   = module.azure_secrets.vault
# }
#
# module "azure_budget" {
#   source = "./modules/azure/budget"
#
#   name              = "${local.config.name_prefix}-${local.config.environment}-group-monthly"
#   settings          = try(local.raw_config.budgets.azure, {})
#   resource_group_id = module.azure_network.resource_group_id
# }

module "aws_monitoring" {
  source = "./modules/aws/monitoring"

  config   = local.config
  vms      = module.aws_vm.vms
  database = module.aws_database.monitoring
}

# module "gcp_monitoring" {
#   source = "./modules/gcp/monitoring"
#
#   config   = local.config
#   vms      = module.gcp_vm.vms
#   database = module.gcp_database.monitoring
# }

# module "azure_monitoring" {
#   source = "./modules/azure/monitoring"
#
#   config   = local.config
#   network  = module.azure_network
#   vms      = module.azure_vm.vms
#   database = module.azure_database.monitoring
# }

module "cloudflare_dns" {
  source = "./modules/cloudflare/dns"

  config = local.config
  vm     = module.aws_vm
}

