resource "azurerm_virtual_network" "this" {
  for_each = local.placements

  name                = "${local.resource_prefix}-${each.key}-vnet"
  location            = each.value.region
  resource_group_name = var.resource_group_name
  address_space       = [var.config.network.vpc_cidr]
  tags                = local.tags
}

resource "azurerm_subnet" "public" {
  for_each = local.placements

  name                 = "${local.resource_prefix}-${each.key}-public"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this[each.key].name
  address_prefixes     = [var.config.network.public_subnet_cidr]
}

resource "azurerm_subnet" "private" {
  for_each = local.placements

  name                 = "${local.resource_prefix}-${each.key}-private"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this[each.key].name
  address_prefixes     = [var.config.network.private_subnet_cidr]
}

resource "azurerm_public_ip" "nat" {
  for_each = local.placements

  name                = "${local.resource_prefix}-${each.key}-nat-ip"
  location            = each.value.region
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = try([each.value.zone], null)
  tags                = local.tags
}

resource "azurerm_nat_gateway" "this" {
  for_each = local.placements

  name                    = "${local.resource_prefix}-${each.key}-nat"
  location                = each.value.region
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  zones                   = try([each.value.zone], null)
  tags                    = local.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  for_each = local.placements

  nat_gateway_id       = azurerm_nat_gateway.this[each.key].id
  public_ip_address_id = azurerm_public_ip.nat[each.key].id
}

resource "azurerm_subnet_nat_gateway_association" "private" {
  for_each = local.placements

  subnet_id      = azurerm_subnet.private[each.key].id
  nat_gateway_id = azurerm_nat_gateway.this[each.key].id
}
