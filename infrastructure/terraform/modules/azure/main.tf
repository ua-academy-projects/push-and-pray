data "azurerm_client_config" "current" {
  count = local.has_vms ? 1 : 0
}

check "infrastructure_host" {
  assert {
    condition = (
      !local.managed_database_enabled ||
      contains(keys(local.workload_vms), local.infrastructure_vm_name)
    )
    error_message = "service_placement.azure.infrastructure_host must name an Azure workload VM when database.mode is managed."
  }
}

resource "azurerm_resource_group" "main" {
  count = local.has_vms ? 1 : 0

  name     = "${local.resource_prefix}-rg"
  location = local.location
  tags     = local.common_labels
}

module "network" {
  source = "./network"
  count  = local.has_vms ? 1 : 0

  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  resource_prefix     = local.resource_prefix
  tags                = local.common_labels

  vpc_cidr                     = local.network_config.vpc_cidr
  management_subnet_cidr       = local.network_config.management_subnet_cidr
  workload_subnet_cidr         = local.network_config.workload_subnet_cidr
  managed_database_subnet_cidr = local.network_config.managed_database_subnet_cidr
  managed_database_enabled     = local.managed_database_enabled
}

module "security" {
  source = "./security"
  count  = local.has_vms ? 1 : 0

  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  resource_prefix     = local.resource_prefix
  tags                = local.common_labels

  vms                          = local.resolved_vms
  bastion_ssh_port             = local.bastion_vm.ssh_port
  bastion_allowed_cidrs        = local.bastion_vm.allowed_cidrs
  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  ui_public_ports              = local.config.network.ui_public_ports
  history_api_port             = local.config.service_ports.history_api
  postgresql_port              = local.config.service_ports.postgresql
  rabbitmq_port                = local.config.service_ports.rabbitmq
  redis_port                   = local.config.service_ports.redis
  k3s_node_cidr                = local.network_config.vpc_cidr
  tailscale_transit_remote_cidrs = [
    for cloud, network in local.config.network : network.vpc_cidr
    if contains(["gcp", "aws", "azure"], cloud) && cloud != local.cloud_key
  ]
  k3s_remote_node_cidrs = [
    for cloud, network in local.config.network : network.vpc_cidr
    if contains(["gcp", "aws", "azure"], cloud) && cloud != local.cloud_key
  ]
  managed_database_enabled = local.managed_database_enabled
  infrastructure_vm_name   = local.infrastructure_vm_name
}

resource "azurerm_subnet_network_security_group_association" "managed_database" {
  count = local.managed_database_enabled ? 1 : 0

  subnet_id                 = module.network[0].managed_database_subnet_id
  network_security_group_id = module.security[0].managed_database_nsg_id
}

module "vm" {
  source = "./vm"
  count  = local.has_vms ? 1 : 0

  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  resource_prefix     = local.resource_prefix
  common_labels       = local.common_labels
  ssh_users           = local.config.ssh_users
  vms                 = local.resolved_vms
  bastion_ssh_port    = local.bastion_vm.ssh_port

  management_subnet_id       = module.network[0].management_subnet_id
  workload_subnet_id         = module.network[0].workload_subnet_id
  network_security_group_ids = module.security[0].network_security_group_ids
}

resource "azurerm_route_table" "tailscale" {
  count               = local.has_vms ? 1 : 0
  name                = "${local.resource_prefix}-tailscale-routes"
  location            = azurerm_resource_group.main[0].location
  resource_group_name = azurerm_resource_group.main[0].name
  tags                = local.common_labels
}

resource "azurerm_route" "tailscale_remote_cloud" {
  for_each = local.has_vms ? {
    for cloud, network in local.config.network : cloud => network.vpc_cidr
    if contains(["gcp", "aws", "azure"], cloud) && cloud != local.cloud_key
  } : {}

  name                   = "to-${each.key}-tailscale"
  resource_group_name    = azurerm_resource_group.main[0].name
  route_table_name       = azurerm_route_table.tailscale[0].name
  address_prefix         = each.value
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = module.vm[0].private_ips[one([for name, vm in local.resolved_vms : name if vm.role == "bastion"])]
}

resource "azurerm_subnet_route_table_association" "tailscale_workload" {
  count          = local.has_vms ? 1 : 0
  subnet_id      = module.network[0].workload_subnet_id
  route_table_id = azurerm_route_table.tailscale[0].id
}

resource "random_password" "managed_database" {
  count = local.managed_database_enabled ? 1 : 0

  length           = 32
  special          = true
  override_special = "-_"
}

resource "random_password" "rabbitmq" {
  count = local.managed_database_enabled ? 1 : 0

  length           = 32
  special          = true
  override_special = "-_"
}

resource "random_password" "redis" {
  count = local.managed_database_enabled ? 1 : 0

  length           = 32
  special          = true
  override_special = "-_"
}

module "secrets" {
  source = "./secrets"
  count  = local.has_vms ? 1 : 0

  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  resource_prefix     = local.resource_prefix
  subscription_id     = local.config.clouds.azure.subscription_id
  tenant_id           = data.azurerm_client_config.current[0].tenant_id
  deployer_object_id  = data.azurerm_client_config.current[0].object_id
  tags                = local.common_labels

  secret_ids       = toset(local.all_secret_ids)
  secret_ids_by_vm = local.secret_ids_by_vm
  principal_ids    = module.vm[0].principal_ids
  secret_values = local.managed_database_enabled ? merge(
    { for id in local.managed_database_secret_ids : id => random_password.managed_database[0].result },
    { for id in local.rabbitmq_secret_ids : id => random_password.rabbitmq[0].result },
    { for id in local.redis_secret_ids : id => random_password.redis[0].result },
  ) : {}
}

module "database" {
  source = "./database"
  count  = local.managed_database_enabled ? 1 : 0

  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  zone                = local.config.regions[local.config.default_region][local.cloud_key].zone
  resource_prefix     = local.resource_prefix
  tags                = local.common_labels

  database               = local.config.database
  managed_settings       = local.config.database.managed.azure
  administrator_password = random_password.managed_database[0].result
  delegated_subnet_id    = module.network[0].managed_database_subnet_id
  private_dns_zone_id    = module.network[0].managed_database_private_dns_zone_id

  depends_on = [
    module.network,
    azurerm_subnet_network_security_group_association.managed_database,
  ]
}

module "monitoring" {
  source = "./monitoring"
  count  = local.monitoring_enabled ? 1 : 0

  resource_group_name = azurerm_resource_group.main[0].name
  resource_group_id   = azurerm_resource_group.main[0].id
  location            = azurerm_resource_group.main[0].location
  resource_prefix     = local.resource_prefix
  tags                = local.common_labels
  settings            = local.monitoring_settings
  virtual_machine_ids = module.vm[0].virtual_machine_ids
  uptime_hostname     = try(local.ui_vm.public_endpoint.hostname, null)
}
