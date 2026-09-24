resource "azurerm_public_ip" "nat" {
  count = local.enabled && length(local.nat_subnets) > 0 ? 1 : 0

  name                = "${local.resource_prefix}-nat-ip"
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway" "main" {
  count = local.enabled && length(local.nat_subnets) > 0 ? 1 : 0

  name                = "${local.resource_prefix}-nat"
  resource_group_name = azurerm_resource_group.main[0].name
  location            = azurerm_resource_group.main[0].location
  sku_name            = "Standard"
  tags                = local.common_tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  count = local.enabled && length(local.nat_subnets) > 0 ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.main[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "main" {
  for_each = local.enabled ? local.nat_subnets : toset([])

  subnet_id      = azurerm_subnet.main[each.value].id
  nat_gateway_id = azurerm_nat_gateway.main[0].id
}
