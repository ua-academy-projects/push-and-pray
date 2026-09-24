resource "azurerm_subnet" "postgres" {
  count = local.postgres_enabled ? 1 : 0

  name                 = "${local.resource_prefix}-postgres"
  resource_group_name  = azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [var.config.clouds.azure.postgres_network.subnet_cidr]

  delegation {
    name = "postgres-flexible-server"

    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone" "postgres" {
  count = local.postgres_enabled ? 1 : 0

  name                = var.config.clouds.azure.postgres_network.private_dns_zone_name
  resource_group_name = azurerm_resource_group.main[0].name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  count = local.postgres_enabled ? 1 : 0

  name                 = "${local.resource_prefix}-postgres"
  private_dns_zone_id  = azurerm_private_dns_zone.postgres[0].id
  virtual_network_id   = azurerm_virtual_network.main[0].id
  registration_enabled = false
  tags                 = local.common_tags

  depends_on = [azurerm_subnet.postgres]
}
