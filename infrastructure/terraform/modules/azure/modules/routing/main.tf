# Azure needs a route table only where the default routing is not enough:
# for the other clouds and the tailnet, which sit behind the bastion. Next
# hop VirtualAppliance names the bastion by address - which is why the
# bastion's address is fixed and a node's is not.
resource "azurerm_route_table" "via_bastion" {
  name                = "${var.resource_prefix}-via-bastion"
  resource_group_name = var.resource_group_name
  location            = var.location

  dynamic "route" {
    for_each = toset(var.destinations)

    content {
      name                   = "via-bastion-${replace(route.value, "/[./]/", "-")}"
      address_prefix         = route.value
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.bastion_internal_ip
    }
  }

  tags = var.tags
}

# Every subnet of the network, the bastion's own included. Tested on a live
# environment: with the table on the workload subnet alone, a node there could
# open connections to the other clouds, but nothing from another cloud or the
# tailnet reached it - the bastion received those packets and they went no
# further. Attaching the table to the management subnet as well is what made
# them arrive. The bastion itself sends traffic for these ranges into its
# tunnel before it leaves the host, so the routes pointing at it do not loop.
resource "azurerm_subnet_route_table_association" "this" {
  for_each = var.subnet_ids

  subnet_id      = each.value
  route_table_id = azurerm_route_table.via_bastion.id
}

moved {
  from = azurerm_subnet_route_table_association.workload
  to   = azurerm_subnet_route_table_association.this["workload"]
}
