resource "azurerm_resource_group" "this" {
  count = local.enabled ? 1 : 0

  name     = "${local.resource_prefix}-rg"
  location = local.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "this" {
  count = local.enabled ? 1 : 0

  name                = "${local.resource_prefix}-vnet"
  location            = azurerm_resource_group.this[0].location
  resource_group_name = azurerm_resource_group.this[0].name
  address_space       = [local.vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "this" {
  for_each = local.enabled ? {
    management = local.network.management_subnet_cidr
    workload   = local.network.workload_subnet_cidr
  } : {}

  name                 = "${local.resource_prefix}-${each.key}"
  resource_group_name  = azurerm_resource_group.this[0].name
  virtual_network_name = azurerm_virtual_network.this[0].name
  address_prefixes     = [each.value]
}

resource "azurerm_subnet" "database" {
  count = var.create_database_subnet ? 1 : 0

  name                 = "${local.resource_prefix}-database"
  resource_group_name  = azurerm_resource_group.this[0].name
  virtual_network_name = azurerm_virtual_network.this[0].name
  address_prefixes     = [var.database_subnet_cidr]

  delegation {
    name = "postgresql-flexible-server"

    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_public_ip" "nat" {
  count = var.create_workload_nat_gateway ? 1 : 0

  name                = "${local.resource_prefix}-nat-ip"
  location            = azurerm_resource_group.this[0].location
  resource_group_name = azurerm_resource_group.this[0].name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway" "this" {
  count = var.create_workload_nat_gateway ? 1 : 0

  name                = "${local.resource_prefix}-nat"
  location            = azurerm_resource_group.this[0].location
  resource_group_name = azurerm_resource_group.this[0].name
  sku_name            = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count = var.create_workload_nat_gateway ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "workload" {
  count = var.create_workload_nat_gateway ? 1 : 0

  subnet_id      = azurerm_subnet.this["workload"].id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}
