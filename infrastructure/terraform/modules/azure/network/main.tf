resource "azurerm_resource_group" "main" {
  for_each = local.locations

  name     = "${local.resource_prefix}-rg${local.location_suffixes[each.key]}"
  location = each.value.region
  tags     = local.labels
}

resource "azurerm_virtual_network" "main" {
  for_each = local.locations

  name                = "${local.resource_prefix}-vnet${local.location_suffixes[each.key]}"
  location            = each.value.region
  resource_group_name = azurerm_resource_group.main[each.key].name
  address_space       = [var.config.network.vpc_cidr]
  tags                = local.labels
}

resource "azurerm_subnet" "management" {
  for_each = local.locations

  name                            = "management"
  resource_group_name             = azurerm_resource_group.main[each.key].name
  virtual_network_name            = azurerm_virtual_network.main[each.key].name
  address_prefixes                = [var.config.network.management_subnet_cidr]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "workload" {
  for_each = local.locations

  name                            = "workload"
  resource_group_name             = azurerm_resource_group.main[each.key].name
  virtual_network_name            = azurerm_virtual_network.main[each.key].name
  address_prefixes                = [var.config.network.workload_subnet_cidr]
  default_outbound_access_enabled = false
}

resource "azurerm_public_ip" "nat" {
  for_each = local.locations

  name                = "${local.resource_prefix}-nat-ip${local.location_suffixes[each.key]}"
  location            = each.value.region
  resource_group_name = azurerm_resource_group.main[each.key].name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.labels
}

resource "azurerm_nat_gateway" "main" {
  for_each = local.locations

  name                = "${local.resource_prefix}-nat${local.location_suffixes[each.key]}"
  location            = each.value.region
  resource_group_name = azurerm_resource_group.main[each.key].name
  sku_name            = "Standard"
  tags                = local.labels
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  for_each = local.locations

  nat_gateway_id       = azurerm_nat_gateway.main[each.key].id
  public_ip_address_id = azurerm_public_ip.nat[each.key].id
}

resource "azurerm_subnet_nat_gateway_association" "management" {
  for_each = local.locations

  subnet_id      = azurerm_subnet.management[each.key].id
  nat_gateway_id = azurerm_nat_gateway.main[each.key].id
}

resource "azurerm_subnet_nat_gateway_association" "workload" {
  for_each = local.locations

  subnet_id      = azurerm_subnet.workload[each.key].id
  nat_gateway_id = azurerm_nat_gateway.main[each.key].id
}

resource "azurerm_subnet" "database" {
  count = local.managed_database_enabled ? 1 : 0

  name                 = "database"
  resource_group_name  = azurerm_resource_group.main[var.config.default_location].name
  virtual_network_name = azurerm_virtual_network.main[var.config.default_location].name
  address_prefixes     = [var.config.network.database_subnet_cidrs[0]]
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "postgresql"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone" "database" {
  count = local.managed_database_enabled ? 1 : 0

  name                = "${local.resource_prefix}.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main[var.config.default_location].name
  tags                = local.labels
}

resource "azurerm_private_dns_zone_virtual_network_link" "database" {
  count = local.managed_database_enabled ? 1 : 0

  name                  = "${local.resource_prefix}-postgres"
  resource_group_name   = azurerm_resource_group.main[var.config.default_location].name
  private_dns_zone_name = azurerm_private_dns_zone.database[0].name
  virtual_network_id    = azurerm_virtual_network.main[var.config.default_location].id
  registration_enabled  = false
  tags                  = local.labels
}
