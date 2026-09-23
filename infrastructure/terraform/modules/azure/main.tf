module "resource_group" {
  source = "./resource_group"

  config           = var.config
  has_selected_vms = local.has_selected_vms
}
module "network" {
  source = "./network"

  config              = var.config
  has_selected_vms    = local.has_selected_vms
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
}

module "security" {
  source = "./security"

  config               = var.config
  has_selected_vms     = local.has_selected_vms
  resource_group_name  = module.resource_group.name
  location             = module.resource_group.location
  selected_vms         = local.selected_vms
  management_subnet_id = module.network.management_subnet_id
  workload_subnet_id   = module.network.workload_subnet_id
}

module "iam" {
  source = "./iam"

  config              = var.config
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  selected_vms        = local.selected_vms
}

module "vm" {
  source = "./vm"

  config               = var.config
  selected_vms         = local.selected_vms
  resource_group_name  = module.resource_group.name
  location             = module.resource_group.location
  management_subnet_id = module.network.management_subnet_id
  workload_subnet_id   = module.network.workload_subnet_id
  identity_ids         = module.iam.identity_ids
}

module "secrets" {
  source = "./secrets"

  config                        = var.config
  has_selected_vms              = local.has_selected_vms
  selected_vms                  = local.selected_vms
  resource_group_name           = module.resource_group.name
  location                      = module.resource_group.location
  principal_ids                 = module.iam.principal_ids
  azure_secret_version_managers = var.azure_secret_version_managers
}

module "postgres" {
  source = "./postgres"

  config                      = var.config
  has_selected_vms            = local.has_selected_vms
  resource_group_name         = module.resource_group.name
  location                    = module.resource_group.location
  delegated_subnet_id         = module.network.database_subnet_id
  vnet_id                     = module.network.vnet_id
  key_vault_id                = module.secrets.key_vault_id
  postgres_password_secret_id = local.postgres_password_secret_id

  depends_on = [module.network, module.secrets]
}

module "monitoring" {
  source = "./monitoring"

  config              = var.config
  selected_vms        = local.selected_vms
  has_selected_vms    = local.has_selected_vms
  instance_ids        = module.vm.ids
  resource_group_id   = module.resource_group.id
  resource_group_name = module.resource_group.name
}

resource "random_password" "rabbitmq" {
  count   = local.has_selected_vms && local.managed_db_enabled ? 1 : 0
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "rabbitmq" {
  count = local.has_selected_vms && local.managed_db_enabled && local.rabbitmq_password_secret_id != null ? 1 : 0

  name         = local.rabbitmq_password_secret_id
  value        = random_password.rabbitmq[0].result
  key_vault_id = module.secrets.key_vault_id
}

resource "random_password" "redis" {
  count   = local.has_selected_vms && local.managed_db_enabled ? 1 : 0
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "redis" {
  count = local.has_selected_vms && local.managed_db_enabled && local.redis_password_secret_id != null ? 1 : 0

  name         = local.redis_password_secret_id
  value        = random_password.redis[0].result
  key_vault_id = module.secrets.key_vault_id
}