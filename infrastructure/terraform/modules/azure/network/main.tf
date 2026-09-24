resource "azurerm_resource_group" "main" {
  count = local.enabled ? 1 : 0

  name     = var.config.clouds.azure.resource_group_name
  location = local.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "main" {
  count = local.enabled ? 1 : 0

  name                = "${local.resource_prefix}-vnet"
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  address_space       = [var.config.clouds.azure.vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "main" {
  for_each = local.enabled ? local.subnet_cidrs : {}

  name                 = "${local.resource_prefix}-${each.key}"
  resource_group_name  = azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = [each.value]
}
