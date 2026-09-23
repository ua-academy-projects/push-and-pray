resource "azurerm_virtual_network" "main" {
  count = var.has_selected_vms ? 1 : 0

  name                = "${local.resource_prefix}-vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = [var.vnet_cidr]
}

resource "azurerm_subnet" "management" {
  count = var.has_selected_vms ? 1 : 0

  name                 = "${local.resource_prefix}-management"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.config.network.management_subnet_cidr]
}

resource "azurerm_subnet" "workload" {
  count                = var.has_selected_vms ? 1 : 0
  name                 = "${local.resource_prefix}-workload"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.config.network.workload_subnet_cidr]
}

resource "azurerm_subnet" "database" {
  count = local.managed_db_enabled ? 1 : 0

  name                 = "${local.resource_prefix}-database"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 8, 2)] # 10.0.2.0/24

  delegation {
    name = "postgres"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}