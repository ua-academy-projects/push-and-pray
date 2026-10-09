output "primary_to_region_ids" {
  value = { for region, peering in azurerm_virtual_network_peering.primary_to_region : region => peering.id }
}

output "region_to_primary_ids" {
  value = { for region, peering in azurerm_virtual_network_peering.region_to_primary : region => peering.id }
}
