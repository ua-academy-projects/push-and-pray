output "networks" {
  description = "Azure network identifiers keyed by logical location."
  value = {
    for location, placement in local.placements : location => {
      region            = placement.region
      zone              = try(placement.zone, null)
      vnet_id           = azurerm_virtual_network.this[location].id
      vnet_name         = azurerm_virtual_network.this[location].name
      public_subnet_id  = azurerm_subnet.public[location].id
      private_subnet_id = azurerm_subnet.private[location].id
    }
  }
}
