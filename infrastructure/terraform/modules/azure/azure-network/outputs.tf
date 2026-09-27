output "resource_group_name" {
  value = try(azurerm_resource_group.this[0].name, null)
}

output "location" {
  value = try(azurerm_resource_group.this[0].location, null)
}

output "virtual_network_id" {
  value = try(azurerm_virtual_network.this[0].id, null)
}

output "virtual_network_name" {
  value = try(azurerm_virtual_network.this[0].name, null)
}

output "subnet_ids" {
  value = { for name, subnet in azurerm_subnet.this : name => subnet.id }
}

output "database_subnet_id" {
  value = try(azurerm_subnet.database[0].id, null)
}

output "nat_public_ip" {
  value = try(azurerm_public_ip.nat[0].ip_address, null)
}
