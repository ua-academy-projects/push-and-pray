resource "azurerm_resource_group" "main" {
  count = local.is_active ? 1 : 0

  name     = local.resource_group_name
  location = local.profile.region

  tags = local.common_tags
}

module "network" {
  source = "./modules/network"
  count  = local.is_active ? 1 : 0

  resource_prefix     = local.resource_prefix
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  profile             = local.profile

  enable_nat_gateway = local.needs_nat_gateway
  tags               = local.common_tags
}

module "firewall" {
  source = "./modules/firewall"
  count  = local.is_active ? 1 : 0

  resource_prefix     = local.resource_prefix
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  subnet_ids          = module.network[0].subnet_ids
  cluster             = var.config.cluster
  tailscale           = var.config.tailscale
  network_cidr        = local.profile.network_cidr
  cluster_cidrs       = module.selection.cluster_cidrs
  remote_cidrs        = module.selection.remote_cidrs
  bastion             = var.config.bastion

  enable_bastion_ssh_bootstrap = var.enable_bastion_ssh_bootstrap
  tags                         = local.common_tags
}

# --------------------------------------------------------------------- bastion
# Core infrastructure, not a node: the cloud's Tailscale subnet router. Its
# specification is derived from the cloud profile rather than written into
# nodes, so it costs nothing to add a provider and cannot drift between them.

module "bastion_spec" {
  source = "../shared/bastion"
  count  = local.is_active ? 1 : 0

  config  = var.config
  cloud   = local.this_cloud
  profile = local.profile
  # Azure reserves the first four addresses of every subnet, like AWS.
  host_index = 4
}

module "bastion_identity" {
  source = "./modules/identity"
  count  = local.is_active ? 1 : 0

  name                = local.bastion_name
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  tags                = local.common_tags
}

module "bastion" {
  source = "./modules/vm"
  count  = local.is_active ? 1 : 0

  name                = local.bastion_name
  vm                  = module.bastion_spec[0].vm
  profile             = local.profile
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location

  identity_id = module.bastion_identity[0].id
  subnet_id   = module.network[0].management_subnet_id
  application_security_group_ids = {
    bastion = module.firewall[0].application_security_group_ids["bastion"]
  }

  ssh_users = var.config.ssh_users

  tags = merge(local.common_tags, { role = "bastion" })
}


module "routing" {
  source = "./modules/routing"
  count  = local.is_active ? 1 : 0

  resource_prefix     = local.resource_prefix
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  destinations        = module.selection.remote_cidrs
  bastion_internal_ip = module.bastion_spec[0].internal_ip
  subnet_ids          = module.network[0].subnet_ids
  tags                = local.common_tags
}

# ----------------------------------------------------------------------- nodes

module "identity" {
  source   = "./modules/identity"
  for_each = local.nodes

  name                = "${local.resource_prefix}-${each.key}"
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  tags                = local.common_tags
}

module "vm" {
  source   = "./modules/vm"
  for_each = local.nodes

  name                = "${local.resource_prefix}-${each.key}"
  vm                  = each.value
  profile             = local.profile
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location

  identity_id = module.identity[each.key].id

  subnet_id = module.network[0].workload_subnet_id
  application_security_group_ids = merge(
    { (each.value.role) = module.firewall[0].application_security_group_ids[each.value.role] },
    each.value.assign_public_ip ? { ingress = module.firewall[0].application_security_group_ids["ingress"] } : {},
  )

  ssh_users = var.config.ssh_users

  tags = merge(local.common_tags, { role = each.value.role })
}

# ---------------------------------------------------------- observability

module "logging" {
  source = "./modules/logging"
  count  = local.is_active ? 1 : 0

  resource_prefix     = local.resource_prefix
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  instances           = local.instances
  retention_days      = try(var.config.observability.log_retention_days, 30)
  tags                = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"
  count  = local.is_active ? 1 : 0

  resource_prefix     = local.resource_prefix
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  instances           = local.instances
  thresholds          = try(var.config.observability.thresholds, {})
  tags                = local.common_tags
}

module "alerting" {
  source = "./modules/alerting"
  count  = local.is_active ? 1 : 0

  resource_prefix     = local.resource_prefix
  resource_group_name = azurerm_resource_group.main[0].name
  resource_group_id   = azurerm_resource_group.main[0].id
  location            = azurerm_resource_group.main[0].location
  email               = var.config.observability.alert_email
  metrics             = module.monitoring[0].metrics
  window_minutes      = module.monitoring[0].window_minutes
  memory_threshold_mb = module.monitoring[0].memory_threshold_mb
  instances           = local.instances
  workspace_id        = module.logging[0].workspace_id
  budget_usd          = try(local.profile.budget_usd, null)
  tags                = local.common_tags
}
