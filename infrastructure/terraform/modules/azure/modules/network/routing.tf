# Azure routes between subnets and to the internet on its own; the routes to
# the other clouds through the bastion live in the routing module. Outbound NAT
# needs an address and a gateway attached to the subnet - no route pointing at
# it, and no public subnet for it to live in.
resource "azurerm_public_ip" "nat" {
  count = var.enable_nat_gateway ? 1 : 0

  name                = "${var.resource_prefix}-nat-ip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.profile.zone]

  tags = var.tags
}

resource "azurerm_nat_gateway" "main" {
  count = var.enable_nat_gateway ? 1 : 0

  name                = "${var.resource_prefix}-nat"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku_name            = "Standard"
  zones               = [var.profile.zone]

  tags = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  count = var.enable_nat_gateway ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.main[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

# The bastion answers through its own public address, so the management
# subnet stays without NAT.
resource "azurerm_subnet_nat_gateway_association" "workload" {
  count = var.enable_nat_gateway ? 1 : 0

  subnet_id      = azurerm_subnet.workload.id
  nat_gateway_id = azurerm_nat_gateway.main[0].id
}
